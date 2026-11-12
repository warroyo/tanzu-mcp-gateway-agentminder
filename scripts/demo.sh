#!/usr/bin/env bash
# Changes what the demo agent may do, by editing its AgentMinder policy:
#
#   scripts/demo.sh revoke write   # take echo.write away: reset disappears
#   scripts/demo.sh grant write    # give it back
#   scripts/demo.sh show           # what the policy grants now
#
# Both reach tokens the agent already holds, in under a minute, as long as
# the token was minted with the intent. A token minted while it was revoked
# needs replacing. The same change can be made in
# the AgentMinder admin console, on the policy's grant rule.
. "$(dirname "$0")/lib.sh"
require_setup

ACTION=${1:-show}
INTENT=urn:iam:agent:intent:echo.${2:-write}
POLICY=$(jq -r .policy "$STATE/agentminder.json")

ADMIN=$("${CURL[@]}" "$AM_TOKEN_URL" -u "$AM_ADMIN_CLIENT_ID:$AM_ADMIN_CLIENT_SECRET" \
  -d grant_type=client_credentials --data-urlencode scope=urn:iam:myscopes | jq -er .access_token)
api() { "${CURL[@]}" -H "Authorization: Bearer $ADMIN" -H 'Content-Type: application/json' "$@"; }

current=$(api "$AM_TENANT_URL/admin/v1/AuthZPolicies/$POLICY")
case $ACTION in
  show)   jq -c '.rules[0].result.privileges' <<<"$current"; exit ;;
  grant)  change='(. + [$i] | unique)' ;;
  revoke) change='map(select(. != $i))' ;;
  *)      echo "usage: $0 grant|revoke read|write, or $0 show" >&2; exit 1 ;;
esac

# A PUT takes the policy's own fields only. Server fields such as policyId
# and createdDate are refused.
jq --arg i "$INTENT" "{policyName, displayName, description, policySubType, status, matchAnyApp, apps,
  rules: [.rules[] | {conditions, result: (.result | .privileges |= $change)}]}" <<<"$current" \
  | api -X PUT -d @- "$AM_TENANT_URL/admin/v1/AuthZPolicies/$POLICY" | jq -c '.rules[0].result.privileges'
