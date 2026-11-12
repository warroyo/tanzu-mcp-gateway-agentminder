# Demo: revoke a tool live

Shows an agent losing a write tool the moment a security admin revokes its write permission in AgentMinder, while it keeps reading, with no change to the agent or the Tanzu MCP Gateway.

## Before you start

- Steps 1 to 4 of the quick start are done, and `scripts/04-test.sh` passes.
- Node is installed (see [testing.md](testing.md#install)).
- The agent holds both intents: `scripts/demo.sh show` prints `echo.read` and `echo.write`. If not, run `scripts/demo.sh grant write`.
- Optional: the AgentMinder admin console is open on the policy named `<AM_PREFIX>-agent`, to make the change there instead of with `scripts/demo.sh`.

## Running the UI on a remote machine

`scripts/demo-ui.sh` listens on all interfaces (`0.0.0.0`, ports 6274 for the UI and 6275 for Inspector's sandbox), so it can run on a jump host or lab VM and be opened from your laptop's browser. It prints the addresses it accepts: this machine's hostname and IP addresses. If you reach the machine by another name, set it first:

```bash
DEMO_UI_PUBLIC_HOST=demo-vm.example.com scripts/demo-ui.sh
```

Then open `https://<host>:6274/?MCP_INSPECTOR_API_TOKEN=<token>` with the token Inspector prints.

It serves HTTPS because browsers only allow the UI's crypto calls on HTTPS or `localhost`. Over plain http from another machine the page loads, but connecting fails with `crypto.randomUUID is not a function`. By default the script makes a self-signed certificate for the names it prints, once, in `.state/inspector-tls/`, so the browser warns on the first visit. To avoid that, pass a certificate the browser trusts, for example one from `tailscale cert` for the machine's tailnet name:

```bash
DEMO_UI_TLS_CERT=host.crt DEMO_UI_TLS_KEY=host.key DEMO_UI_PUBLIC_HOST=host.tailnet.ts.net scripts/demo-ui.sh
```

The sandbox on port 6275 stays on http. It's only for MCP Apps, which this demo doesn't use.

**Only on a trusted network.** On a non-loopback address, Inspector warns that its auth token is not access control: the page hands it to anyone who can load it, and they can then act as you. Here that means calling the MCP server as the demo agent. Where the network isn't trusted, keep the UI local and tunnel to it:

```bash
DEMO_UI_HOST=127.0.0.1 scripts/demo-ui.sh                  # on the remote machine
ssh -L 6274:localhost:6274 -L 6275:localhost:6275 <remote>  # on your laptop
```

Then open the `http://localhost:6274/...` URL Inspector prints.

## Steps

1. **Connect as the agent.**

   ```bash
   scripts/demo-ui.sh
   ```

   Inspector opens in the browser, set to the Tanzu gateway URL with the agent's token. Connect, then list the tools: `whoami` and `reset`.

   Why: the agent knows one URL, the Tanzu MCP Gateway's. The tools it sees come from AgentMinder, which filters them by the agent's permissions.

2. **Read.** Run `whoami`.

   The echo server answers with what it received: the agent's own token (its `aud` is the AgentMinder gateway, its `scope` holds `echo.read` and `echo.write`) and the identity headers AgentMinder adds, such as `Appname` and `Clientid`.

   Why: identity passes through both gateways to the MCP server.

3. **Write.** Run `reset`. It works.

4. **Revoke write.** Remove `urn:iam:agent:intent:echo.write` from the policy's grant rule in the admin console, or run:

   ```bash
   scripts/demo.sh revoke write
   ```

   Wait about 30 seconds, then list the tools again in Inspector: only `whoami` is left. `whoami` still runs. Calling `reset` from a client that still has it in an older list is refused.

   Why: AgentMinder checks the policy on every call, so the revoke reaches the token the agent already holds. Nothing changed on the agent, the token or the Tanzu gateway.

5. **Grant it back.**

   ```bash
   scripts/demo.sh grant write
   scripts/demo-ui.sh
   ```

   Stop the old Inspector first (Ctrl+C). With the new token, `reset` is back.

   Why: a grant only reaches tokens minted after it. Agents with short-lived tokens pick it up on their next token.

## Reset after the demo

```bash
scripts/demo.sh grant write
```
