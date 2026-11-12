# FAQ

## How do I use my own MCP server?

1. Run it anywhere AgentMinder can reach over HTTPS: as a CF app, on Kubernetes, or elsewhere.
2. Make it validate the bearer token: the issuer is the AgentMinder tenant, the signature checks out against the tenant's keys, and the audience includes the **AgentMinder gateway URL**. That URL is the token's audience, not the server's own URL, so a server that only accepts its own URL refuses every call that comes through AgentMinder.
3. In `scripts/02-agentminder-setup.py`, set the server URL and the `TOOLS` and `GRANTED` lists to your tool names.
4. Run steps 2 to 4 of the quick start.

Validating the token at the server matters because the Tanzu MCP Gateway doesn't, and the server's own route can be called without going through either gateway.

## Why does the gateway set SSL_CERT_FILE?

The gateway is a Python app. It looks CA certificates up by hash link in `/etc/ssl/certs`. On the hosts of a Kubernetes resource segment, those links come from the image and only cover the public CAs. The platform's trusted certificates are in the bundle file `/etc/ssl/certs/ca-certificates.crt`. So without the setting, gateway instances there can't verify AgentMinder or the platform's UAA. Instances on BOSH Diego cells aren't affected.

`scripts/03-create-gateway.sh` passes `{"env": {"SSL_CERT_FILE": "/etc/ssl/certs/ca-certificates.crt"}}` in the create parameters. This is a workaround for a known issue that is being fixed. It does no harm on cells that don't need it.

## How does the gateway trust a private CA?

Add the CA to Ops Manager: BOSH Director tile, Security, Trusted Certificates. Then Apply Changes, including the TAS tile for Diego cells and the Kubernetes resource segment tile for its hosts. Restart the gateway app afterwards (`cf restart` in its `system` space, or `cf update-service` with the full parameters).

## Why does an update lose my servers or settings?

`cf update-service` replaces `env` and `mcp-servers` with what you send. An update without them clears them. A gateway that lost `SSL_CERT_FILE` on a Kubernetes segment host can then fail its next update with `list-backing-servers: unexpected status 500`. To recover, set the variable on the gateway app by hand (`cf set-env` in org `system`, space `mcp-gateway-<instance guid>`), restart it, then update with the full parameters. Always update with the whole parameter file.

## Why does a call without a token fail with "missing MCP-Protocol-Version header"?

The Tanzu MCP Gateway answers `initialize` itself, with or without a token. The first call it passes on reaches AgentMinder without the `MCP-Protocol-Version` header, and AgentMinder answers `400 AI Gateway: missing MCP-Protocol-Version header`. The call is refused either way, but the error is misleading. Straight at AgentMinder, the same call without a token gets 401.

## Why does a denied tool say "Unknown tool"?

The Tanzu MCP Gateway only passes on calls to tools it listed in the same session, and its list is what AgentMinder returns: the granted tools only. So the Tanzu gateway refuses `denyme` itself as `Unknown tool: 'denyme'`, and the call never reaches AgentMinder. Straight at AgentMinder, the same call gets 403.

A client that calls a tool without `tools/list` first in that session gets `Unknown tool` even for a granted tool. MCP clients normally list first.

## Do I need a new token after a policy change?

For a grant, yes. For a revoke, no. Tested by changing the policy through the admin API and waiting 45 seconds:

| Change | Token minted before the change | Token minted after |
|---|---|---|
| Grant `denyme` | Still refused: the token has no `denyme` intent | Allowed |
| Revoke `denyme` | Refused, although the token still has the intent | Refused |

AgentMinder needs both: the intent in the token, and a current grant in the policy. A grant reaches newly minted tokens after about 20 seconds.

## Why does the AgentMinder gateway URL return 404 "no matching route"?

The route takes 30 to 60 seconds to register after the resource server is created. `scripts/04-test.sh` waits for it.

## Which headers does an MCP call to AgentMinder need?

`MCP-Protocol-Version` on every request, and the `Mcp-Session-Id` from `initialize` on every later request. `scripts/mcp.sh` is a minimal client that sends both.

## How do agents discover the gateway's servers?

Not through the gateway on its own: it has no catalog and the bind credentials are empty. Use the Service Publisher tile. See [architecture.md](architecture.md#discovery).

## The gateway service won't delete

If `cf delete-service` fails at the broker, `cf purge-service-instance <name>` removes the record. Then delete the gateway app and its `mcp-gateway-<instance guid>` space in the `system` org by hand.
