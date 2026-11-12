#!/usr/bin/env bash
# Opens the MCP Inspector web UI, connected to the Tanzu MCP Gateway as the
# demo agent: a fresh agent token in the Authorization header. Rerun it for
# a new token: when it expires (15 minutes) or to pick up an intent the old
# one was minted without. Needs Node.
#
# It listens on all interfaces (DEMO_UI_HOST=0.0.0.0), so the UI can run on
# a remote machine and be opened from your browser. Inspector refuses that
# unless DANGEROUSLY_BIND_ALL_INTERFACES=true, and it only answers browsers
# whose origin is in ALLOWED_ORIGINS: this script allows this machine's
# hostname and IP addresses, plus DEMO_UI_PUBLIC_HOST if you set it (a DNS
# name or address you reach the machine by). Set DEMO_UI_HOST=127.0.0.1 to
# keep it local and reach it through an SSH tunnel instead.
#
# On all interfaces it serves HTTPS. Browsers only allow the UI's crypto
# calls on HTTPS or localhost; over plain http from another machine,
# connecting fails with "crypto.randomUUID is not a function". By default it
# makes a self-signed certificate for the names above (in .state/, once), so
# the browser warns on first visit. To avoid the warning, give it a trusted
# certificate and key, such as one from `tailscale cert`:
#
#   DEMO_UI_TLS_CERT=host.crt DEMO_UI_TLS_KEY=host.key scripts/demo-ui.sh
#
# Anyone who can reach the port can use the UI as the demo agent: Inspector's
# auth token is handed out by the page itself. Use it on a trusted network
# only. See docs/demo.md.
#
# The agent token is on Inspector's command line, so other users of this
# machine can see it in the process list.
. "$(dirname "$0")/lib.sh"
. "$(dirname "$0")/mcp.sh"
need npx
require_setup gateway

# A self-signed certificate for these names, made once.
self_signed() {
  local dir=$STATE/inspector-tls san="" n
  for n in "$@"; do
    if [[ $n =~ ^[0-9.]+$ ]]; then san+="IP:$n,"; else san+="DNS:$n,"; fi
  done
  if [ ! -s "$dir/cert.pem" ]; then
    need openssl
    mkdir -p "$dir"
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=$(hostname)" \
      -addext "subjectAltName=${san%,}" -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
    chmod 600 "$dir/key.pem"
    echo "made a self-signed certificate in $dir (delete it to make a new one)"
  fi
  DEMO_UI_TLS_CERT=$dir/cert.pem DEMO_UI_TLS_KEY=$dir/key.pem
}

BIND=${DEMO_UI_HOST:-0.0.0.0}
PORT=${CLIENT_PORT:-6274}

TOKEN=$("$(dirname "$0")/agent-token.sh")
ROUTE=$(cat "$STATE/gateway-route")
echo "token intents: $(jwt_claims "$TOKEN" | jq -r .scope | grep -o 'intent:[a-z.]*' | tr '\n' ' ')"

export HOST=$BIND CLIENT_PORT=$PORT
if [ "$BIND" = 0.0.0.0 ]; then
  names=("localhost" "127.0.0.1" "$(hostname)")
  fqdn=$(hostname -f 2>/dev/null || true); [ -n "$fqdn" ] && names+=("$fqdn")
  # hostname -I is Linux only.
  for ip in $(hostname -I 2>/dev/null || true); do [[ $ip == *:* ]] || names+=("$ip"); done
  [ -n "${DEMO_UI_PUBLIC_HOST:-}" ] && names+=("$DEMO_UI_PUBLIC_HOST")
  mapfile -t names < <(printf '%s\n' "${names[@]}" | awk '!seen[$0]++')
  [ -n "${DEMO_UI_TLS_CERT:-}" ] && [ -n "${DEMO_UI_TLS_KEY:-}" ] || self_signed "${names[@]}"
  export INSPECTOR_TLS_CERT_PATH=$DEMO_UI_TLS_CERT INSPECTOR_TLS_KEY_PATH=$DEMO_UI_TLS_KEY
  ALLOWED_ORIGINS=$(printf "https://%s:$PORT," "${names[@]}"); ALLOWED_ORIGINS=${ALLOWED_ORIGINS%,}
  export DANGEROUSLY_BIND_ALL_INTERFACES=true ALLOWED_ORIGINS
  echo "listening on 0.0.0.0:$PORT; open it as https://<one of: ${names[*]}>:$PORT/?MCP_INSPECTOR_API_TOKEN=<the token printed below>"
fi

exec npx -y "@modelcontextprotocol/inspector@$INSPECTOR_VERSION" --web --transport http \
  --server-url "$ROUTE/$GATEWAY_SERVER_NAME/mcp" --header "Authorization: Bearer $TOKEN"
