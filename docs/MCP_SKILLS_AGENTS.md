# MCP / Skills / Agents 设计方案（草案）

你提到的三块我们可以这样分层理解：

- **SAP（工具接入平台 / Tool Gateway）**：负责“连接外部工具与执行环境”，对上提供统一的 Tool API；对下对接 MCP server、HTTP API、本地进程、沙箱等。
- **MCP**：作为“工具协议”，让工具以统一方式被注册、发现、调用（跨语言、跨进程）。
- **Skills（能力编排）**：把多个工具调用串成可复用的工作流（带参数、约束、权限与输出模板）。
- **Agents（智能体）**：负责“决策与调度”，决定何时调用工具、何时运行 skill、如何把结果写回记忆/上下文。

这四个概念的关键是：**职责边界必须硬**，否则系统会变成“前端/后端/工具都能自己做主”，最终不可控、不可审计。

---

## 目标边界（建议的长期形态）

1. **Flutter（CMYKE）**
   - 只做 UI、配置、会话管理、渲染事件消费（Live3D/Live2D）。
   - 发起“意图”：用户消息、语音转写（mic/voice_channel）、弹幕等事件。
   - 不直接执行高风险工具，不直接管理 MCP 子进程。

2. **SAP（建议落在本地后端：优先 Rust）**
- Tool Registry：工具发现、能力列表、schema。
- Policy / Permissions：白名单、用户确认、隔离策略、速率限制。
- Executor：执行 MCP tool / HTTP tool / 本地 sandbox tool，并产出统一 ToolResult。
- **Special case (Deep Research):** delegate MCP/tool execution to OpenCode
  (Rust gateway only proxies and enforces policy).
   - Audit：每次 tool/skill/agent 执行都带 `trace_id`，可回放、可追责。

3. **Agents**
   - 标准模式：LLM 可以直接提出 tool call，但必须由 SAP 执行与裁决。
   - 实时模式：Realtime 模型只做对话；由 Control/Planner Agent 代表它调用工具（同样走 SAP）。

4. **Skills（应用内“技能”，不是 Codex 的 SKILL.md）**
   - 以声明式形式存储（建议 YAML/JSON），包含：
     - `name` / `description`
     - `inputs` schema
     - `policy`（是否需要确认、允许的工具集合、最大耗时/花费）
     - `steps`（顺序/并行 tool calls，带模板变量）
     - `output` 模板（如何渲染、是否写记忆）

---

## 为什么 SAP 这里“很可能需要 Rust 后端”

你之前的原则是“能原生就原生，不行再引 Rust”。对 **MCP + 工具执行** 这一块，Rust 后端的收益非常直接：

- 需要管理 **长生命周期子进程**（stdio MCP servers）、断线重连、超时/取消。
- 需要更强的 **权限与审计**（不应在 UI 里做）。
- 需要统一的 **沙箱/资源限制**（CPU/内存/文件系统/网络），后端更合适。

短期我们可以先保持 Flutter 侧 ToolRouter 为 stub（现在就是），同时把 SAP 的协议和边界先定死，避免后续推倒重来。

---

## 统一协议（必须先冻结）

### 1) Message 元数据（多源输入）

需要把“麦克风 / 语音频道 / 弹幕 / 插件 / 用户”统一成一个 envelope，不要再靠字符串前缀。

建议字段：

- `source.kind`: `user|mic|voice_channel|barrage|plugin|system`
- `source.id`: 例如 `discord:guild/channel` / `bilibili:roomId`
- `priority`: `USER|VOICE_CH|BARRAGE|PROACTIVE|LOW`
- `trace_id`: 贯通 tool/skill/agent 的链路 id

### 2) Tool 调用协议（SAP 对上）

- `ToolCall`: `{trace_id, tool_name, arguments, timeout_ms, policy_hint}`
- `ToolResult`: `{trace_id, ok, content, structured, error, cost_ms, citations?}`

### 2.1) OpenCode Delegation (Deep Research)

For Deep Research runs:

- `ToolCall` is wrapped and sent to OpenCode.
- OpenCode executes tools (including MCP) inside the sandbox.
- Rust gateway logs and enforces path/permission rules; it does **not**
  directly call MCP tools in this mode.
- OpenCode skills/config are managed under `workspace/_shared/opencode/` (shared across sessions).

Reference:
- OpenCode CLI tool contract and sandbox policy: `docs/OpenCode_CLI_Tool_Contract.md`

### 3) Skill 执行协议

- `SkillRun`: `{trace_id, skill_name, inputs, mode, policy}`
- `SkillResult`: `{trace_id, ok, outputs, side_effects(memory/events), error}`

---

## 运行时路由（和你现在的诉求对齐）

1. **语音频道（Windows）**
   - 语音频道转写 -> 进入同一条“输入事件管线”
   - Control/Planner Agent 决定：
     - 直接当消息注入（轻量）
     - 或先做汇总/去噪 skill（重一点）

2. **弹幕**
   - 默认只进“侧路上下文”
   - 通过 skill 批量汇总后再注入（防刷屏）

3. **工具**
   - 标准模式：LLM 可以触发 tool call，但 SAP 决定是否执行、是否需要确认
   - 实时模式：Realtime 模型不直连工具，由 Control/Planner Agent 发起 tool call

---

## 最小落地顺序（建议）

1. **先把“多源消息 source 元数据”做成正式字段**（mic/voice_channel/barrage/plugin）
2. **把 ToolRouter 从“回显”升级为“HTTP 调 SAP”**（哪怕 SAP 先是 stub）
3. **落 Skill Registry（本地 YAML/JSON + 校验 + 列表 UI）**
4. **再接 MCP runtime**（先接一个工具 server 作为样板）

---

## 标准接入字段（草案）

所有外部平台（MCP/Skills/Agents）统一采用“连接器配置”，先定义最小字段，便于 UI 与导入流程统一。

- `name`: 显示名。
- `kind`: `mcp` | `skill_bundle` | `agent_platform`。
- `base_url`: 平台入口或 MCP server 地址。
- `auth`: API Key / Token / OAuth 占位（具体协议后续细化）。
- `capabilities`: 能力标签（search / code / docs / vision / publish）。
- `enabled`: 是否启用。
- `notes`: 备注或限制说明。

## 标准接入流程（草案）

1. 用户在设置页选择“接入类型”。
2. 选择平台模板（如 Agent 平台 / Skill 包 / MCP Server）。
3. 填写 `base_url` 与 `auth`。
4. 选择启用的能力范围（Capabilities）。
5. 保存后进入“权限与审计策略”。

说明：以上为 UI 与数据结构对齐用的草案，具体平台模板内容会在接入阶段补充。

---

## 需要你确认的一个定义

你说的 **“SAP”**，我按“工具接入平台/网关”来理解。

如果你原意是：
- “MCP Router”（专门做 MCP server 汇聚与能力发现）
- 或 “系统接入平台”（包含账号/权限/连接器）

告诉我你希望 SAP 的职责范围，我再把上面的边界画得更精确（会影响是否必须 Rust、以及 Flutter 要不要直接连 MCP）。
