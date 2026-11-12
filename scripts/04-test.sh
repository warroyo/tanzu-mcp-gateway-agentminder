#!/usr/bin/env bash
# Runs the agent's side end to end and checks each layer does its job:
#
#   1. the agent gets a token from AgentMinder for the AgentMinder gateway URL
#   2. tools/list through the Tanzu gateway shows only the granted tool
#   3. whoami through the Tanzu gateway works, and the echo server got the
#      agent's own token, unchanged
#   4. denyme through the Tanzu gateway is refused
#   5. denyme straight at AgentMinder is refused with 403
#   6. whoami through the Tanzu gateway with no token is refused
#
# Uses the MCP Inspector CLI when npx is on PATH, else a curl client.
# MCP_CLIENT=inspector or MCP_CLIENT=curl picks one. Check 5 always uses
# curl, because it needs the HTTP status.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/mcp.sh"

AM_GATEWAY_URL=$(jq -r .gateway_url "$STATE/agentminder.json")
ROUTE=$(cat "$STATE/gateway-route" 2>/dev/null || { cf target -o "$CF_ORG" -s "$CF_SPACE" >/dev/null; gateway_route; })
TANZU_URL=$ROUTE/$GATEWAY_SERVER_NAME/mcp
FAIL=0
check() { if [ "$1" = ok ]; then echo "PASS  $2"; else echo "FAIL  $2"; FAIL=1; fi; }

echo "MCP client:          $MCP_CLIENT"
echo "Tanzu gateway:       $TANZU_URL"
echo "AgentMinder gateway: $AM_GATEWAY_URL"
echo

# 1
TOKEN=$("$(dirname "$0")/agent-token.sh") || { echo "FAIL  agent token request"; exit 1; }
CLAIMS=$(jwt_claims "$TOKEN")
echo "token sha256 $(sha12 "$TOKEN"): $(jq -c '{aud, scope}' <<<"$CLAIMS")"
grep -q 'urn:iam:agent:intent:whoami' <<<"$CLAIMS" && r=ok || r=no
check $r "1. token carries the whoami intent"

# AgentMinder's gateway route takes a little while to appear after setup.
for _ in $(seq 1 12); do
  [ "$(mcp_status "$AM_GATEWAY_URL" "$TOKEN" whoami)" != 404 ] && break
  echo "waiting for the AgentMinder gateway route"; sleep 10
done

# 2
TOOLS=$(mcp_list "$TANZU_URL" "$TOKEN")
echo "tools/list: $TOOLS"
[ "$TOOLS" = '["whoami"]' ] && r=ok || r=no
check $r "2. tools/list shows only the granted tool"

# 3
mcp_call "$TANZU_URL" "$TOKEN" whoami
SEEN=$(sed 's/^HTTP [0-9]* //' <<<"$CALL_OUT" | jq -r 'if type == "string" then fromjson else . end | .auth.sha256 // empty' 2>/dev/null || true)
echo "whoami: rc $CALL_RC, echo saw token sha256 ${SEEN:-none}"
[ "$CALL_RC" = 0 ] && [ "$SEEN" = "$(sha12 "$TOKEN")" ] && r=ok || r=no
check $r "3. whoami works and the server got the agent's token unchanged"

# 4
mcp_call "$TANZU_URL" "$TOKEN" denyme
echo "denyme: rc $CALL_RC, $(cut -c1-160 <<<"$CALL_OUT")"
[ "$CALL_RC" != 0 ] && r=ok || r=no
check $r "4. denyme through the Tanzu gateway is refused"

# 5
CODE=$(mcp_status "$AM_GATEWAY_URL" "$TOKEN" denyme)
echo "denyme at AgentMinder: HTTP $CODE"
[ "$CODE" = 403 ] && r=ok || r=no
check $r "5. denyme straight at AgentMinder is 403"

# 6. The Tanzu gateway answers initialize itself, so the refusal shows on
# the first call it passes on to AgentMinder.
mcp_call "$TANZU_URL" "" whoami
echo "no token: rc $CALL_RC, $(cut -c1-160 <<<"$CALL_OUT")"
[ "$CALL_RC" != 0 ] && r=ok || r=no
check $r "6. whoami with no token is refused"

exit $FAIL
