# Cursor Agent Integration

Symphony can route Linear issues to Cursor through the `cursor` runtime. The
current path uses a long-lived Cursor ACP bridge so Cursor follows the same
session shape as Codex app-server runs.

The bridge command is intentionally short and portable:

```sh
cursor-symphony-bridge
```

Workflow configs should prefer the env-driven command so other machines do not
need a hardcoded user path:

```yaml
cursor:
  command: '"${SYMPHONY_CURSOR_BRIDGE:-cursor-symphony-bridge}"'
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
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

Cursor Agent supports both local login and API-key authentication. The bridge
does not hardcode an account and does not assume `popcornqhd@gmail.com`; it uses
the active Cursor CLI login on the current machine unless `CURSOR_API_KEY` is
set.

For a developer machine, prefer the Cursor login stored by the CLI:

```sh
cursor-agent login
cursor-agent status
```

For CI or non-interactive machines, use an API key:

```env
CURSOR_API_KEY=...
```

To prevent accidental use of the wrong local account, set:

```env
SYMPHONY_CURSOR_EXPECTED_ACCOUNT=you@example.com
```

When set, the bridge runs Cursor CLI `status` before launching and fails fast if
the active account does not match. Leave it blank if the current machine should
use whichever Cursor account is logged in.

## Observability

Cursor runs now emit the same Symphony app-server events as Codex, including
`session_started`, turn notifications, and `turn/completed`. The bridge also
writes a local activity log under:

```text
~/.cache/symphony-logs/cursor-bridge-<pid>.log
```

Token accounting depends on Cursor ACP's response payload. Symphony records
usage when the bridge receives a `usage` map and forwards it with
`turn/completed`; some Cursor accounts or CLI versions may omit token counts.
