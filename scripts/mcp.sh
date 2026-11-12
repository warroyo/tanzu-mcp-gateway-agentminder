# MCP client helpers for the tests. Sourced, not run.
#
# Two clients:
#   inspector  the official MCP Inspector CLI, through npx (needs Node)
#   curl       a minimal client in this file, for machines without Node
# MCP_CLIENT=auto (the default) picks inspector when npx is on PATH.
#
#   mcp_list URL TOKEN         prints the tool names as a JSON array
#   mcp_call URL TOKEN TOOL    sets CALL_RC (0 = the tool ran) and CALL_OUT
#                              (the tool's text, or the error)
#   mcp_status URL TOKEN TOOL  prints the HTTP status of a tools/call (curl only)

MCP_VERSION=2025-06-18
INSPECTOR_VERSION=${INSPECTOR_VERSION:-2.13.0}
MCP_CLIENT=${MCP_CLIENT:-auto}
if [ "$MCP_CLIENT" = auto ]; then
  if command -v npx >/dev/null; then MCP_CLIENT=inspector; else MCP_CLIENT=curl; fi
fi

# Same TLS settings as the curl calls.
if [ "${INSECURE:-0}" = 1 ]; then
  export NODE_TLS_REJECT_UNAUTHORIZED=0 NODE_NO_WARNINGS=1
elif [ -n "${CA_FILE:-}" ]; then
  export NODE_EXTRA_CA_CERTS=$CA_FILE
fi

# --- inspector ---

inspector() {
  local url=$1 token=$2; shift 2
  local auth=()
  [ -n "$token" ] && auth=(--header "Authorization: Bearer $token")
  npx -y "@modelcontextprotocol/inspector@$INSPECTOR_VERSION" --cli "$url" --transport http "${auth[@]}" "$@"
}

# --- curl ---

curl_init() {
  MCP_URL=$1
  MCP_H=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream'
         -H "MCP-Protocol-Version: $MCP_VERSION")
  [ -n "${2:-}" ] && MCP_H+=(-H "Authorization: Bearer $2")
  MCP_ID=0
  local headers sid
  headers=$(mktemp)
  MCP_INIT_CODE=$("${CURL[@]}" -o /dev/null -D "$headers" -w '%{http_code}' -X POST "$MCP_URL" "${MCP_H[@]}" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"$MCP_VERSION\",\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"0\"}}}")
  sid=$(grep -i '^mcp-session-id:' "$headers" | cut -d' ' -f2 | tr -d '\r' || true)
  rm -f "$headers"
  [ -n "$sid" ] && MCP_H+=(-H "Mcp-Session-Id: $sid")
  "${CURL[@]}" -o /dev/null -X POST "$MCP_URL" "${MCP_H[@]}" -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'
}

# Prints "<http code> <JSON-RPC response>". A response is plain JSON or one SSE "data:" line.
curl_rpc() {
  local method=$1 params=${2:-'{}'} out body
  MCP_ID=$((MCP_ID + 1))
  out=$("${CURL[@]}" -w '\n%{http_code}' -X POST "$MCP_URL" "${MCP_H[@]}" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":$MCP_ID,\"method\":\"$method\",\"params\":$params}")
  body=$(sed '$d' <<<"$out" | sed -n 's/^data: //p;/^{/p' | tail -n1)
  echo "$(tail -n1 <<<"$out") ${body:-null}"
}

# --- the client-neutral calls the test uses ---

mcp_list() {
  if [ "$MCP_CLIENT" = inspector ]; then
    inspector "$1" "$2" --method tools/list 2>/dev/null | jq -c '[.tools[]?.name]'
  else
    local code body
    curl_init "$1" "$2"
    read -r code body < <(curl_rpc tools/list)
    jq -c '[.result.tools[]?.name]' <<<"$body"
  fi
}

mcp_call() {
  local url=$1 token=$2 tool=$3
  if [ "$MCP_CLIENT" = inspector ]; then
    local out
    # The result goes to stdout, an error to stderr. Exit 0 means the tool ran.
    out=$(inspector "$url" "$token" --method tools/call --tool-name "$tool" 2>&1) && CALL_RC=0 || CALL_RC=$?
    CALL_OUT=$(grep -v 'Warning' <<<"$out" | jq -c 'if .content then (.content[0].text) else . end' 2>/dev/null || echo "$out")
    [ "$CALL_RC" = 0 ] && [ "$(jq -r '.isError // false' <<<"$out" 2>/dev/null)" = true ] && CALL_RC=1
  else
    local code body
    curl_init "$url" "$token"
    read -r code body < <(curl_rpc tools/call "{\"name\":\"$tool\",\"arguments\":{}}")
    if [ "$code" = 200 ] && jq -e '.result and (.result.isError | not)' <<<"$body" >/dev/null; then CALL_RC=0; else CALL_RC=1; fi
    CALL_OUT="HTTP $code $(jq -c '.result.content[0].text // .error // .' <<<"$body" 2>/dev/null || echo "$body")"
  fi
  return 0
}

# The HTTP status of a tools/call, which the Inspector CLI doesn't show.
mcp_status() {
  local code body
  curl_init "$1" "$2"
  read -r code body < <(curl_rpc tools/call "{\"name\":\"$3\",\"arguments\":{}}")
  echo "$code"
}
