# Validation

Results from the reference environment, November 2026.

## Environment

- Tanzu Platform for Cloud Foundry 11.0.1, GenAI tile 11.0.0, Ops Manager 11.0.0.
- App hosts of two kinds: BOSH Diego cells, and the hosts of a Kubernetes resource segment (tile 11.0.1).
- AgentMinder (SSP) 4.1.1 build 1673, on its own Kubernetes cluster, with a certificate from a private CA. The CA was added to the Director's trusted certificates.

## Clean run of the scripts

`01` to `04` on fresh names, then `99-cleanup.sh`:

```
token sha256 dd903b296f0a: {"aud":["https://agentminder.example.com/default/aigateway/v1/mcp/ZTkw...","https://agentminder.example.com/default/"],"scope":"urn:iam:t.authenticate urn:iam:agent:intent:whoami urn:iam:m.meclient"}
PASS  1. token carries the whoami intent
tools/list: 200 ["whoami"]
PASS  2. tools/list shows only the granted tool
whoami: 200, echo saw token sha256 dd903b296f0a
PASS  3. whoami works and the server got the agent's token unchanged
denyme: 200 {"isError":true,"text":"Unknown tool: 'denyme'"}
PASS  4. denyme through the Tanzu gateway is refused
denyme at AgentMinder: 403
PASS  5. denyme straight at AgentMinder is 403
no token: init 200, whoami 400 {"error":"AI Gateway: missing MCP-Protocol-Version header"}
PASS  6. whoami with no token is refused
```

That run used the curl client. A later run of `04-test.sh` against the same kind of setup passed all six checks with both clients, MCP Inspector 2.13.0 (Node 24.19) and curl.

The cleanup removed the gateway, the echo app and all four AgentMinder changes. Reading the objects back afterwards returned 404.

## Both kinds of host

A separate gateway instance was scaled to four instances: two on Diego cells and two on Kubernetes segment hosts. Sixteen full sessions (initialize, `tools/list`, `whoami`) through the chain all succeeded. The router logs showed the calls spread evenly over the four instances, all answered 200 or 202, with no certificate errors.
