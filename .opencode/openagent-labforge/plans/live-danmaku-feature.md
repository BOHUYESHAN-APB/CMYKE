# Live Danmaku Multi-Platform Abstraction (Phase-1)

## TL;DR
> **Summary**: Implement a production-ready live danmaku feature as an independent page with multi-platform abstraction (interface + Bilibili + Mock), including timed batch summarization and runtime injection compatibility.
> **Deliverables**:
> - Platform adapter contract + adapter registry (Bilibili + Mock)
> - Independent Danmaku screen with connect/control/status/feed
> - Timed batch summarization pipeline with configurable interval/batch size
> - Settings persistence for danmaku controls and summary behavior
> - Automated tests + agent-executed verification evidence
> **Effort**: Medium
> **Parallel**: YES - 3 waves
> **Critical Path**: Task 1 → Task 2 → Task 4 → Task 6 → Task 8 → Task 10

## Context
### Original Request
- 开发直播弹幕功能，参考 N-T-AI。
- 明确选择：
  - 首期做多平台抽象
  - 首期就做弹幕批处理总结
  - UI 采用独立页面
  - 测试策略采用 tests-after

### Interview Summary
- 现仓库已经具备 B 站弹幕底层接入和事件流能力，不应推翻重做。
- 首期采用“抽象优先 + 单真实平台落地”：统一接口、B站适配器、Mock适配器。
- 批处理总结能力必须首期上线，并可配置批次窗口参数。

### Metis Review (gaps addressed)
- Guardrail: 不在首期接第二真实平台，避免范围膨胀；通过 Mock 适配器验证抽象完整性。
- Guardrail: 批处理默认仅做“汇总与展示/注入”，不绑定强制自动回复行为，避免意外刷屏。
- Guardrail: 对高频弹幕引入上限（batch_size）与节流（interval）并记录丢弃策略。
- Guardrail: 凭据字段（SESSDATA/bili_jct/buvid3）只走本地设置存储，不写日志、不导出。

## Work Objectives
### Core Objective
在不破坏现有实时链路的前提下，交付可配置、可观测、可测试的直播弹幕能力：支持平台抽象、B站接入、批处理总结、独立页面运维控制。

### Deliverables
- Danmaku 平台抽象层（统一事件、连接状态、适配器生命周期）
- Bilibili 适配器（复用既有 `BilibiliDanmakuService`）
- Mock 适配器（稳定测试与演示）
- 批处理总结器（定时窗口、批次上限、摘要输出事件）
- 独立页面（配置/连接/实时流/批处理摘要）
- 设置项持久化（平台、roomId、批处理开关、interval、batchSize、注入开关）
- 自动化测试与验证证据

### Definition of Done (verifiable conditions with commands)
- `flutter analyze` 无新增 error。
- `flutter test` 通过，且新增 danmaku 相关测试覆盖 adapter/batcher/UI 关键路径。
- 在 Danmaku 页面可使用 Mock 适配器稳定产生日志与批处理摘要。
- 在 Bilibili 适配器配置有效房间后，可接收实时事件并在页面看到消息与批处理摘要。
- 当禁用“注入主对话”时，ChatEngine 不产生弹幕注入 cue；启用后恢复。

### Must Have
- 保持现有链路兼容：`RuntimeEventBus.emitDanmaku` 与 `ChatEngine._handleDanmakuEvent` 不中断。
- 首期抽象包含：Adapter Interface + Bilibili Adapter + Mock Adapter。
- 首期提供批处理总结参数：`enabled`, `intervalSeconds`, `batchSize`。
- 独立页面可直接执行连接/断开/清空/查看状态。

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- 不接入第二真实平台（抖音/YouTube 等）到首期实现。
- 不引入后端-rust 新 API 作为首期依赖。
- 不将弹幕凭据写入日志、导出文件或聊天记录正文。
- 不在首期实现复杂推荐/记忆归档自动化策略（仅保留挂点）。

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.
- Test decision: tests-after + Flutter test framework
- QA policy: 每个任务含 happy/failure 场景
- Evidence: `.opencode/openagent-labforge/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
Wave 1: Domain contracts + settings + batching foundation (Tasks 1-4)
Wave 2: UI/page + navigation + runtime integration (Tasks 5-8)
Wave 3: tests hardening + docs sync + final verification (Tasks 9-10)

### Dependency Matrix (full, all tasks)
- T1 blocks T2, T3, T4, T5
- T2 blocks T6
- T3 blocks T7
- T4 blocks T7, T8
- T5 blocks T6
- T6 + T7 block T8
- T8 blocks T9
- T9 blocks T10

### Agent Dispatch Summary (wave → task count → categories)
- Wave 1 → 4 tasks → quick / unspecified-low
- Wave 2 → 4 tasks → visual-engineering / unspecified-low
- Wave 3 → 2 tasks → unspecified-low / writing

## TODOs
> Implementation + Test = ONE task. Never separate.
> EVERY task includes Agent Profile + Parallelization + QA Scenarios.

- [ ] 1. Define danmaku adapter domain contract and lifecycle state model

  **What to do**: 新增平台抽象契约（adapter 接口、连接状态、标准事件包装、错误语义）。确保上层只依赖抽象，不直接依赖 Bilibili 服务细节。
  **Must NOT do**: 不改现有 `DanmakuEvent` 字段语义；不把 UI 逻辑塞入 domain 层。

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: 领域建模+边界定义
  - Skills: `[]` — 无特殊技能依赖
  - Omitted: `[]` — 无

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [2,3,4,5] | Blocked By: []

  **References**:
  - Pattern: `lib/core/models/danmaku_event.dart:1-35` — 当前标准事件结构
  - Pattern: `lib/core/services/event_bus.dart:216-234` — 统一发布入口
  - Pattern: `lib/core/services/runtime_hub.dart:12-33` — runtime 服务注册方式
  - External: `Studying/N-T-AI-main/backend/app/plugins/bilibili_live/__init__.py:168-221` — 批处理循环参考

  **Acceptance Criteria**:
  - [ ] 新增抽象接口后，Bilibili 适配器可实现该接口且不引入循环依赖
  - [ ] 抽象层包含连接状态/错误状态，供 UI 和批处理器统一消费

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: Bash
    Steps: flutter analyze
    Expected: no new type errors around adapter interface wiring
    Evidence: .opencode/openagent-labforge/evidence/task-1-adapter-contract.txt

  Scenario: [Failure/edge case]
    Tool: Bash
    Steps: flutter test test/runtime_event_bus_test.dart
    Expected: existing runtime bus contract still passes (no breakage)
    Evidence: .opencode/openagent-labforge/evidence/task-1-adapter-contract-error.txt
  ```

  **Commit**: YES | Message: `feat(danmaku): define adapter contract and lifecycle states` | Files: [lib/core/models/*, lib/core/services/*]

- [ ] 2. Implement adapter registry and Bilibili adapter wrapper

  **What to do**: 实现 adapter registry（按平台键选择适配器），并将既有 `BilibiliDanmakuService` 封装为 BilibiliAdapter（connect/disconnect/stream/status）。
  **Must NOT do**: 不复制粘贴 `BilibiliDanmakuService` 内部协议代码；仅封装复用。

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: 现有服务封装与依赖注入
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [6] | Blocked By: [1]

  **References**:
  - Pattern: `lib/core/services/bilibili_danmaku_service.dart:38-143` — connect 生命周期
  - Pattern: `lib/core/services/bilibili_danmaku_service.dart:260-278` — 自动重连策略
  - Pattern: `lib/core/services/runtime_hub.dart:20-33` — 服务持有模式

  **Acceptance Criteria**:
  - [ ] 通过 registry 可获取 BilibiliAdapter，并成功调用 connect/disconnect
  - [ ] Runtime 事件仍通过 `emitDanmaku` 发出，ChatEngine 订阅不受影响

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: Bash
    Steps: flutter analyze
    Expected: adapter wrapper and registry compile without nullable/lifecycle errors
    Evidence: .opencode/openagent-labforge/evidence/task-2-bili-adapter.txt

  Scenario: [Failure/edge case]
    Tool: Bash
    Steps: run app with invalid roomId config and trigger connect
    Expected: adapter returns failed status gracefully; app does not crash
    Evidence: .opencode/openagent-labforge/evidence/task-2-bili-adapter-error.txt
  ```

  **Commit**: YES | Message: `feat(danmaku): add bilibili adapter and registry wiring` | Files: [lib/core/services/*]

- [ ] 3. Implement Mock adapter for deterministic local replay

  **What to do**: 新增 MockAdapter，按固定节奏产出 danmaku/superChat/gift 事件，用于 UI 与批处理稳定测试。
  **Must NOT do**: 不依赖网络；不写入真实凭据字段。

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: 独立模拟器实现，低耦合
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [7] | Blocked By: [1]

  **References**:
  - Pattern: `lib/core/models/danmaku_event.dart:1-35` — 事件字段约束
  - Pattern: `lib/core/services/chat_engine.dart:1487-1535` — 事件类型优先级与文案预期

  **Acceptance Criteria**:
  - [ ] MockAdapter 支持 start/stop 且可重复启动
  - [ ] 每种事件类型至少产出 1 条，供页面与批处理验证

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: Bash
    Steps: flutter test <new mock adapter test file>
    Expected: deterministic event sequence assertions pass
    Evidence: .opencode/openagent-labforge/evidence/task-3-mock-adapter.txt

  Scenario: [Failure/edge case]
    Tool: Bash
    Steps: start/stop mock adapter repeatedly in test loop
    Expected: no timer leak / stream close exception
    Evidence: .opencode/openagent-labforge/evidence/task-3-mock-adapter-error.txt
  ```

  **Commit**: YES | Message: `feat(danmaku): add mock adapter for local replay` | Files: [lib/core/services/*, test/*]

- [ ] 4. Build timed batch summarizer pipeline with configurable limits

  **What to do**: 实现批处理聚合器：窗口收集（intervalSeconds）、上限截断（batchSize）、摘要输出（简洁中文概览），并支持可选注入给 ChatEngine。
  **Must NOT do**: 不默认触发自动回复发送；不把摘要当成用户消息写入历史。

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: 事件聚合与节流策略
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [7,8] | Blocked By: [1]

  **References**:
  - Pattern: `Studying/N-T-AI-main/backend/app/plugins/bilibili_live/__init__.py:168-221` — interval/batch 总结循环
  - Pattern: `lib/core/services/chat_engine.dart:1443-1464` — 运行时入队节流方式
  - Pattern: `lib/core/services/event_bus.dart:174-194` — runtime metric 发布模式

  **Acceptance Criteria**:
  - [ ] 在窗口期内收集事件并按 `batchSize` 截断输出
  - [ ] 摘要事件可被 UI 订阅显示，且开关关闭时不产出摘要
  - [ ] 默认仅显示/指标输出，不自动推送到聊天主输入链

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: Bash
    Steps: flutter test <new batcher test file>
    Expected: emits summary exactly at configured interval with expected item cap
    Evidence: .opencode/openagent-labforge/evidence/task-4-batch-summarizer.txt

  Scenario: [Failure/edge case]
    Tool: Bash
    Steps: feed empty window and oversized burst inputs
    Expected: empty window emits nothing; burst is capped and no crash
    Evidence: .opencode/openagent-labforge/evidence/task-4-batch-summarizer-error.txt
  ```

  **Commit**: YES | Message: `feat(danmaku): add timed batch summarization pipeline` | Files: [lib/core/services/*, lib/core/models/*, test/*]

- [ ] 5. Extend settings model/repository for danmaku controls

  **What to do**: 在 `AppSettings` 与 `SettingsRepository` 增加弹幕相关字段（platform, roomId, enabled, injectEnabled, batchEnabled, intervalSeconds, batchSize, credential slots）。完成 DB 映射与默认值回填。
  **Must NOT do**: 不破坏已有 settings 迁移路径；不在日志中打印敏感凭据。

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: 配置模型与持久化映射
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [6] | Blocked By: [1]

  **References**:
  - Pattern: `lib/core/models/app_settings.dart:25-141` — settings 字段风格
  - Pattern: `lib/core/models/app_settings.dart:143-260` — copyWith 与默认传播
  - Pattern: `lib/core/repositories/settings_repository.dart:434-529` — bool/double/int 映射实践

  **Acceptance Criteria**:
  - [ ] 新字段可被保存并在重启后加载
  - [ ] 旧数据（无新字段）可安全回退到默认值

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: Bash
    Steps: flutter test <new settings serialization test file>
    Expected: toJson/fromJson and DB row mapping preserve danmaku settings
    Evidence: .opencode/openagent-labforge/evidence/task-5-settings.txt

  Scenario: [Failure/edge case]
    Tool: Bash
    Steps: load legacy settings snapshot without danmaku keys
    Expected: defaults applied without exceptions
    Evidence: .opencode/openagent-labforge/evidence/task-5-settings-error.txt
  ```

  **Commit**: YES | Message: `feat(settings): persist danmaku controls and batch params` | Files: [lib/core/models/app_settings.dart, lib/core/repositories/settings_repository.dart]

- [ ] 6. Create independent Danmaku screen (connect/control/feed/summary)

  **What to do**: 新建独立页面展示：平台选择、房间配置、连接状态、连接/断开按钮、实时事件列表、批处理摘要列表、清空按钮、错误提示区。
  **Must NOT do**: 不把页面塞回 Chat 主布局右面板；不与深度研究页面混合。

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: 独立页面与交互状态管理
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [8] | Blocked By: [2,5]

  **References**:
  - Pattern: `lib/features/notes/notes_screen.dart` — 独立功能页模式
  - Pattern: `lib/features/memory/memory_tier_screen.dart` — 路由打开与局部编辑交互
  - Pattern: `lib/features/chat/chat_screen.dart:513-545` — 页面导航入口模式

  **Acceptance Criteria**:
  - [ ] 页面可在运行时切换 Mock/Bilibili 平台
  - [ ] 连接状态和错误提示实时更新
  - [ ] 可查看最近 N 条事件与最近 N 条摘要

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: interactive_bash
    Steps: run flutter app, open Danmaku screen, choose Mock, connect
    Expected: live feed and summary panels receive updates within configured interval
    Evidence: .opencode/openagent-labforge/evidence/task-6-danmaku-screen.txt

  Scenario: [Failure/edge case]
    Tool: interactive_bash
    Steps: choose Bilibili with invalid roomId then connect
    Expected: error banner shown; app remains responsive and reconnect button usable
    Evidence: .opencode/openagent-labforge/evidence/task-6-danmaku-screen-error.txt
  ```

  **Commit**: YES | Message: `feat(danmaku-ui): add independent danmaku management screen` | Files: [lib/features/danmaku/*]

- [ ] 7. Wire batch summary pipeline to screen and runtime metrics

  **What to do**: 将 Task 4 的批处理器输出接到 Danmaku 页面摘要区，并通过 runtime metric 记录窗口大小、丢弃数量、摘要长度等指标。
  **Must NOT do**: 不在该任务引入模型调用；摘要文本只做规则化压缩，不进 LLM。

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: 事件桥接 + 指标暴露
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [8] | Blocked By: [3,4]

  **References**:
  - Pattern: `lib/core/services/event_bus.dart:174-194` — runtime metric 命名与 attributes
  - Pattern: `test/runtime_event_bus_test.dart:98-130` — metric 验证风格

  **Acceptance Criteria**:
  - [ ] 每个摘要窗口都有对应 metric 事件
  - [ ] 事件流高峰时，丢弃计数可观测且 UI 不冻结

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: Bash
    Steps: flutter test <new summary-metric test file>
    Expected: metric envelopes emitted with expected fields per summary window
    Evidence: .opencode/openagent-labforge/evidence/task-7-summary-metrics.txt

  Scenario: [Failure/edge case]
    Tool: Bash
    Steps: simulate burst events beyond batchSize in tests
    Expected: droppedCount > 0 and still emits valid summary payload
    Evidence: .opencode/openagent-labforge/evidence/task-7-summary-metrics-error.txt
  ```

  **Commit**: YES | Message: `feat(danmaku): expose summary metrics and ui feed wiring` | Files: [lib/core/services/*, lib/features/danmaku/*, test/*]

- [ ] 8. Add navigation entry and ChatEngine injection toggle alignment

  **What to do**: 在现有入口（Chat 页 header 或 sidebar 菜单）新增“弹幕中心”导航；将“注入主对话”开关与 ChatEngine 注入逻辑对齐，确保开关即时生效。
  **Must NOT do**: 不更改 `_handleDanmakuEvent` 的既有优先级语义（SC>gift>danmaku）。

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: 导航与交互开关联动
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 2 | Blocks: [9] | Blocked By: [4,6,7]

  **References**:
  - Pattern: `lib/features/chat/chat_screen.dart:491-545` — 入口导航函数组织
  - Pattern: `lib/features/chat/widgets/chat_header.dart:111-129` — header action 按钮模式
  - Pattern: `lib/core/services/chat_engine.dart:1467-1506` — 注入开关判定与 route 约束

  **Acceptance Criteria**:
  - [ ] 用户可从主流程直接进入 Danmaku 页面
  - [ ] 注入开关关闭时，不再向对话生成 `ChatSourceKind.barrage` 消息
  - [ ] 开关重新开启后，注入恢复且节流行为稳定

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: interactive_bash
    Steps: open Danmaku page, toggle inject on, run mock stream
    Expected: chat receives barrage messages with existing formatting rules
    Evidence: .opencode/openagent-labforge/evidence/task-8-navigation-injection.txt

  Scenario: [Failure/edge case]
    Tool: interactive_bash
    Steps: toggle inject off during active stream
    Expected: new barrage cues stop immediately; no crash or pending-queue leak
    Evidence: .opencode/openagent-labforge/evidence/task-8-navigation-injection-error.txt
  ```

  **Commit**: YES | Message: `feat(chat): add danmaku center entry and injection toggle alignment` | Files: [lib/features/chat/*, lib/features/danmaku/*, lib/core/services/chat_engine.dart]

- [ ] 9. Add automated tests for adapters, batching, and UI state transitions

  **What to do**: 新增 tests-after 覆盖：adapter lifecycle、mock 事件稳定性、batch summarizer 规则、Danmaku 页面状态迁移（connecting/connected/error/disconnected）和注入开关行为。
  **Must NOT do**: 不引入脆弱的真实网络依赖测试；Bilibili 实网作为手工场景验证。

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: 测试补全与回归防护
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [10] | Blocked By: [8]

  **References**:
  - Pattern: `test/runtime_event_bus_test.dart:8-130` — runtime 事件断言模式
  - Pattern: `test/runtime_event_arbitrator_test.dart` — 队列/节流类服务测试风格
  - Pattern: `test/brain_router_test.dart` — 状态分支测试结构

  **Acceptance Criteria**:
  - [ ] 新增 danmaku 相关测试全部通过
  - [ ] 旧有测试集不回归

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: Bash
    Steps: flutter test
    Expected: all tests pass including new danmaku tests
    Evidence: .opencode/openagent-labforge/evidence/task-9-tests.txt

  Scenario: [Failure/edge case]
    Tool: Bash
    Steps: run flutter test with an intentionally malformed adapter fixture
    Expected: test catches contract violation deterministically
    Evidence: .opencode/openagent-labforge/evidence/task-9-tests-error.txt
  ```

  **Commit**: YES | Message: `test(danmaku): cover adapters batching and screen state transitions` | Files: [test/*]

- [ ] 10. Run full verification sweep and sync developer-facing docs

  **What to do**: 执行 `flutter analyze` + `flutter test` + 关键手工运行场景（Mock/Bilibili）并记录证据；同步 docs/README 中“弹幕中心与批处理参数”说明。
  **Must NOT do**: 不扩展新特性；仅做验证和文档对齐。

  **Recommended Agent Profile**:
  - Category: `writing` — Reason: 文档同步 + 验证结果归档
  - Skills: `[]`
  - Omitted: `[]`

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [] | Blocked By: [9]

  **References**:
  - Pattern: `README.md` — 功能说明条目与路线图风格
  - Pattern: `docs/left_brain_first_architecture.md` — 架构文档陈述方式
  - Pattern: `docs/MIGRATION_FROM_NTAI.md` — 迁移说明写作风格

  **Acceptance Criteria**:
  - [ ] `flutter analyze` 通过
  - [ ] `flutter test` 通过
  - [ ] README/docs 至少一处新增弹幕中心与批处理配置说明
  - [ ] 证据文件齐全并可追溯到每个任务

  **QA Scenarios**:
  ```
  Scenario: [Happy path]
    Tool: Bash + interactive_bash
    Steps: run analyze/test; run app with Mock and Bilibili manual flows
    Expected: command suite green; both platform modes behave as designed
    Evidence: .opencode/openagent-labforge/evidence/task-10-final-verification.txt

  Scenario: [Failure/edge case]
    Tool: interactive_bash
    Steps: interrupt/reconnect during active stream and during summary window
    Expected: state recovers cleanly; no duplicate timers or stuck connecting state
    Evidence: .opencode/openagent-labforge/evidence/task-10-final-verification-error.txt
  ```

  **Commit**: YES | Message: `docs(danmaku): document danmaku center controls and verification` | Files: [README.md, docs/*]

## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- Commit 1: `feat(danmaku): add adapter abstraction and batching pipeline`
- Commit 2: `feat(danmaku-ui): add independent page and runtime controls`
- Commit 3: `test(danmaku): add adapter/batcher/ui verification coverage`

## Success Criteria
- 用户可在独立页面完成弹幕连接管理并观察实时流与批处理摘要。
- 抽象层可在不改上层页面代码前提下切换 Mock/Bilibili 适配器。
- 弹幕注入行为可配置且可验证（开启/关闭均符合预期）。
- 自动化测试与命令行验证可重复通过。
