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

The Tanzu MCP Gateway only passes on calls to tools it listed in the same session, and its list is what AgentMinder returns: the granted tools only. So after a revoke the Tanzu gateway refuses `reset` itself as `Unknown tool: 'reset'`, and the call never reaches AgentMinder. Straight at AgentMinder, the same call gets 403.

A client that calls a tool without `tools/list` first in that session gets `Unknown tool` even for a granted tool. MCP clients normally list first.

## Do I need a new token after a policy change?

Only when the token doesn't carry the intent. AgentMinder checks two things on every call: the intent is in the token's scope, which is fixed when the token is minted, and the policy grants it now. Tested by changing the policy through the admin API:

| Change | Token that carries the intent | Token minted while the intent was revoked |
|---|---|---|
| Revoke the intent | Refused within about 30 seconds | Refused |
| Grant it back | Allowed again within about 40 seconds | Still refused: get a new token |
| Remove a tool's binding | Refused, for every agent | Refused |
| Add the binding back | Allowed again | Allowed again |

A token minted after a grant carries the intent after about 20 seconds. Short token lifetimes keep that wait short: an agent that gets a new token every minute picks up a new intent within a minute.

Removing a tool's binding on the resource server works as a kill switch: the tool goes away for every agent, and comes back when the binding does, without new tokens. The call is refused with 401.

## Why does the AgentMinder gateway URL return 404 "no matching route"?

The route takes 30 to 60 seconds to register after the resource server is created. `scripts/04-test.sh` waits for it.

## Which headers does an MCP call to AgentMinder need?

`MCP-Protocol-Version` on every request, and the `Mcp-Session-Id` from `initialize` on every later request. `scripts/mcp.sh` is a minimal client that sends both.

## How do agents discover the gateway's servers?

From `<gateway route>/registry.json`, which lists each server and its endpoint URL. Bind credentials are empty, so binding doesn't help. For marketplace discovery, the Service Publisher tile publishes a CF app as its own offering. See [architecture.md](architecture.md#discovery).

## The gateway route returns 404

The route's root serves nothing on the build tested here, although the AI Services docs show a dashboard there. The MCP endpoints are at `<route>/<server name>/mcp`, the server list at `<route>/registry.json`, and a health check at `<route>/health`. Usage metrics are in Tanzu Hub: Marketplace, Service Offerings, MCP Gateway, Usage.

## The gateway service won't delete

If `cf delete-service` fails at the broker, `cf purge-service-instance <name>` removes the record. Then delete the gateway app and its `mcp-gateway-<instance guid>` space in the `system` org by hand.
