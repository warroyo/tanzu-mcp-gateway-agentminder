#!/usr/bin/env bash
# Creates the Tanzu MCP Gateway (or updates it) with one server: the
# AgentMinder gateway URL for the echo server, in forward_token mode.
#
# Every update REPLACES env and mcp-servers, so this always sends the full
# parameter set. The params are kept in .state/gateway-params.json.
. "$(dirname "$0")/lib.sh"

AM_GATEWAY_URL=$(jq -r '.gateway_url // empty' "$STATE/agentminder.json" 2>/dev/null || true)
[ -n "$AM_GATEWAY_URL" ] || { echo "run 02-agentminder-setup.py first" >&2; exit 1; }

# SSL_CERT_FILE: the gateway is a Python app. On Kubernetes resource
# segment hosts its default CA path misses the platform's trusted
# certificates, so it can't verify AgentMinder or UAA. Pointing it at the
# bundle file fixes that. Harmless elsewhere. See docs/faq.md.
jq -n --arg name "$GATEWAY_SERVER_NAME" --arg url "$AM_GATEWAY_URL" '{
  env: {SSL_CERT_FILE: "/etc/ssl/certs/ca-certificates.crt"},
  "mcp-servers": [{
    name: $name,
    url: $url,
    auth: {mode: "forward_token"},
    metadata: {description: "Echo MCP server, behind the AgentMinder AI Gateway"}
  }]
}' > "$STATE/gateway-params.json"

cf target -o "$CF_ORG" -s "$CF_SPACE" >/dev/null
if cf service "$GATEWAY_NAME" >/dev/null 2>&1; then
  cf update-service "$GATEWAY_NAME" -c "$STATE/gateway-params.json" --wait
else
  cf create-service mcp-gateway gateway "$GATEWAY_NAME" -c "$STATE/gateway-params.json" --wait
fi

ROUTE=$(gateway_route)
echo "$ROUTE" > "$STATE/gateway-route"
echo "agents call: $ROUTE/$GATEWAY_SERVER_NAME/mcp"
