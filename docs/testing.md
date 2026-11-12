# Testing with MCP Inspector

The tests use the official [MCP Inspector](https://github.com/modelcontextprotocol/inspector) CLI when Node is installed, and fall back to a small curl client when it isn't. Inspector is also the easiest way to poke at the chain by hand.

## Install

Inspector runs through `npx`, so it only needs Node and npm. Tested with Node 24.19 and Inspector 2.13.0.

- macOS: `brew install node`
- Linux and macOS with [nvm](https://github.com/nvm-sh/nvm): `nvm install 24`
- Others: the installers at [nodejs.org](https://nodejs.org/)

Check it:

```bash
npx -y @modelcontextprotocol/inspector@2.13.0 --version
```

`npx` downloads Inspector on first use. To install it once instead:

```bash
npm install -g @modelcontextprotocol/inspector@2.13.0   # gives the mcp-inspector command
```

### Certificates

Node doesn't use the system trust store by default. If AgentMinder or the apps domain use a private CA, point Node at it:

```bash
export NODE_EXTRA_CA_CERTS=/path/to/ca.pem
```

The scripts set this from `CA_FILE` in `config.env`. With `INSECURE=1` they set `NODE_TLS_REJECT_UNAUTHORIZED=0` instead. Use that in a lab only.

## Try it by hand

After steps 1 to 4 of the quick start:

```bash
TOKEN=$(scripts/agent-token.sh)
URL=$(cat .state/gateway-route)/echo/mcp
I() { npx -y @modelcontextprotocol/inspector@2.13.0 --cli "$URL" --transport http --header "Authorization: Bearer $TOKEN" "$@"; }

I --method tools/list                          # only whoami
I --method tools/call --tool-name whoami       # the headers and token claims echo-mcp got
I --method tools/call --tool-name denyme       # exit 5, tool_not_found
```

`scripts/agent-token.sh` prints a fresh token. Tokens last 5 minutes.

For the web UI, run `npx @modelcontextprotocol/inspector@2.13.0` and connect with transport Streamable HTTP, the gateway URL, and an `Authorization: Bearer <token>` header.

## What Inspector shows and doesn't

- **Denied tools.** Inspector lists the tools before it calls one, so it refuses `denyme` itself with `tool_not_found` (exit 5). That's still AgentMinder's decision: AgentMinder left the tool out of the list.
- **No token.** Inspector reports the error and its HTTP status, for example `"status":400` with `AI Gateway: missing MCP-Protocol-Version header` (exit 1).
- **The 403 from AgentMinder.** Inspector never sends the call, so it never sees the 403. Check 5 in `04-test.sh` always uses curl for that reason.

## The curl fallback

Without Node, or with `MCP_CLIENT=curl`, `04-test.sh` uses `scripts/mcp.sh`. It's a minimal streamable HTTP client: `initialize`, the session ID, the `MCP-Protocol-Version` header and one JSON-RPC call per request. It needs only `curl` and `jq`, and it shows the raw HTTP status of every call.

```bash
MCP_CLIENT=curl scripts/04-test.sh
```

Both clients pass all six checks against the reference environment.
