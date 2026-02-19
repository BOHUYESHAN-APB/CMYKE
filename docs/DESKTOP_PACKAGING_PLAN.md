# Desktop Packaging Plan (PC-first)

This doc captures the plan for shipping CMYKE to real users on PC first:
- Frontend (Flutter desktop) and backend (Rust gateway) are shipped together.
- The app can detect dev vs non-dev environments and auto-connect to the gateway.
- OpenCode is treated as the primary tool-runtime dependency (distributed with CMYKE when feasible).

Updated: 2026-02-19

## 1) Current Reality (as-is)

- Flutter desktop can run standalone.
- Tool execution (web search/crawl/analyze/summarize/code) is delegated to the Rust gateway, which calls OpenCode CLI (`opencode`).
- `Studying/` contains third-party reference repos and must not be shipped in releases.

## 2) Distribution Layout (Windows, initial)

Target bundle layout:

- `cmyke.exe`
- `data/` (Flutter assets)
- `cmyke-backend.exe` (Rust gateway sidecar)
- `opencode.exe` or `opencode` (OpenCode CLI) and its runtime files if needed
- optional: `tools/` (extra tool binaries / MCP servers)
- runtime data: `workspace/_shared/opencode/` (OpenCode config + skills, created on first use)

Build helper (repo-local):
- `tools/package_windows.ps1` stages a Windows package folder and copies `cmyke-backend.exe` (+ optional `opencode.exe`).

## 3) Environment Detection

- Dev environment:
  - prefer developer-specified gateway base URL (Settings / env override).
  - do not assume a bundled backend exists.
- Non-dev environment (Release):
  - if gateway is enabled, auto-start bundled `cmyke-backend` if health-check fails.
  - best-effort auto-pairing if pairing token is empty (local desktop only).

## 4) Auto-Connect Algorithm (Gateway)

1. Read settings: `toolGatewayEnabled`, `toolGatewayBaseUrl`, `toolGatewayPairingToken`.
2. Health-check `GET {baseUrl}/api/v1/health`.
3. If unhealthy and in Release desktop:
   - spawn `cmyke-backend` from app directory.
   - wait for health-check ready.
4. If healthy and pairing token missing:
   - call `POST {baseUrl}/api/v1/gateway/pairing/create`
   - persist token into settings.

## 5) OpenCode Packaging Strategy

Goal: ship OpenCode with CMYKE to reduce user setup and keep tool integration consistent.

Practical constraints:
- We must decide if we ship a native binary or a Node-based CLI bundle.
- The Rust gateway should resolve `opencode` via:
  - `CMYKE_OPENCODE_BIN`, or
  - `opencode` next to the gateway executable, or
  - fallback to PATH.

## 6) Size Control (keep the package lean)

Main levers for Windows desktop:
- do NOT ship `Studying/`, `build/`, `backend-rust/target/`.
- audit large assets:
  - fonts (MiSans/HarmonyOS Sans variants)
  - motion packs / animations
  - large embedded vendor files

Quick observation from a sample Windows `Release/` folder:
- Biggest single files typically include: `kernel_blob.bin`, `flutter_windows.dll`, multiple CJK font TTFs, and animation packs.

## 7) Realtime Companion Mode (future)

Release goals for a "virtual companion" experience:
- proactive participation (autonomy loops, reminders, exploration) with explicit user controls
- background-safe scheduling (desktop) and clear permission boundaries
- tools and web search must still be available and traceable in this mode
