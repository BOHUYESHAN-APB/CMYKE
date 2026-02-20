# CMYKE Roadmap / 发展方向（Draft）

本文件用于记录 CMYKE 后续的主要发展方向与阶段性里程碑，避免“边做边改”导致架构反复。

## 项目定位（不变的原则）

- **Realtime / Voice-first**：实时语音/低延迟对话模型是核心路线，不是附属模式。
- **多平台优先**：Windows / macOS / Linux / Android / iOS 同一套 Flutter UI 与统一协议。
- **企业化优先**：可部署、可观测、可审计、可配置；后端能力优先于“堆 UI 功能”。
- **可插拔**：模型、工具、插件、知识库、渲染器均可替换/扩展。

## 当前状态（2026-01）

- Flutter：UI、Provider 配置、本地 SQLite、四级记忆、动作/记忆小模型 agent 已具备雏形。
- Rust：已加入最小 REST 后端骨架（`backend-rust/`，目前仅健康检查）。
- Python：作为可选扩展层存在（尚未形成稳定的插件注册/调用协议）。

## 总体架构方向（建议）

### 1) 端侧（Flutter）

- 只做 UI/交互/渲染与少量“离线兜底”（可选）。
- **默认不承载**工具回路、记忆治理、插件编排等“系统层”逻辑。
- 通过配置切换：
  - **直连模式**：Flutter 直接调用 OpenAI-compatible Provider（开发/离线/快速验证）。
  - **后端模式（主路径）**：Flutter 调用 Rust Backend（REST/WS），由后端统一编排工具/记忆/插件。

### 2) 后端（Rust，主路径）

- 对外提供稳定 API（REST + WS）：
  - `chat`：会话、消息、流式输出、路由（standard/realtime/omni）。
  - `memory`：四级记忆的写入/检索/去重/归档/导入导出。
  - `tools`：工具注册、权限、审计、执行与结果落库。
  - `plugins`：插件生命周期、能力声明、事件总线。
  - `telemetry`：trace_id、日志、错误面板、性能指标。
- 对内形成统一“编排层”：
  - Standard：主 LLM 可直接工具调用（或由后端解析 tool calls）。
  - Realtime：Realtime 模型只负责对话与轻量意图，工具调用由 Control/Planner agent 决策执行。

### 3) Python（可选扩展层）

- 不作为系统“主脑”，而是作为：
  - MCP server、模型服务、专用工具执行器（例如浏览器、OCR、特定库、现成生态）。
- 通过 **HTTP/MCP** 方式注册到 Rust 的 Tool Registry，由 Rust 统一权限与审计。

## 里程碑（建议分期）

### M0：协议冻结（短期）

目标：让“多端 + 可部署后端”先跑起来，避免一开始就做成大而全的单体。

- 定义一套最小后端 API（版本化，`/api/v1`）：
  - `GET /health`
  - `POST /chat/stream`（SSE 或 WS）
  - `GET/POST /memory/...`（先做读写与导入导出）
- 定义统一事件模型（文本/音频/工具/动作/表情），为后续 WS 打通做准备。
- Flutter 增加后端 baseUrl + enable 开关（先只用于 health 与简单 chat）。

验收标准：
- Flutter 在 Android/iOS/Desktop 都能连接同一个远端后端完成基本对话。

### M1：记忆系统后移（中短期）

目标：把“记忆治理”从前端迁移到后端，形成企业可控的记忆生命周期。

- 后端实现四级记忆的 CRUD、检索（embedding + keyword fallback）。
- 实现“记忆 Agent”服务化：抽取核心/日记、查重、合并、归档。
- 提供导入/导出统一格式（JSON + Markdown），并保持可审计（来源/时间/trace）。

验收标准：
- 前端不再负责记忆抽取与去重，只展示与编辑。

### M2：工具系统与插件化（中期）

目标：补齐 N-T-AI / MoeChat 的“工具回路 + 插件编排”能力，但以 Rust 作为统一入口。

- Tool Registry：schema、权限、timeout、审计日志。
- Python 工具作为插件（HTTP/MCP）注册；Rust 统一调度与落库。
- 统一“工具输出 → 记忆/知识库”落库路径，支持回放与追踪。

验收标准：
- 工具调用在 Standard 与 Realtime 两条链路中均可用，且可审计。

### M3：Realtime 语音链路（中期）

目标：落地真正的 Realtime/Voice-first 管线（双工、打断、低延迟）。

- WS 通道：音频 in/out、partial transcript、barge-in、状态机。
- Control/Planner agent：实时模式下代表用户做工具决策与执行，不阻塞对话主线。
- 语音与渲染同步：口型、表情、动作事件随音频/语义触发。

验收标准：
- 移动端可用、可打断、端到端延迟可控（指标可观测）。

### M4：渲染与桌宠（中长期）

目标：统一 Live2D/Live3D 渲染控制通路与动作库调用机制。

- 统一 ExpressionEvent / StageAction 事件协议（端侧渲染器消费）。
- 动作库标准化：动作元数据、触发条件、优先级、叠加规则、回到 idle 的策略。
- 桌宠模式：只展示模型、可跟随鼠标（桌面端）。

验收标准：
- 不出现“站桩/抽搐/T-pose”之类不稳定动作；动作可追踪来源（哪个 agent/规则触发）。

### M5：具身/外部控制（远期，VRChat/机器人）

目标：在 **Realtime/Omni 实时交流模式**下，支持可选的“具身控制”链路（例如 VRChat OSC、机器人控制），并确保可审计、可中断、可配置。

关键原则：
- 标准模式不接入外部执行器。
- 具身链路与关键系统输出采用 JSON-first 协议（结构化输出），避免靠特殊分隔符和长文本传话。
- 必须具备安全闸门（allowlist、速率限制、急停、权限提示）与全量 JSONL 日志回放。

前置现实：
- VLA/具身模型推理通常需要独立算力设备（NVIDIA GPU 桌面或边缘推理设备；也可先做远端推理服务）。

设计文档：
- `docs/EMBODIMENT_ARCHITECTURE.md`
- `docs/STRUCTURED_OUTPUT_PROTOCOL.md`

## 与参考项目的“迁移优先级”

- `Studying/N-T-AI-main`：后端编排、工具回路、MCP、企业化治理思路（优先抽象“协议与边界”）。
- `Studying/MoeChat-main`：核心记忆 + 日记记忆、时间范围检索、记忆编辑思路（迁移“方法论 + 关键交互”）。
- `Studying/my-neuro-main`：Realtime 语音、打断、体验细节（迁移“状态机与交互策略”）。
- `Studying/memU-main`：分层记忆结构、可追溯与自演化分类（迁移“归档/分类/追溯”设计）。

## 开放问题（待定）

- Realtime 音频协议选型：SSE + chunk vs WS 双工（推荐 WS）。
- 多租户与权限：是否需要用户体系/工作区隔离（企业化必做）。
- 数据治理：加密、备份、导出、合规审计、删除策略。
- 工具执行沙箱：Docker/WSL/远端 runner 的策略与风险控制。
