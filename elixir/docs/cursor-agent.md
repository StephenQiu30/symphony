# Cursor Agent Integration

Symphony can route Linear issues to Cursor through the `cursor` runtime.

The current production path uses Cursor Agent headless mode:

```sh
cursor-symphony-bridge -p --force --sandbox disabled --output-format stream-json
```

`AgentCli` appends the required headless flags when they are missing, so
workflow configs should prefer the short command:

```yaml
cursor:
  command: '"${SYMPHONY_CURSOR_BRIDGE:-cursor-symphony-bridge}"'
```

## Install The Bridge

Install helper scripts into `~/.local/bin` from the Symphony checkout:

```sh
cd elixir
mise exec -- mix symphony.install
```

This creates or updates symlinks such as:

```text
~/.local/bin/cursor-symphony-bridge -> <symphony checkout>/scripts/cursor-symphony-bridge
```

Using the symlink keeps `WORKFLOW.md` portable across machines. A local `.env`
may still override the command path:

```env
SYMPHONY_CURSOR_BRIDGE=/path/to/symphony/scripts/cursor-symphony-bridge
```

## Authentication Modes

Cursor Agent supports both local login and API-key authentication.

For a developer machine, prefer the Cursor login stored by the CLI:

```sh
cursor-agent login
cursor-agent status
```

For CI or non-interactive machines, use an API key:

```env
CURSOR_API_KEY=...
```

The bridge does not hardcode an account. It uses whatever `cursor-agent` uses
on the current machine. To prevent accidental use of the wrong local account,
set:

```env
SYMPHONY_CURSOR_EXPECTED_ACCOUNT=you@example.com
```

When set, the bridge runs `cursor-agent status` before launching and fails fast
if the active account does not match.

## Observability

Cursor Agent `stream-json` emits a `system/init` event with fields such as
`apiKeySource`, `session_id`, `model`, `permissionMode`, and `cwd`.
Symphony emits a `runtime_authenticated` event from that payload so dashboards
and logs can distinguish:

- `login` — local `cursor-agent login` account
- `env` — `CURSOR_API_KEY`
- `flag` — explicit `--api-key`

Token accounting depends on Cursor's emitted payloads. Symphony records usage
when Cursor emits `result.usage`, including on non-zero exits, but Cursor may
omit token counts for some accounts or CLI versions.

## Reference: ACP Bridge

The `wildmaker/symphony` fork demonstrates a deeper Cursor integration through
Cursor CLI ACP (`agent acp`). That bridge keeps a long-lived Cursor session and
adapts it to Symphony's app-server JSON-RPC shape.

That design is a better long-term direction when Cursor should behave like
Codex app-server:

- persistent sessions across turns
- one long-lived backend process per workspace
- ACP permission handling
- optional MCP injection

Migrating to ACP should be done as a separate runtime-path change because this
repository currently routes Cursor through the CLI runtime (`AgentCli`), while
Codex uses the app-server path (`Codex.AppServer`).
