# Demo: revoke a tool live

Shows an agent losing a write tool the moment a security admin revokes its write permission in AgentMinder, while it keeps reading, with no change to the agent or the Tanzu MCP Gateway.

## Before you start

- Steps 1 to 4 of the quick start are done, and `scripts/04-test.sh` passes.
- Node is installed (see [testing.md](testing.md#install)).
- The agent holds both intents: `scripts/demo.sh show` prints `echo.read` and `echo.write`. If not, run `scripts/demo.sh grant write`.
- Optional: the AgentMinder admin console is open on the policy named `<AM_PREFIX>-agent`, to make the change there instead of with `scripts/demo.sh`.

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
