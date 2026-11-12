# AgentMinder objects and API calls

`scripts/02-agentminder-setup.py` makes four things through the tenant admin API. You can make the same objects in the AgentMinder admin console. This page lists the calls so you can do it from your own automation (Terraform's `restapi` provider works with the same payloads).

All calls go to `<tenant URL>`, for example `https://agentminder.example.com/default`, with a bearer token from the tenant admin client:

```bash
curl -s "$AM_TENANT_URL/oauth2/v1/token" -u "$ADMIN_ID:$ADMIN_SECRET" \
  -d grant_type=client_credentials --data-urlencode scope=urn:iam:myscopes
```

## 1. The resource server

`POST /admin/v1/Apps` with `isAiResourceServerApp: true`. The fields that matter:

| Field | Value | Why |
|---|---|---|
| `mcpServerEndpoint` | `https://echo-mcp.apps.example.com/mcp` | Where AgentMinder forwards allowed calls |
| `secondaryAudiences` | the same URL | |
| `primaryAudience` | the AgentMinder gateway URL (see below) | Agents ask for tokens with `resource=` this URL |
| `resourceServerScopes` | each tool name, and each intent as `urn:iam:agent:intent:<intent>` | The intents this server knows |
| `agentToolBindings` | per tool: `{toolName, intentScope}` | Which intent unlocks each tool; tools can share one |
| `protectedByDefault` | `true` | A tool with no binding can't be called |
| `enforcePolicies` | `true` | Turns per-tool authorization on |
| `mcpRequireAccessToken`, `mcpDiscoverRequireAccessToken` | `true` | No anonymous calls or tool lists |
| `mcpIgnoreSslValidation` | `true` only for a self-signed MCP server | AgentMinder's own check of the server's certificate |

The response holds `appId` and `clientId`.

### The gateway URL

AgentMinder's gateway URL for a resource server is its `appId`, base64-encoded without padding:

```bash
echo "$AM_TENANT_URL/aigateway/v1/mcp/$(printf %s "$APP_ID" | base64 | tr -d '=')"
```

The URL exists only after the create, so the script creates the app with the MCP server's URL as `primaryAudience`, then sends the whole app again with `PUT /admin/v1/Apps/<appId>` and the gateway URL as `primaryAudience`. A PUT replaces the app, so send every field, plus `appId` and `clientId`.

The gateway route takes 30 to 60 seconds to start answering after the create. Before that it returns 404 "no matching route".

## 2. The agent client

`POST /admin/v1/Apps` with `clientType: CONFIDENTIAL` and `allowedGrantTypes` including `client_credentials`. The response holds `clientId` and `secret`. The secret is shown only once.

`metadata: [{name: urn:iam:app:oauthAccessTokenExpirySecs, value: "900"}]` sets the token lifetime in seconds.

## 3. The policy

`POST /admin/v1/AuthZPolicies`:

```json
{
  "policyName": "demo-agent",
  "policySubType": "role",
  "status": "active",
  "matchAnyApp": false,
  "apps": [{"id": "<resource server appId>", "name": "demo-echo-mcp"}],
  "rules": [{
    "conditions": {"principal": {"clientApp": {"operator": "in", "value": ["<agent client appId>"]}}},
    "result": {"effect": "grant", "msg": "demo-agent", "privileges": ["urn:iam:agent:intent:echo.read", "urn:iam:agent:intent:echo.write"]}
  }]
}
```

`privileges` lists the intents granted. A tool whose intent isn't listed is hidden from `tools/list` and refused on call.

To change a grant, send the policy back with `PUT /admin/v1/AuthZPolicies/<policyId>`. Send only the fields above: the server refuses its own fields, such as `policyId` and `createdDate`, with `Unknown property`. `scripts/demo.sh` does this.

## 4. AuthClientPolicy

AgentMinder issues intent scopes only to clients that are principals of its built-in `AuthClientPolicy`. Find the policy, then add the client through the delegator:

```
GET  /admin/v1/AuthZPolicies?filter=policyName eq "AuthClientPolicy"
POST /admin/v1/AdminRolesDelegator
     {"id": "<AuthClientPolicy policyId>", "principal": {"clientApp": {"operator": "in", "value": ["<agent client appId>"]}}}
```

The filter returns a JSON array. Pick the entry whose `policyName` is `AuthClientPolicy`.

## Deleting

`scripts/99-cleanup.sh` reverses the four steps:

```
DELETE /admin/v1/AdminRolesDelegator           (same body as the POST)
DELETE /admin/v1/AuthZPolicies/<policyId>
DELETE /admin/v1/Apps/<agent client appId>?force=true
DELETE /admin/v1/Apps/<resource server appId>?force=true
```
