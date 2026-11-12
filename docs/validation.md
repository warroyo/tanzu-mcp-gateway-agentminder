# Validation

Results from the reference environment, November 2026.

## Environment

- Tanzu Platform for Cloud Foundry 11.0.1, GenAI tile 11.0.0, Ops Manager 11.0.0.
- App hosts of two kinds: BOSH Diego cells, and the hosts of a Kubernetes resource segment (tile 11.0.1).
- AgentMinder (SSP) 4.1.1 build 1673, on its own Kubernetes cluster, with a certificate from a private CA. The CA was added to the Director's trusted certificates.

## Clean run of the scripts

`01` to `04` on fresh names, with both test clients:

```
token sha256 3691238de55e, scope: urn:iam:t.authenticate urn:iam:agent:intent:echo.write urn:iam:m.meclient urn:iam:agent:intent:echo.read
PASS  1. token carries echo.read and echo.write
tools/list: ["whoami","reset"], whoami rc 0, echo saw token sha256 3691238de55e
PASS  2. both tools listed; whoami works and the server got the agent's token unchanged
revoking echo.write: ["urn:iam:agent:intent:echo.read"]
same token: tools/list ["whoami"], reset rc 5 {"error":{"code":"tool_not_found","message":"Tool 'reset' not found on server."}}, whoami rc 0
PASS  3. after revoking echo.write, the same token loses reset and keeps whoami
reset at AgentMinder: HTTP 403
PASS  4. reset straight at AgentMinder is 403
no token: rc 1, {"error":{"code":"error","message":"Error POSTing to endpoint: {\"error\":\"AI Gateway: missing MCP-Protocol-Version header\"}...
PASS  5. a call with no token is refused
granting echo.write: ["urn:iam:agent:intent:echo.read","urn:iam:agent:intent:echo.write"]
same token: tools/list ["whoami","reset"], reset rc 0
PASS  6. after granting echo.write back, the same token can call reset again
```

That was MCP Inspector 2.13.0 on Node 24.19. With `MCP_CLIENT=curl` all six checks pass too; there, the refused `reset` in check 3 shows as `HTTP 200 "Unknown tool: 'reset'"`. A run takes about 90 seconds, most of it waiting for the policy changes.

An earlier version of the scripts ran `01` to `04` and then `99-cleanup.sh`. The cleanup removed the gateway, the echo app and all four AgentMinder changes, and reading the objects back afterwards returned 404.

## Policy and binding changes

Measured by changing the policy or the tool bindings through the admin API:

- A revoked intent stopped working for an existing token within 45 seconds.
- Granting the intent back made it work again within 40 seconds on a token that still carried it (2026-11-12).
- A granted intent appeared in newly minted tokens after about 20 seconds. Tokens minted while it was revoked stayed without it.
- Removing a tool's binding stopped the tool for an existing token within 45 seconds (HTTP 401). Adding it back made it work again within 30 seconds, on the same token.

## Both kinds of host

A separate gateway instance was scaled to four instances: two on Diego cells and two on Kubernetes segment hosts. Sixteen full sessions (initialize, `tools/list`, `whoami`) through the chain all succeeded. The router logs showed the calls spread evenly over the four instances, all answered 200 or 202, with no certificate errors.
