# MCP over streamable HTTP with curl, for the tests. Sourced, not run.
#
#   mcp_init URL [TOKEN]   initialize and notifications/initialized; sets MCP_URL, MCP_H
#   mcp_rpc METHOD [PARAMS_JSON]
#                          prints "<http code> <JSON-RPC response>" on one line
#
# MCP-Protocol-Version is required by the AgentMinder AI Gateway, and the
# session ID from initialize must go on every later call.

MCP_VERSION=2025-06-18

mcp_init() {
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

mcp_rpc() {
  local method=$1 params=${2:-'{}'} out code body
  MCP_ID=$((MCP_ID + 1))
  out=$("${CURL[@]}" -w '\n%{http_code}' -X POST "$MCP_URL" "${MCP_H[@]}" \
    -d "{\"jsonrpc\":\"2.0\",\"id\":$MCP_ID,\"method\":\"$method\",\"params\":$params}")
  code=$(tail -n1 <<<"$out")
  # A response is plain JSON or one SSE "data:" line.
  body=$(sed '$d' <<<"$out" | sed -n 's/^data: //p;/^{/p' | tail -n1)
  echo "$code ${body:-null}"
}
