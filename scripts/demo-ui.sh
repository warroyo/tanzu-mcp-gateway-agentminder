#!/usr/bin/env bash
# Opens the MCP Inspector web UI, connected to the Tanzu MCP Gateway as the
# demo agent: a fresh agent token in the Authorization header. Rerun it to
# pick up a grant, which only reaches new tokens. Needs Node.
#
# The token is on Inspector's command line, so other users of this machine
# can see it in the process list. Use it on your own workstation.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/mcp.sh"
need npx

TOKEN=$("$(dirname "$0")/agent-token.sh")
ROUTE=$(cat "$STATE/gateway-route" 2>/dev/null || { cf target -o "$CF_ORG" -s "$CF_SPACE" >/dev/null; gateway_route; })
echo "token intents: $(jwt_claims "$TOKEN" | jq -r .scope | grep -o 'intent:[a-z.]*' | tr '\n' ' ')"

exec npx -y "@modelcontextprotocol/inspector@$INSPECTOR_VERSION" --web --transport http \
  --server-url "$ROUTE/$GATEWAY_SERVER_NAME/mcp" --header "Authorization: Bearer $TOKEN"
