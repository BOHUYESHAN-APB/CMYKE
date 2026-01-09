# CMYKE Architecture (Draft)

This document captures the base architecture so the UI can scale toward a
realtime, multimodal agent runtime without breaking core UX.

## Goals

- ChatGPT-style UX first: multi-session chat, message queue, exportable logs.
- Four-tier memory model that can grow into SQLite + vector DB backends.
- Clear separation between UI, domain models, and storage to support future
  Rust core + optional Python extensions.

## Modules

- UI (Flutter)
  - Chat shell, session sidebar, message list, composer, memory panel.
  - Works without any backend; ready to bind to realtime gateway later.
- Domain Models
  - `ChatSession`, `ChatMessage`, `MemoryRecord`, `MemoryTier`.
- Repositories
  - `ChatRepository`: owns sessions, active session, message queue.
  - `MemoryRepository`: owns memory tiers and retrieval counts.
  - `SettingsRepository`: stores model routing + provider catalogs.
- Services
  - `LocalStorage`: JSON persistence in `Documents/cmyke/`.
  - `ChatExportService`: exports logs to `Documents/cmyke/exports/`.

## Memory Tiers

1) Context (in-session)
   - Short-term context window for the active chat.
2) Cross-session memory
   - Frequently used persona facts that can be injected into system prompts.
3) Autonomous memory
   - Self-saved insights from the model (text/image summaries).
4) External knowledge base
   - User-imported professional data; only fetched on-demand.

Current storage uses JSON for local prototyping. The repository layer can be
swapped to SQLite and vector backends (SQLite + FTS5, LanceDB, Qdrant, etc.)
without UI changes.

## Model Routing (Draft)

- Standard LLM stack: LLM + Vision Agent + TTS + STT.
- Realtime stack: single realtime voice model (audio in/out, barge-in).
- Omni stack: single full-modal model (text/vision/audio).

These are configured in-app, backed by a provider catalog for each kind
(LLM, Vision Agent, Realtime, Omni, TTS, STT).

## Current Integration Notes

- Standard + Realtime routes use OpenAI-compatible `/v1/chat/completions`
  (streaming enabled).
- Voice input/output is currently handled locally via STT/TTS to support
  barge-in testing. Native realtime audio WS integration is planned next.
- Provider protocols supported: OpenAI-compatible (OpenAI/SiliconFlow/DashScope/
  LM Studio) and Ollama native (`/api/chat`).

## Runtime Evolution (Planned)

- Rust Core
  - Realtime event bus (audio/text/tool events).
  - Session occupancy state machine (idle → listening → processing → speaking).
- Optional Python Extensions
  - Self-hosted TTS/STT/LLM services via HTTPS.
  - MCP-compatible tool servers and adapters.

## Next Milestones

- Wire the chat UI to a realtime gateway (WS/SSE).
- Replace JSON storage with SQLite + vector index.
- Add file uploads and voice capture flows.
