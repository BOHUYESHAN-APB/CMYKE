# OpenCode CLI Tool Contract (Draft)

This document defines how CMYKE integrates OpenCode CLI for tool execution and MCP delegation.

## 1) Sandbox Directory Strategy

All OpenCode executions are sandbox-only. The Tool Gateway must enforce the per-session workspace layout:

```
workspace/
  <session_id>/
    inputs/
    scratch/
    outputs/
    logs/
```

Rules:
- `cwd` defaults to `workspace/<session_id>/scratch/`.
- `files[]` must resolve under `workspace/<session_id>/`.
- Absolute paths are rejected unless they are mapped to the workspace root.
- The Tool Gateway performs path normalization and denies `..` escapes.

## 2) tool.opencode.run Schema

### 2.1 Input

```jsonc
{
  "name": "tool.opencode.run",
  "description": "Run OpenCode CLI in non-interactive mode inside the sandbox workspace",
  "input_schema": {
    "type": "object",
    "required": ["session_id", "message"],
    "additionalProperties": false,
    "properties": {
      "trace_id": {"type": "string"},
      "session_id": {"type": "string"},
      "message": {"type": "string"},
      "command": {"type": "string", "description": "Maps to --command"},
      "model": {"type": "string", "description": "provider/model"},
      "agent": {"type": "string"},
      "files": {
        "type": "array",
        "items": {
          "type": "object",
          "required": ["path"],
          "additionalProperties": false,
          "properties": {
            "path": {"type": "string"},
            "label": {"type": "string"}
          }
        }
      },
      "cwd": {"type": "string", "description": "Relative to workspace/<session_id>"},
      "format": {"type": "string", "enum": ["json", "default"], "default": "json"},
      "share": {"type": "boolean", "default": false},
      "attach": {"type": "string", "description": "Server URL, maps to --attach"},
      "port": {"type": "integer", "description": "Maps to --port"},
      "continue": {"type": "boolean", "default": false},
      "session": {"type": "string", "description": "Maps to --session"},
      "fork": {"type": "boolean", "default": false},
      "title": {"type": "string"},
      "timeout_ms": {"type": "integer", "description": "Tool Gateway enforced"}
    }
  }
}
```

### 2.2 Output

```jsonc
{
  "type": "object",
  "required": ["ok", "exit_code", "stdout", "stderr"],
  "additionalProperties": false,
  "properties": {
    "ok": {"type": "boolean"},
    "exit_code": {"type": "integer"},
    "stdout": {"type": "string"},
    "stderr": {"type": "string"},
    "format": {"type": "string", "enum": ["json", "default"]},
    "events": {
      "type": "array",
      "items": {"type": "object"},
      "description": "Parsed JSON events when format=json"
    },
    "session_id": {"type": "string"},
    "trace_id": {"type": "string"},
    "files_written": {
      "type": "array",
      "items": {"type": "string"},
      "description": "Workspace-relative paths discovered after run"
    },
    "duration_ms": {"type": "integer"}
  }
}
```

### 2.3 CLI Mapping

- `message` -> `opencode run [message..]`
- `command` -> `--command`
- `model` -> `--model`
- `agent` -> `--agent`
- `files[]` -> repeated `--file`
- `format` -> `--format`
- `share` -> `--share`
- `attach` -> `--attach`
- `continue` -> `--continue`
- `session` -> `--session`
- `fork` -> `--fork`
- `title` -> `--title`
- `port` -> `--port`

## 3) MCP Delegation Mode (Deep Research -> OpenCode)

For Deep Research, the Rust Tool Gateway must **delegate MCP and tool execution to OpenCode**:

- Gateway starts or reuses `opencode serve` and calls `opencode run --attach` for each tool invocation.
- OpenCode handles MCP tool discovery and execution; the gateway only proxies and enforces policies.
- All OpenCode runs are scoped to `workspace/<session_id>` as described above.

Notes:
- `opencode serve` provides a headless server to avoid MCP cold starts.
- `opencode run` supports `--attach` for server reuse and `--format json` for structured event output.

## 4) Error Semantics

- If OpenCode exits non-zero, return `ok=false` with `stderr` populated.
- If sandbox policy is violated, reject before invoking OpenCode and return `ok=false` with a policy error.
- If `format=json` and event parsing fails, keep `stdout` and set `events` to empty.
