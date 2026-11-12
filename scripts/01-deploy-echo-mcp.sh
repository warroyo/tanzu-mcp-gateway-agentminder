#!/usr/bin/env bash
# Pushes the echo MCP server to CF_ORG/CF_SPACE, at https://<ECHO_APP>.<APPS_DOMAIN>/mcp.
# Creates the space if it doesn't exist. The gateway instance goes in the
# same space (03-create-gateway.sh).
. "$(dirname "$0")/lib.sh"
need cf

cf target -o "$CF_ORG" >/dev/null
if ! cf space "$CF_SPACE" >/dev/null 2>&1; then
  cf create-space "$CF_SPACE" -o "$CF_ORG" >/dev/null
  echo "created space $CF_ORG/$CF_SPACE"
fi
cf target -o "$CF_ORG" -s "$CF_SPACE" >/dev/null
cf push "$ECHO_APP" -f "$ROOT/echo-mcp/manifest.yml" -p "$ROOT/echo-mcp" --no-start >/dev/null
cf map-route "$ECHO_APP" "$APPS_DOMAIN" --hostname "$ECHO_APP" >/dev/null
cf set-env "$ECHO_APP" AM_ISSUER "$AM_TENANT_URL/" >/dev/null
cf start "$ECHO_APP" >/dev/null

echo "echo-mcp: $ECHO_URL"
"${CURL[@]}" -o /dev/null -w "health: %{http_code}\n" "https://$ECHO_APP.$APPS_DOMAIN/health"
