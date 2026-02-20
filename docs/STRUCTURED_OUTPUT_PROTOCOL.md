# JSON-First 结构化输出协议（Draft）

目标：用 **JSON-first** 的方式重构“模型输出 -> 系统行为”的组织方式，减少上下文浪费、降低解析歧义、支持多智能体协作与可审计回放。

本协议主要解决：
- Realtime/Omni 主脑模型上下文很宝贵，不应承载工具细节与长链路状态。
- 不同组件（Boss/Manager/Tool/Spine/Render）需要可机器消费的稳定接口。
- 依赖特殊分隔符（例如 `[SPLIT]`）会导致跨模式行为不一致，且难以扩展。

## 1) 原则

- 用户看到的“展示文本”可以是自然语言；系统内部必须是结构化消息。
- 任何会触发工具/外部动作/写入记忆的输出，都必须有对应 JSON 字段（可审计）。
- 可降级：模型不支持结构化输出时，允许 best-effort 文本解析，但必须记录“解析不可信”。

## 2) 通用信封（Envelope）

建议所有内部事件都统一一个 Envelope：

```json
{
  "v": 0,
  "type": "assistant_frame|tool_intent|tool_result|memory_write|expression|stage_action|action_frame",
  "trace_id": "std_1700000000000_0",
  "session_id": "chat_session_id",
  "ts_ms": 1700000000000,
  "payload": {}
}
```

说明：
- `type` 决定 payload schema
- `trace_id` 用于串联一次“思考 -> 工具 -> 输出”的完整链路

## 3) AssistantFrame（模型对系统的主输出）

AssistantFrame 的职责是：把“对用户说的话”和“系统要做的事”明确分开。

```json
{
  "display": {
    "text": "给你的简短回答...",
    "segments": [
      {"kind": "text", "text": "第一段..."},
      {"kind": "text", "text": "第二段..."}
    ]
  },
  "speech": {
    "text": "可朗读的台词正文（可选）"
  },
  "tool_intents": [
    {"action": "search", "query": "xxx", "routing": "standard_chat"}
  ],
  "memory_writes": [
    {"tier": "context", "content": "要写入的记忆（可选）"}
  ],
  "actions": [
    {"kind": "stage_action", "name": "wave", "priority": "low"}
  ]
}
```

约束：
- `display.segments` 用于 UI 分段显示，替代依赖 `[SPLIT]`。
- `speech.text` 与 `display.text` 可以不同（例如 display 更详细，speech 更短）。
- `tool_intents` 必须显式列出，不允许“在文本里暗示工具调用”。

## 4) ToolIntent / ToolResult

工具意图建议对齐现有 `ToolIntent` 模型：

```json
{"action":"search","query":"...","routing":"deep_research","trace_id":"..."}
```

工具结果建议落地为：

```json
{
  "ok": true,
  "stdout": "...",
  "stderr": "",
  "files_written": ["outputs/..."],
  "duration_ms": 1234
}
```

要求：
- 工具结果必须可落盘（JSONL），并与 `trace_id` 关联

## 5) 与模式的关系

标准模式（Standard）：
- 允许模型直接生成 `AssistantFrame`（包含 tool intents）
- UI 只展示 `display`

实时模式（Realtime/Omni）：
- Boss 只输出最小 `AssistantFrame`（display/speech）
- 工具/检索/规划由 Manager 产出独立的 `tool_intent`/`tool_result`/`control_plan`

具身控制（Embodiment）：
- 行为输出使用 `ActionFrame`（见 `docs/EMBODIMENT_ARCHITECTURE.md`）

## 6) 落地策略（建议）

阶段 1（兼容模式）：
- 保留现有文本输出路径
- 新增“结构化输出优先”的尝试：如果 provider 支持 structured outputs / JSON schema，则启用
- 否则回退到纯文本

阶段 2（强约束）：
- 对关键链路强制 JSON（工具、记忆写入、具身动作）
- 纯文本只允许存在于 `display/speech`

