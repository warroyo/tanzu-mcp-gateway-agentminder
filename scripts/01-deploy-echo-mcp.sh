#!/usr/bin/env bash
# Pushes the echo MCP server to CF_ORG/CF_SPACE, at https://<ECHO_APP>.<APPS_DOMAIN>/mcp.
. "$(dirname "$0")/lib.sh"

cf target -o "$CF_ORG" -s "$CF_SPACE" >/dev/null
cf push "$ECHO_APP" -f "$ROOT/echo-mcp/manifest.yml" -p "$ROOT/echo-mcp" --no-start >/dev/null
cf map-route "$ECHO_APP" "$APPS_DOMAIN" --hostname "$ECHO_APP" >/dev/null
cf set-env "$ECHO_APP" AM_ISSUER "$AM_TENANT_URL/" >/dev/null
cf start "$ECHO_APP" >/dev/null

echo "echo-mcp: $ECHO_URL"
"${CURL[@]}" -o /dev/null -w "health: %{http_code}\n" "https://$ECHO_APP.$APPS_DOMAIN/health"
