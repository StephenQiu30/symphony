# Cursor Agent Integration

Symphony can route Linear issues to Cursor through the `cursor` runtime. The
current path uses a long-lived Cursor ACP bridge so Cursor follows the same
session shape as Codex app-server runs.

The bridge command is intentionally short and portable:

```sh
cursor-symphony-bridge
```

Workflow configs should prefer the stable PATH command installed by
`mix symphony.install`:

```yaml
agents:
  cursor:
    command: cursor-symphony-bridge
    approval_policy: never
    thread_sandbox: workspace-write
    turn_sandbox_policy:
      type: workspaceWrite
routing:
  by_label:
    agent:cursor: cursor
    agent:claude: cursor
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

Using the symlink keeps `WORKFLOW.md` portable across machines without a
machine-specific command path.

## Authentication Modes

Cursor Agent supports both local login and API-key authentication. The bridge
does not hardcode an account and does not assume `popcornqhd@gmail.com`.

Authentication precedence:

1. Non-empty `CURSOR_API_KEY` from the shell or project `.env`
2. The active Cursor CLI login on the current machine

For a developer machine, prefer the Cursor login stored by the CLI:

```sh
cursor-agent login
cursor-agent status
```

For CI or non-interactive machines, use an API key:

```env
CURSOR_API_KEY=...
```

It is safe to leave `CURSOR_API_KEY=` blank in the project `.env`; the bridge
will fall back to the active Cursor CLI login.

To prevent accidental use of the wrong local account, set
`SYMPHONY_CURSOR_EXPECTED_ACCOUNT` in the shell or project `.env`:

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
