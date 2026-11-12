#!/usr/bin/env bash
# Runs the agent's side end to end and checks each layer does its job:
#
#   1. the agent gets a token from AgentMinder for the AgentMinder gateway URL
#   2. tools/list through the Tanzu gateway shows only the granted tool
#   3. whoami through the Tanzu gateway works, and the echo server got the
#      agent's own token, unchanged
#   4. denyme through the Tanzu gateway is refused
#   5. denyme straight at AgentMinder is refused with 403
#   6. no token through the Tanzu gateway is refused
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/mcp.sh"

AM_GATEWAY_URL=$(jq -r .gateway_url "$STATE/agentminder.json")
ROUTE=$(cat "$STATE/gateway-route" 2>/dev/null || { cf target -o "$CF_ORG" -s "$CF_SPACE" >/dev/null; gateway_route; })
TANZU_URL=$ROUTE/$GATEWAY_SERVER_NAME/mcp
FAIL=0
check() { if [ "$1" = ok ]; then echo "PASS  $2"; else echo "FAIL  $2"; FAIL=1; fi; }

echo "Tanzu gateway:      $TANZU_URL"
echo "AgentMinder gateway: $AM_GATEWAY_URL"
echo

# 1. The token. scope=urn:iam:myscopes asks for every intent the policy
# grants; resource= names the AgentMinder gateway URL as the audience.
ID=$(jq -r .client_id "$STATE/agent-client.json")
SECRET=$(jq -r .client_secret "$STATE/agent-client.json")
TOKEN=$("${CURL[@]}" "$AM_TOKEN_URL" -u "$ID:$SECRET" -d grant_type=client_credentials \
  --data-urlencode scope=urn:iam:myscopes --data-urlencode "resource=$AM_GATEWAY_URL" | jq -r '.access_token // empty')
[ -n "$TOKEN" ] || { echo "FAIL  agent token request"; exit 1; }
CLAIMS=$(jwt_claims "$TOKEN")
echo "token sha256 $(sha12 "$TOKEN"): $(jq -c '{aud, scope}' <<<"$CLAIMS")"
grep -q 'urn:iam:agent:intent:whoami' <<<"$CLAIMS" && r=ok || r=no
check $r "1. token carries the whoami intent"

# AgentMinder's gateway route takes a little while to appear after setup.
for _ in $(seq 1 12); do
  mcp_init "$AM_GATEWAY_URL" "$TOKEN"
  [ "$MCP_INIT_CODE" = 200 ] && break
  echo "waiting for the AgentMinder gateway route (init $MCP_INIT_CODE)"; sleep 10
done

# 2-4 through the Tanzu gateway.
mcp_init "$TANZU_URL" "$TOKEN"
read -r code body < <(mcp_rpc tools/list)
TOOLS=$(jq -c '[.result.tools[]?.name]' <<<"$body")
echo "tools/list: $code $TOOLS"
[ "$TOOLS" = '["whoami"]' ] && r=ok || r=no
check $r "2. tools/list shows only the granted tool"

read -r code body < <(mcp_rpc tools/call '{"name":"whoami","arguments":{}}')
SEEN=$(jq -r '.result.content[0].text // empty' <<<"$body" | jq -r '.auth.sha256 // empty' 2>/dev/null || true)
echo "whoami: $code, echo saw token sha256 ${SEEN:-none}"
[ "$code" = 200 ] && [ "$SEEN" = "$(sha12 "$TOKEN")" ] && r=ok || r=no
check $r "3. whoami works and the server got the agent's token unchanged"

read -r code body < <(mcp_rpc tools/call '{"name":"denyme","arguments":{}}')
echo "denyme: $code $(jq -c '.error // {isError: .result.isError, text: .result.content[0].text}' <<<"$body" | cut -c1-160)"
jq -e '.error or .result.isError == true' <<<"$body" >/dev/null && r=ok || r=no
check $r "4. denyme through the Tanzu gateway is refused"

# 5 straight at AgentMinder.
mcp_init "$AM_GATEWAY_URL" "$TOKEN"
read -r code body < <(mcp_rpc tools/call '{"name":"denyme","arguments":{}}')
echo "denyme at AgentMinder: $code"
[ "$code" = 403 ] && r=ok || r=no
check $r "5. denyme straight at AgentMinder is 403"

# 6 no token. The Tanzu gateway answers initialize itself, so the refusal
# shows on the first call it passes on to AgentMinder.
mcp_init "$TANZU_URL"
read -r code body < <(mcp_rpc tools/call '{"name":"whoami","arguments":{}}')
echo "no token: init $MCP_INIT_CODE, whoami $code $(cut -c1-100 <<<"$body")"
case $code in 2*) r=no ;; *) r=ok ;; esac
check $r "6. whoami with no token is refused"

exit $FAIL
