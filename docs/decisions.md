# Decisions

## AgentMinder sits behind the Tanzu MCP Gateway, not in front of it

2026-11-11.

**Context.** Both products are gateways for MCP. The Tanzu MCP Gateway is the platform's front door and, with Service Publisher, its catalog. AgentMinder holds agent identity and per-tool policy.

**Decision.** The agent calls the Tanzu MCP Gateway. The gateway's registered server is the AgentMinder AI Gateway URL, and AgentMinder forwards to the MCP server.

**Rejected.**
- *AgentMinder in front, pointing at the Tanzu gateway.* AgentMinder would then authorize calls to the Tanzu gateway as one server, so the platform's front door and catalog would sit behind the policy layer, hidden from agents.
- *Tanzu gateway only.* Its auth modes check that a token is present and pass it on. They don't know which agent may call which tool.

## forward_token mode

2026-11-11.

**Context.** An off-platform server in the gateway's `mcp-servers` parameter takes `auth.mode` `forward_token` or `oauth_passthrough`.

**Decision.** `forward_token`. The agent already holds an AgentMinder token for the AgentMinder gateway URL, and AgentMinder needs that exact token.

**Not tried.** `oauth_passthrough`. `forward_token` already hands AgentMinder the token it needs, on the first call.

## Register the server through the create parameters, not a bind

2026-11-11.

**Context.** A server can be registered by binding a CF app to the gateway, or by listing a URL in the `mcp-servers` create parameter.

**Decision.** The `mcp-servers` parameter. The registered target is the AgentMinder gateway URL, which isn't a CF app, so it can't be bound.

**Consequence.** Every `cf update-service` replaces the whole `mcp-servers` list and `env`. The script keeps the full parameter set in one file and always sends all of it.

## A test MCP server that reports what it receives

2026-11-11.

**Decision.** Test with `echo-mcp`, which returns the header names and token claims it gets, instead of a real MCP server.

**Why.** It proves the token reaches the server unchanged (same SHA-256), shows which headers AgentMinder adds, and has a tool to grant and a tool to deny, with no side effects.
