#!/usr/bin/env bash
# Prints an AgentMinder access token for the demo agent, for use in $(...):
#
#   TOKEN=$(scripts/agent-token.sh)
#
# scope=urn:iam:myscopes asks for every intent the agent's policy grants.
# resource= makes the AgentMinder gateway URL the token's audience.
. "$(dirname "$0")/lib.sh"
require_setup

AM_GATEWAY_URL=$(jq -r .gateway_url "$STATE/agentminder.json")
ID=$(jq -r .client_id "$STATE/agent-client.json")
SECRET=$(jq -r .client_secret "$STATE/agent-client.json")

"${CURL[@]}" "$AM_TOKEN_URL" -u "$ID:$SECRET" -d grant_type=client_credentials \
  --data-urlencode scope=urn:iam:myscopes --data-urlencode "resource=$AM_GATEWAY_URL" \
  | jq -er '.access_token'
