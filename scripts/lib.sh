# Shared by the scripts. Sourced, not run.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STATE=$ROOT/.state
[ -f "$ROOT/config.env" ] || { echo "missing config.env: copy config.env.example and fill it in" >&2; exit 1; }
set -a; . "$ROOT/config.env"; set +a
mkdir -p "$STATE"; chmod 700 "$STATE"

need() { command -v "$1" >/dev/null || { echo "needs $1 on PATH" >&2; exit 1; }; }
need curl
need jq

CURL=(curl -sS)
if [ "${INSECURE:-0}" = 1 ]; then CURL+=(-k); elif [ -n "${CA_FILE:-}" ]; then CURL+=(--cacert "$CA_FILE"); fi

ECHO_URL=https://$ECHO_APP.$APPS_DOMAIN/mcp
AM_TOKEN_URL=$AM_TENANT_URL/oauth2/v1/token

# The gateway's public route is the service instance's dashboard URL.
gateway_route() {
  need cf
  local guid
  guid=$(cf curl "/v3/service_instances?names=$GATEWAY_NAME" | jq -r '.resources[0].guid // empty')
  [ -n "$guid" ] || { echo "no service instance $GATEWAY_NAME in the targeted space" >&2; return 1; }
  cf curl "/v3/service_instances/$guid" | jq -r '.dashboard_url'
}

# Prints a JWT's claims. Never prints the token.
jwt_claims() {
  local p
  p=$(cut -d. -f2 <<<"$1" | tr '_-' '/+')
  while [ $(( ${#p} % 4 )) -ne 0 ]; do p="$p="; done
  base64 -d <<<"$p" 2>/dev/null
}

sha12() { printf %s "$1" | sha256sum | cut -c1-12; }
