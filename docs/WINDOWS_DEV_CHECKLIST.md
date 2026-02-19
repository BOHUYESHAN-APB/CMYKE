# Windows Dev Checklist (pre-beta)

Updated: 2026-02-19

## 1) Must Work End-to-End

- Standard chat:
  - multi-round concurrent web search through gateway (when enabled)
  - multi-image + file uploads (persisted + rendered)
- Deep research:
  - questionnaire constraints applied (deliverable/depth/export formats)
  - multi-round search loop + trace IDs
  - user attachments injected into research goal
  - per-run outputs under workspace with `manifest.json`

## 2) Gateway + OpenCode

- Desktop release can auto-start `cmyke-backend` when gateway is enabled and health-check fails.
- Gateway can locate `opencode` when bundled next to `cmyke-backend`:
  - `opencode.exe`, or `tools/opencode.exe`, or `CMYKE_OPENCODE_BIN`.

## 3) Packaging

- Windows bundle includes:
  - `cmyke.exe` + `data/`
  - `cmyke-backend.exe`
  - `opencode.exe` (bundled)
- Never ship `Studying/` in the release.

## 4) Regression Sweep (manual, fast)

- Settings:
  - tool gateway base URL / token can be edited and saved
  - "Create pairing" works on desktop
  - "Test connection" works
- Chat:
  - send message with only attachments
  - send message with text + attachments
- Deep research:
  - run a small task, export DOCX/PDF fallback behavior is clear

