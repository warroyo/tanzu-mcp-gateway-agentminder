# Decisions

## AgentMinder sits behind the Tanzu MCP Gateway, not in front of it

2026-11-11.

**Context.** Both products are gateways for MCP. The Tanzu MCP Gateway is the platform's front door. AgentMinder holds agent identity and per-tool policy.

**Decision.** The agent calls the Tanzu MCP Gateway. The gateway's registered server is the AgentMinder AI Gateway URL, in `forward_token` mode, so the agent's AgentMinder token reaches AgentMinder unchanged. AgentMinder forwards to the MCP server.

**Rejected.**
- *AgentMinder in front, pointing at the Tanzu gateway.* AgentMinder would see the Tanzu gateway as one server, and the platform's front door would sit behind the policy layer.
- *Tanzu gateway only.* Its auth modes check that a token is present and pass it on. They don't know which agent may call which tool.

## Register the server with `mcp-servers`, not a bind

2026-11-11.

**Decision.** The script lists the AgentMinder gateway URL in the gateway's `mcp-servers` parameter. It is the only way to give the gateway a URL as the upstream.

**Rejected.** *Binding the MCP server app.* Bind parameters have no URL field: a bound app needs an `apps.internal` route, and the gateway calls the app on that route directly, which skips AgentMinder.

## Intents are permissions, granted per agent

2026-11-12.

**Decision.** Two intents shaped like permissions: `echo.read` unlocks `whoami` and `echo.write` unlocks `reset`. The agent starts with both, and the demo revokes `echo.write`.

**Why.** That's how a security admin thinks about it: an agent gets read or write on a server, not a list of tool names. A revoke and a grant back both reach the token the agent already holds.

**Rejected.** *A per-tool deny rule in a policy.* AgentMinder 4.1.1 policy conditions match the caller, not the tool.
