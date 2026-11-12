# Tanzu MCP Gateway with AgentMinder

## Overview

This repo shows how to put two gateways in front of an MCP server, so each one does what it's good at:

- The **Tanzu MCP Gateway** (the `mcp-gateway` service of Tanzu Platform's GenAI tile) is the platform's single front door for MCP servers. It's a marketplace service, and it gives one route for every registered server plus gateway metrics. With the Service Publisher tile it also makes MCP servers discoverable in the marketplace.
- **AgentMinder** knows who the agent is and decides which tools that agent may use. Its AI Gateway checks each MCP call against policy, and it hides the tools the agent isn't granted.

Here the Tanzu MCP Gateway forwards the agent's AgentMinder token to the AgentMinder AI Gateway, unchanged. AgentMinder enforces per-tool access and passes the call to the MCP server. The scripts build the whole chain with a small echo MCP server that has a read tool and a write tool. The agent starts with both. Revoking its write permission in AgentMinder takes the write tool away within seconds, with no change to the agent or the Tanzu gateway.

## How it works

```mermaid
flowchart LR
  agent([Agent])
  idp[AgentMinder<br/>token endpoint]
  tanzu[Tanzu MCP Gateway<br/>https://gw-route/echo/mcp]
  am[AgentMinder AI Gateway<br/>/aigateway/v1/mcp/app-id]
  mcp[MCP server<br/>echo-mcp]

  agent -- "1. client_credentials<br/>scope=urn:iam:myscopes<br/>resource=AgentMinder gateway URL" --> idp
  idp -- "token with intent scopes<br/>for the granted tools" --> agent
  agent -- "2. MCP call + bearer token" --> tanzu
  tanzu -- "3. forward_token:<br/>same bearer token" --> am
  am -- "4. tool allowed by policy?<br/>adds identity headers" --> mcp
```

1. The agent gets a token from AgentMinder for the AgentMinder gateway URL. The token carries the intents, or permissions, the agent's policy grants, for example `urn:iam:agent:intent:echo.read`. Each intent unlocks one or more tools.
2. The agent calls the Tanzu MCP Gateway at `https://<gateway route>/<server name>/mcp`.
3. The Tanzu MCP Gateway has the AgentMinder gateway URL registered as an off-platform server, with `auth.mode: forward_token`. It passes the bearer token on as it is.
4. AgentMinder validates the token, checks the policy, filters `tools/list` to the tools the agent's intents unlock, refuses other tool calls, and forwards allowed calls to the MCP server with the same token and extra identity headers.

Details, the sequence diagram and what each layer enforces are in [docs/architecture.md](docs/architecture.md).

## Quick start

Prerequisites:

- Tanzu Platform for Cloud Foundry 11.0 with the GenAI tile 11.0, which offers the `mcp-gateway` service (plan `gateway`). Tested on TPCF 11.0.1.
- An AgentMinder tenant and a tenant admin client (client ID and secret, `client_credentials` grant). Tested with AgentMinder 4.1.1.
- The Tanzu MCP Gateway must trust AgentMinder's TLS certificate. If AgentMinder uses a private CA, add the CA to the Ops Manager Director's trusted certificates and Apply Changes. See [docs/faq.md](docs/faq.md#how-does-the-gateway-trust-a-private-ca).
- `cf` CLI v8 or later, logged in, with an org where you can create a space (or an existing space where you can push apps and create services). `curl`, `jq` and `python3` (standard library only).
- Node 22 or later for the [MCP Inspector](https://github.com/modelcontextprotocol/inspector) CLI, which the tests use. Optional: without Node, the tests fall back to curl. See [docs/testing.md](docs/testing.md).

Steps:

1. Configure:

   ```bash
   cp config.env.example config.env
   $EDITOR config.env
   ```

2. Push the echo MCP server. This creates `CF_SPACE` in `CF_ORG` if it doesn't exist:

   ```bash
   scripts/01-deploy-echo-mcp.sh
   ```

3. Create the AgentMinder resource server, agent client and policy. Intent `echo.read` unlocks the `whoami` tool and `echo.write` unlocks `reset`. The policy grants the agent both:

   ```bash
   scripts/02-agentminder-setup.py
   ```

4. Create the Tanzu MCP Gateway with the AgentMinder gateway URL as its server:

   ```bash
   scripts/03-create-gateway.sh
   ```

5. Test the chain:

   ```bash
   scripts/04-test.sh
   ```

   Expected result:

   ```
   PASS  1. token carries echo.read and echo.write
   PASS  2. both tools listed; whoami works and the server got the agent's token unchanged
   PASS  3. after revoking echo.write, the same token loses reset and keeps whoami
   PASS  4. reset straight at AgentMinder is 403
   PASS  5. a call with no token is refused
   PASS  6. after granting echo.write back, the same token can call reset again
   ```

   To show it live in the MCP Inspector UI, see [docs/demo.md](docs/demo.md).

6. Clean up:

   ```bash
   scripts/99-cleanup.sh
   ```

To put a real MCP server behind the chain, see [docs/faq.md](docs/faq.md#how-do-i-use-my-own-mcp-server).

## Repo structure

```
config.env.example             settings for the scripts; copy to config.env
echo-mcp/                      test MCP server: answers each call with the headers and token claims it got
scripts/01-deploy-echo-mcp.sh  pushes echo-mcp
scripts/02-agentminder-setup.py creates the AgentMinder objects through the admin API
scripts/03-create-gateway.sh   creates or updates the mcp-gateway service instance
scripts/04-test.sh             end-to-end checks, with MCP Inspector or the curl fallback
scripts/agent-token.sh         prints a token for the demo agent
scripts/demo.sh                grants or revokes the agent's echo.read and echo.write intents
scripts/demo-ui.sh             opens the MCP Inspector web UI as the demo agent
scripts/99-cleanup.sh          deletes everything the scripts made
scripts/lib.sh, mcp.sh         shared helpers (config, the Inspector wrapper, a minimal curl MCP client)
docs/architecture.md           components, call sequence, what each layer enforces
docs/agentminder-api.md        the AgentMinder objects and API calls the setup makes
docs/decisions.md              why the chain is built this way
docs/demo.md                   presenter steps for a live grant and revoke in the Inspector UI
docs/faq.md                    gotchas and how-tos
docs/testing.md                installing MCP Inspector, using it by hand, the curl fallback
docs/validation.md             test results from the reference environment
```
