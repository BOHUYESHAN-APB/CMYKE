# Agent Record: OpenCode Gateway (Rust)

## API Design
- Endpoint: `POST /api/v1/opencode/run`
- Auth: pairing token required. Accepted via `pairing_token` in JSON body, or header `x-pairing-token`, or `Authorization: Bearer <token>`.
- Sandbox: workspace root resolved as `${CMYKE_WORKSPACE_ROOT:-workspace}/{workspace?}/{session_id}`.
  - `session_id` must be ASCII `[A-Za-z0-9_-]`.
  - `workspace`, `cwd`, and `files[].path` must be workspace-relative paths with no absolute paths or `..` segments.

## Request Structure (JSON)
- `pairing_token`: string (optional if provided in header)
- `trace_id`: string (optional, passed through)
- `session_id`: string (required)
- `workspace`: string (optional, subfolder under workspace root)
- `message`: string (optional)
- `input`: any JSON (optional). If `message` missing, `input` is serialized to JSON and used as the message.
- `timeout_ms`: integer (optional; default 120000ms; clamped by env max)
- `allowed_commands`: string[] (optional allowlist; if present, `command` must be in list)
- Pass-through CLI args:
  - `command`, `model`, `agent`, `files[]`, `cwd`, `format`, `share`, `attach`, `port`, `continue`, `session`, `fork`, `title`

## Response Structure (JSON)
- `ok`: bool
- `exit_code`: int (`-1` on spawn error or timeout)
- `stdout`: string
- `stderr`: string (appends `timeout` if timed out)
- `format`: `json|default`
- `events`: array of JSON objects parsed from `stdout` lines when format=`json`
- `session_id`: string
- `trace_id`: string | null
- `files_written`: string[] (currently always empty)
- `duration_ms`: integer

## Env Vars
- `CMYKE_WORKSPACE_ROOT`: workspace base dir (default `workspace`)
- `CMYKE_OPENCODE_TIMEOUT_MAX_MS`: max timeout clamp (default 300000)
- `CMYKE_OPENCODE_ALLOWED_COMMANDS`: comma-separated server allowlist (optional)

## Files Changed
- `backend-rust/src/main.rs`
- `backend-rust/Cargo.toml`

## Unresolved / Follow-ups
- `files_written` discovery is not implemented (always empty).
- No warm `opencode serve` management; only direct `opencode run`.
- Assumes `opencode` is on PATH; missing binary returns `ok=false` with stderr.
