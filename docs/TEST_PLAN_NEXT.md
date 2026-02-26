# Next Test Plan (Checklist)

This checklist collects the manual tests we have not fully validated yet. Keep it updated as features evolve.

Updated: 2026-02-26

## Tool Gateway / Web Search

- Verify gateway can be started as sidecar (desktop) and logs are written under `Documents/cmyke/workspace/<session_id>/logs/`.
- Verify Standard mode auto web search:
  - triggers on "最新/今天/官网/政策/价格" type queries,
  - runs 3+ parallel queries in one round,
  - injects snippets with `trace_id` into the prompt,
  - emits a `sourceKind=tool` status message in chat.
- Verify Deep Research web search loop:
  - runs multi-round search refinement,
  - de-duplicates queries and results,
  - stops on configured conditions and reports stop reason.
- Verify tool routing works for both Standard and Deep Research when gateway is enabled and pairing token is set.

## Deep Research UX / Deliverables

- Questionnaire:
  - multi-round display and timeout countdown are correct,
  - multi-select works for export formats (DOCX/PDF/PPTX/XLSX),
  - answers are applied to export and shown in preview/manifest.
- Deliverables:
  - `slides` deliverable uses "第N页" structure,
  - exported artifacts match the selected formats and are opened correctly.
- Ensure `[SPLIT]` does not appear in Deep Research outputs; if it appears, it should not split into multiple bubbles.

## Attachments (Images/Files)

- Standard chat:
  - allow multiple attachments in one send,
  - images are visible and analyzable by vision-capable provider,
  - file ingest writes to library + session workspace paths.
- Deep Research:
  - allow multiple attachments in one send,
  - attachment context includes `[IMAGE: ...]` tokens as expected,
  - report export can include user-provided images when requested by the prompt.

## Voice Channel (Windows)

- Device listing:
  - list capture (input) and render (output) devices,
  - default devices are detected correctly,
  - pairing hints (VB-CABLE CABLE Input/Output) are reasonable.
- Monitoring chain (VB-CABLE):
  - Discord/KOOK output -> virtual speaker -> virtual mic -> Windows default recording -> STT transcript,
  - transcript injection respects the "auto send to chat" toggle.
- Confirm current boundary: system STT follows Windows default recording device.

## Local Realtime Speech (Fun-Audio-Chat Line)

- Verify local speech-to-speech roundtrip latency on XPU and CPU fallback paths.
- Verify barge-in stability during continuous conversation (interrupt user/AI speech multiple times).
- Verify long-session stability (>=30 min) without stream deadlock, memory leak, or device reset.
- Verify degraded-mode behavior when TTS device falls back from XPU to CPU.

## Handoff Docs Consistency

- Verify `HANDOFF.md` and `docs/HANDOFF.md` share the same active-track statement (voice and VLA both active).
- Verify dates and run commands are current after each milestone update.
- Verify snapshot statements are explicitly marked as snapshot (avoid persistent claims like "always clean").
- Verify local `.git/hooks/pre-push` blocks `HANDOFF.md` and `docs/HANDOFF.md` from remote push by default.

## Desktop Packaging / Deployment

- Windows package includes frontend + `cmyke-backend.exe` and can auto-connect.
- Bundled OpenCode (`opencode.exe`) works with the gateway and shared skill store under `_shared/opencode/`.
- Dev vs release environment detection behaves as expected (base URLs, workspace locations, sidecar startup).

## Embodiment / External Control (Active Pre-Research)

- Standalone minimal experiment for VLA model loading/inference:
  - ModelScope download works (light + full) for `XiaomiRobotics/Xiaomi-Robotics-0-LIBERO`,
  - `transformers` can load with `trust_remote_code` and run one dummy forward pass,
  - `outputs.actions` exists and `processor.decode_action(...)` returns an action chunk with expected shape.
  - Note: this is a local-only experiment (not committed). Keep model files under `local_models/` (already gitignored).
- Proactive movement behavior in VRM sandbox:
  - avatar can keep purposeful movement toward goals without relying on a hand-authored trigger table,
  - collect metrics: goal completion rate, interact-too-far count, wall-contact count, manual override count,
  - verify rule-based logic is limited to safety gate/fallback and does not replace policy decisions.
