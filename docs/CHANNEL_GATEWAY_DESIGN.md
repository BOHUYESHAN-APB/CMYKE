# Channel Gateway & Adapter Design (Draft)

Goal: let users talk to CMYKE **inside other chat apps** (Telegram/Feishu/etc.)
without installing the CMYKE client, by running a local gateway daemon.

This doc scopes **channels**, **adapters**, **routing**, and **risk handling**.

## Scope (Current Decisions)

- **Priority channels:** Telegram → Feishu/Lark → Computer-Use.
- **QQ/WeChat:** not direct bot integration for now (high risk / high compliance cost).
  - Instead: use **Computer-Use** control of the local QQ/WeChat client.
  - This is slower but most stable for now.
- **WhatsApp/Slack/Discord:** deferred until the core gateway is stable.

## Gateway Pairing (LAN + WAN)

- **LAN pairing**: local discovery (mDNS/UDP) + short-lived token.
  - Best UX and lowest latency.
- **WAN pairing**: explicit gateway URL + long-lived token.
  - Required for cloud-hosted gateways.
  - Must enforce TLS and token rotation.

## High-Level Architecture

```
Chat App (Telegram/Feishu/WhatsApp)
   -> Channel Adapter
   -> Gateway (Rust)
   -> CMYKE Core (LLM + memory + tools)
   -> Gateway -> Adapter -> Chat App
```

### 1) Gateway (Rust daemon)

- Extend the existing `backend-rust` service into a gateway.
- Runs on a host machine.
- Owns:
  - **Channel registry** (enabled adapters + configs)
  - **Message router** (normalize inbound/outbound messages)
  - **Session mapping** (channel user -> CMYKE session)
  - **Policy & allowlist** (pairing, rate limits, etc.)
  - **Tool routing** (OpenCode for Deep Research, built-in MCP for normal tasks)

### 2) Channel Adapters

Each adapter is a thin bridge:

- `Inbound`: platform event -> `InboundMessage`
- `Outbound`: `OutboundMessage` -> platform API call

Adapters can be:
- Rust-native (preferred for core platforms)
- Node/Python (allowed via MCP or subprocess with strict policy)

### 3) Message Envelope (normalized)

```
InboundMessage {
  channel: "telegram|feishu|whatsapp|computer_use",
  user_id: "...",
  user_display: "...",
  chat_id: "...",
  text: "...",
  media: [...],
  timestamp: "...",
  trace_id: "..."
}

OutboundMessage {
  channel: "...",
  chat_id: "...",
  text: "...",
  media: [...],
  reply_to?: "...",
  trace_id: "..."
}
```

## Gateway API Spec (Draft)

This section formalizes the message schema and pairing/session mapping. It is
intended for the Rust gateway and any channel adapters.

### InboundMessage (Adapter -> Gateway)

```json
{
  "id": "msg_01J3Z9C9E8XW7FQK2P1E5X7W7A",
  "channel": "telegram",
  "source": { "kind": "user", "id": "telegram:123456" },
  "user": { "id": "123456", "display": "Alice", "avatar_url": "https://..." },
  "chat": { "id": "chat_abc", "type": "dm", "title": "Alice" },
  "content": { "text": "hello", "media": [] },
  "reply_to": "msg_01J3Z8...",
  "timestamp": "2026-02-17T16:10:00Z",
  "trace_id": "trace_01J3Z9...",
  "raw": "{}"
}
```

### OutboundMessage (Gateway -> Adapter)

```json
{
  "id": "out_01J3Z9C9E8XW7FQK2P1E5X7W7A",
  "channel": "telegram",
  "chat_id": "chat_abc",
  "text": "reply text",
  "media": [],
  "reply_to": "msg_01J3Z8...",
  "mentions": ["123456"],
  "trace_id": "trace_01J3Z9...",
  "allow_stream": false
}
```

### MediaRef (shared)

```json
{
  "id": "media_01J3Z9...",
  "kind": "image|audio|video|file",
  "mime": "image/png",
  "url": "https://...",
  "path": "workspace/<session_id>/inputs/img.png",
  "size_bytes": 12345,
  "width": 1024,
  "height": 768,
  "duration_ms": 0,
  "sha256": "..."
}
```

### SessionMap (channel identity -> CMYKE session)

```json
{
  "map_id": "map_01J3Z9...",
  "channel": "telegram",
  "chat_id": "chat_abc",
  "user_id": "123456",
  "session_id": "sess_01J3Z9...",
  "pairing_id": "pair_01J3Z9...",
  "status": "active|blocked|pending",
  "routing": { "agent_id": "default", "workspace_id": "main", "policy": "default" },
  "created_at": "2026-02-17T16:00:00Z",
  "last_seen_at": "2026-02-17T16:10:00Z",
  "expires_at": null
}
```

### Pairing (LAN + WAN)

**PairingOffer**

```json
{
  "pairing_id": "pair_01J3Z9...",
  "mode": "lan|wan",
  "status": "offered|accepted|active|expired|revoked",
  "short_code": "A7H3",
  "token": "long_or_short_token",
  "expires_at": "2026-02-17T16:20:00Z",
  "gateway": {
    "id": "gw_01J3Z9...",
    "name": "cmyke-desktop",
    "url": "https://gateway.example.com",
    "ip": "192.168.1.10",
    "port": 4891
  },
  "client": {
    "device_id": "device_01J3Z9...",
    "device_name": "Pixel 9",
    "app_version": "0.1.0"
  }
}
```

LAN pairing uses mDNS/UDP discovery plus a short-lived `short_code` + token
exchange. WAN pairing uses explicit `gateway.url` and a long-lived token with
rotation. WAN must enforce TLS and token rotation policies.

### Gateway HTTP API (Draft, v1)

```
GET  /api/v1/gateway/info
GET  /api/v1/gateway/capabilities
GET  /api/v1/events            (SSE or WS upgrade)

POST /api/v1/messages/inbound  (adapter -> gateway)
POST /api/v1/messages/outbound (gateway -> adapter)

POST /api/v1/session-map/resolve
GET  /api/v1/session-map/{map_id}
PUT  /api/v1/session-map/{map_id}
DELETE /api/v1/session-map/{map_id}

POST /api/v1/pairing/lan/offer
POST /api/v1/pairing/lan/accept
POST /api/v1/pairing/wan/create
POST /api/v1/pairing/wan/rotate
GET  /api/v1/pairing/{pairing_id}
```

### backend-rust Layout Suggestion

```
backend-rust/src/
  main.rs
  gateway/
    mod.rs
    types.rs
    routes.rs
    pairing.rs
    session_map.rs
    adapter/
      mod.rs
      registry.rs
      telegram.rs
      feishu.rs
      computer_use.rs
    router/
      mod.rs
      message_router.rs
      policy.rs
    storage/
      mod.rs
      session_map_store.rs
      pairing_store.rs
```

## Learnings from openclaw / nanobot

From the cloned repos:

- **openclaw**: a gateway daemon with channel adapters + strong security policy.
  - Key lesson: external channels should **not receive streaming partial replies**.
- **nanobot-cn**: ultra-light, clear bus model + config-based channels.
  - Useful pattern: simple `MessageBus`, config-driven channel activation.

## Computer-Use Adapter (QQ/WeChat fallback)

Why: official QQ/WeChat bot APIs are hard to obtain; unofficial APIs are high risk.

Approach:

1) **Capture**
   - **Windows**: prefer UI Automation (UIA) element-tree when stable.
   - Fallback: periodic screenshot + OCR + layout heuristics.
   - **macOS/Linux**: screenshot + OCR by default.
2) **Normalize**
   - Convert screen text into `InboundMessage` with `source=computer_use`.
3) **Respond**
   - Use UI automation to click input box + paste text + send.

### Windows UIA + OCR Fallback (Design)

**Core idea**: UIA is the first-class path for speed, structure, and lower cost.
OCR is the safety net when UIA is missing, broken, or ambiguous.

**Windows UIA path (preferred):**
- **Attach**: enumerate top-level windows by process name/title; pick the active
  QQ/WeChat window or configured target.
- **Map**: walk the UIA tree to locate key elements:
  `chat list`, `message list`, `input box`, `send button`, `new message badge`.
- **Read**: pull text via UIA TextPattern / ValuePattern with timestamps if
  available; fall back to Name/HelpText if text patterns are absent.
- **Act**: focus input box, paste response, trigger send via InvokePattern or
  keyboard (Enter/Ctrl+Enter based on app settings).
- **Verify**: UIA result check (message list updated or “sent” indicator).

**Health checks / failover triggers:**
- UIA tree missing critical nodes (`input box` or `message list`).
- UIA text extraction returns empty or repeated stale content.
- UIA element bounding rectangles are zero/invalid.
- Actuation fails (no UI state change within timeout).

**OCR fallback path (when UIA fails):**
- Capture window-only screenshot (not full desktop when possible).
- Detect layout regions: `chat list`, `message list`, `input area`.
- Run OCR on message list ROI; parse into message blocks by line grouping.
- Use template anchors (avatar bubble edges, timestamps) to de-duplicate.

**Hybrid strategy (best of both):**
- Use UIA for control/actuation even when OCR is used for reading.
- If OCR identifies the active chat or unread indicator, use UIA to click it.
- Cache UIA element IDs and OCR ROIs per app version to speed next run.

Constraints:
- Slower latency.
- Sensitive to UI changes.
- Must be rate-limited and debounced.
- UIA reliability varies by client version; must detect and fallback to OCR.

### OCR Strategy: System OCR vs Model OCR

We treat OCR as **two classes**:

1) **System OCR** (built-in, free)
2) **Model OCR** (local or cloud)
   - Local and cloud are the same class; only the runtime location differs.

**System OCR (first pass):**
- Fast, zero-cost, low setup.
- Best for short messages, clean contrast, and stable fonts.
- Works well when UI provides clean text rendering and minimal overlap.

**Model OCR (second pass):**
- Higher accuracy on dense chats, small fonts, emoji-heavy content, or
  mixed languages.
- Use **local** model first when available; **cloud** only if user allows.
- Enables advanced parsing (bubble boundaries, timestamps, sender labels).

**Routing policy (complexity-aware):**
- Start with **System OCR** on the message list ROI.
- If UI is dense/complex or System OCR confidence is low:
  - Switch to **Model OCR** (local preferred; cloud optional).
- Allow per-user config: cost cap, “allow cloud”, and max OCR fps.

### Cost Strategy & Confidence Thresholds (Suggested)

**Budgeting controls:**
- **Rate limit** OCR by chat activity (e.g., 1 scan per 1–3 seconds).
- **Skip** OCR when window is unfocused or inactive.
- **ROI-only** OCR (message list region), never full-screen by default.
- **Cache** last N message hashes to avoid repeat OCR on static screens.

**Confidence thresholds (pragmatic defaults):**
- **System OCR accept**: ≥ 0.90 average confidence on message lines.
- **Borderline**: 0.75–0.90 → retry System OCR once or switch to Model OCR.
- **Fail**: < 0.75 → Model OCR required.

**Model OCR escalation policy:**
- Prefer **local** model unless user explicitly allows cloud.
- For cloud OCR, enforce **daily budget** and **hard cap** per session.
- If cloud budget exceeded: fall back to local model or reduce scan frequency.

**Quality vs cost tuning knobs:**
- Confidence threshold (`system_accept`, `system_borderline`).
- OCR scan interval (idle vs active chat).
- Max image size / downscale ratio.
- Cloud usage toggle and per-day token/cost limit.

## Compliance & Risk Policy

- Only official bot APIs are supported by default.
- Unofficial bridges are opt-in and require explicit risk acceptance.
- Computer-Use mode is the safest fallback but has UX costs.

## Phased Implementation

Phase 1:
- Telegram adapter (bot token)
- Feishu/Lark adapter (websocket long connection)
- Gateway daemon + routing + allowlist (in `backend-rust`)

Phase 2:
- Computer-Use for QQ/WeChat (Windows only first)

Phase 3:
- WhatsApp (bridge or official)
- Slack/Discord
- More enterprise channels
