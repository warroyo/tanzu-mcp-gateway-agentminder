#!/usr/bin/env bash
# Runs the agent's side end to end and checks each layer does its job.
# The agent starts with both intents, echo.read (whoami) and echo.write (reset).
#
#   1. the agent's token carries both intents
#   2. through the Tanzu gateway: both tools are listed, and whoami works
#      with the agent's own token arriving unchanged at the MCP server
#   3. revoke echo.write: with the same token, reset disappears from the
#      list and is refused, and whoami still works
#   4. reset straight at AgentMinder is refused with 403
#   5. a call with no token is refused
#   6. grant echo.write back: the same token can call reset again
#
# Uses the MCP Inspector CLI when npx is on PATH, else a curl client.
# MCP_CLIENT=inspector or MCP_CLIENT=curl picks one. Check 4 always uses
# curl, because it needs the HTTP status.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/mcp.sh"
require_setup gateway

HERE=$(dirname "$0")
AM_GATEWAY_URL=$(jq -r .gateway_url "$STATE/agentminder.json")
ROUTE=$(cat "$STATE/gateway-route")
TANZU_URL=$ROUTE/$GATEWAY_SERVER_NAME/mcp
FAIL=0
check() { if [ "$1" = ok ]; then echo "PASS  $2"; else echo "FAIL  $2"; FAIL=1; fi; }
# Polls until the tool list through the Tanzu gateway equals $2. Policy
# changes take up to a minute to arrive.
wait_list() {
  local tools
  for _ in $(seq 1 12); do
    tools=$(mcp_list "$TANZU_URL" "$1")
    [ "$tools" = "$2" ] && break
    sleep 10
  done
  echo "$tools"
}

echo "MCP client:          $MCP_CLIENT"
echo "Tanzu gateway:       $TANZU_URL"
echo "AgentMinder gateway: $AM_GATEWAY_URL"
echo

# Start from the granted state, in case a previous run stopped half way.
"$HERE/demo.sh" grant write >/dev/null

# 1
TOKEN=$("$HERE/agent-token.sh") || { echo "FAIL  agent token request"; exit 1; }
SCOPES=$(jwt_claims "$TOKEN" | jq -r .scope)
echo "token sha256 $(sha12 "$TOKEN"), scope: $SCOPES"
grep -q 'intent:echo.read' <<<"$SCOPES" && grep -q 'intent:echo.write' <<<"$SCOPES" && r=ok || r=no
check $r "1. token carries echo.read and echo.write"

# 2
TOOLS=$(wait_list "$TOKEN" '["whoami","reset"]')
mcp_call "$TANZU_URL" "$TOKEN" whoami
SEEN=$(sed 's/^HTTP [0-9]* //' <<<"$CALL_OUT" | jq -r 'if type == "string" then fromjson else . end | .auth.sha256 // empty' 2>/dev/null || true)
echo "tools/list: $TOOLS, whoami rc $CALL_RC, echo saw token sha256 ${SEEN:-none}"
[ "$TOOLS" = '["whoami","reset"]' ] && [ "$CALL_RC" = 0 ] && [ "$SEEN" = "$(sha12 "$TOKEN")" ] && r=ok || r=no
check $r "2. both tools listed; whoami works and the server got the agent's token unchanged"

# 3
echo "revoking echo.write: $("$HERE/demo.sh" revoke write)"
TOOLS=$(wait_list "$TOKEN" '["whoami"]')
mcp_call "$TANZU_URL" "$TOKEN" reset; RESET_RC=$CALL_RC; RESET_OUT=$CALL_OUT
mcp_call "$TANZU_URL" "$TOKEN" whoami
echo "same token: tools/list $TOOLS, reset rc $RESET_RC $(cut -c1-100 <<<"$RESET_OUT"), whoami rc $CALL_RC"
[ "$TOOLS" = '["whoami"]' ] && [ "$RESET_RC" != 0 ] && [ "$CALL_RC" = 0 ] && r=ok || r=no
check $r "3. after revoking echo.write, the same token loses reset and keeps whoami"

# 4
CODE=$(mcp_status "$AM_GATEWAY_URL" "$TOKEN" reset)
echo "reset at AgentMinder: HTTP $CODE"
[ "$CODE" = 403 ] && r=ok || r=no
check $r "4. reset straight at AgentMinder is 403"

# 5. The Tanzu gateway answers initialize itself, so the refusal shows on
# the first call it passes on to AgentMinder.
mcp_call "$TANZU_URL" "" whoami
echo "no token: rc $CALL_RC, $(cut -c1-120 <<<"$CALL_OUT")"
[ "$CALL_RC" != 0 ] && r=ok || r=no
check $r "5. a call with no token is refused"

# 6
echo "granting echo.write: $("$HERE/demo.sh" grant write)"
TOOLS=$(wait_list "$TOKEN" '["whoami","reset"]')
mcp_call "$TANZU_URL" "$TOKEN" reset
echo "same token: tools/list $TOOLS, reset rc $CALL_RC"
[ "$TOOLS" = '["whoami","reset"]' ] && [ "$CALL_RC" = 0 ] && r=ok || r=no
check $r "6. after granting echo.write back, the same token can call reset again"

exit $FAIL
