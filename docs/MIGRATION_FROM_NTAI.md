# CMYKE <- N-T-AI Migration Checklist (Draft)

目标：只迁移“能复用、能长期维护、能提升实时交互体验”的能力；避免把 N-T-AI 的历史包袱整包搬进来。

本文是迁移明细表 + 取舍依据，后续每一项迁移都应该能在这里找到对应条目与状态。

## 约定

- **源项目**：`Studying/N-T-AI-main`
- **目标项目**：本仓库（CMYKE）
- **迁移形态**：
  - `Port`：直接迁移（代码/协议基本复用）
  - `Rebuild`：按同一需求重写（保留设计但不搬实现）
  - `Skip`：明确不迁移（或后置）
- **状态**：`todo` / `doing` / `done` / `defer`

## 明细表

| # | 能力 | 用户价值 | 源代码位置（示例） | 依赖/运行时 | 目标形态 | 状态 | 备注/边界 |
|---:|---|---|---|---|---|---|---|
| 1 | Bilibili 直播弹幕接入（采集） | 直播实时互动 | `backend/app/plugins/bilibili_live/**` | Python + `aiohttp` + `blivedm` | `Port`(短期) / `Rebuild`(中期Rust插件) | doing | 服务层已迁移（事件解析/心跳/签名），UI 与配置入口未接入 |
| 2 | 弹幕事件 WS 推流（给 UI 窗口） | 独立弹幕窗/叠加显示 | `backend/main.py` (`/api/v1/plugins/*/stream`) | 后端 WS | `Port` | todo | CMYKE 侧需要确定 WS 端点与鉴权策略 |
| 3 | 弹幕汇总 Agent（批处理/去噪/注入主脑） | 减轻主模型负担，避免被刷屏 | `backend/app/plugins/bilibili_live/__init__.py` | LLM 供给 | `Rebuild` | todo | 建议改为“低优先级队列 + 空闲触发 + 结构化摘要”，避免打断用户输入 |
| 4 | 弹幕 UI 窗口（HTML） | 观感与调试 | `backend/app/static/bilibili/bilibili_danmaku.html` | WebView/浏览器 | `Port` | todo | 在 CMYKE 里可以先当成外部窗口或 WebView2/Flutter WebView |
| 5 | 插件生命周期（启用/禁用/状态） | 功能可控、可回收 | `backend/main.py` (`/api/v1/plugins/{id}/activate|deactivate|status`) | 后端插件管理器 | `Rebuild` | todo | CMYKE 最终建议由 Rust backend 统一管；Flutter 只负责开关与配置 |
| 6 | 语音频道监听（虚拟声卡/回环采集 -> STT -> transcript） | Discord/KOOK 语音转文字注入 | `backend/app/api/routes/live2d_routes.py` (`voice_channel_transcript`) + 前端设置页 | OS 音频回环/虚拟声卡 + STT | `Rebuild` | done | Windows MVP 已完成：设备选择 + 监听 + 注入开关；可用“系统默认录音设备”或“应用内手动选择设备”两种方式接入系统 STT |
| 7 | 语音频道事件 UI 展示（中心气泡/标签） | 区分来源、减少干扰 | `flutter_application/lib/screens/firefly_screen.dart` + `message_bubble.dart` | Flutter UI | `Port`(概念) | todo | CMYKE 当前 UI 体系不同：只迁“消息 source/role 映射 + 样式原则” |
| 8 | Audio broadcast（口型同步） | Live2D/Live3D 同步 | `backend/app/api/routes/live2d_routes.py` (`/broadcast/audio`) | WS 广播 | `Rebuild` | todo | CMYKE 未来应把 audio/expression 统一为实时事件总线（Rust WS） |
| 9 | 事件优先级队列（USER/VOICE_CH/BARRAGE/PROACTIVE） | 防止弹幕/回环抢占 | `backend/app/services/priority_manager.py` | 后端任务队列 | `Rebuild` | todo | 迁移时把弹幕与语音频道都走同一优先级队列；不要直接调用 ChatService |
| 10 | 输入栏快捷键（Enter/Alt+Enter 发送） | 高频效率 | CMYKE: `lib/features/chat/widgets/chat_composer.dart` | Flutter | `Port` | done | 已实现：Enter/Alt+Enter/Ctrl+Enter/Meta+Enter 发送；Shift+Enter 换行 |
| 11 | 语音频道监听（Windows 虚拟声卡 + 系统 STT） | 语音频道内容转写并注入对话（像麦克风一样“说完一句就结束”） | CMYKE: `lib/core/services/chat_engine.dart` + `docs/VOICE_CHANNEL_WINDOWS.md` | Windows + speech_to_text | `Rebuild` | done | 设备选择与注入开关已补齐；注入使用 `source=voiceChannel` 元数据，并在 UI 显示来源标签 |
| 12 | “消息来源 source”字段贯通（mic / voice_channel / barrage / plugin） | 多源输入不混淆 | N-T-AI: README/Changelog（source 持久化） | UI + 存储 | `Rebuild` | doing | 已在 ChatMessage + DB 增加 source/priority 字段，语音频道与麦克风注入使用；弹幕/插件仍待接入 |
| 13 | 虚拟麦克风注入（把 TTS 注入语音软件输入） | 让 AI “在语音频道里说话” | N-T-AI: `flutter_application/.../general_tab.dart`（配置/测试提示） | Windows 音频路由 | `Defer` | defer | 这是“输出侧”，实现复杂度与系统差异大；建议等语音频道输入稳定后再做 |
| 14 | 回环/loopback 设备枚举与采集调试接口（可选） | 多虚拟驱动环境下排障 | `backend/app/api/routes/audio_routes.py` (`/devices`, `/loopback/*`) | Python + sounddevice | `Defer` | defer | 你明确接受手动配置，所以先不做；真要做排障再引入 sidecar 或 Rust |
| 15 | 表情推断与广播（expression_service + WS） | 更“活”的角色反馈 | `backend/app/services/expression_service.py` + `chat_service.py` | 后端表达总线 | `Rebuild` | defer | CMYKE 已有 Live3D motion agent；表情建议走统一 event bus，避免复制关键词表情规则 |

## 迁移方案（先设计，后实现）

核心原则：**先冻结“实时事件协议”与“队列/路由规则”**，再决定到底是 Python sidecar 复用还是 Rust 重写，否则会把旧项目的路由堆叠直接带进 CMYKE。

### 1) 统一实时事件总线（Realtime Event Bus）

把“弹幕 / 语音频道转写 / 工具结果 / 表情动作”都变成一类可订阅事件，统一走一个 WS（或 SSE）通道。

建议事件结构（草案）：

```jsonc
{
  "type": "barrage|voice_transcript|tool_result|expression|system",
  "ts": "2026-02-15T15:30:22Z",
  "source": { "kind": "bilibili|discord|loopback|user|agent", "id": "..." },
  "priority": "USER|VOICE_CH|BARRAGE|PROACTIVE|LOW",
  "payload": { "text": "...", "meta": {} }
}
```

配套规则：

- **优先级队列**：`USER` 永远不被弹幕抢占；`VOICE_CH` 不直接打断当前输入；`BARRAGE` 默认只展示，汇总再注入。
- **注入策略**：弹幕与语音频道转写默认只进“旁路上下文”（side context），由汇总器在空闲窗口合并后再写入主上下文。

### 2) Bilibili 弹幕迁移分两期

- **一期（最快可用）**：保留 N-T-AI 的 bilibili 采集实现作为 Python sidecar，CMYKE 只订阅标准化后的 `barrage` 事件。
  - 风险隔离：采集失败不影响主聊天；sidecar 可单独重启。
  - 需要做：鉴权（token）、房间号/礼物/舰长等事件的字段规范、断线重连策略。
- **二期（可维护）**：在 `backend-rust/` 里重写为 Rust 插件（同一协议输出），把 sidecar 替换掉。

### 3) 语音频道（macOS/Windows）建议走“双实现”

目标：把语音频道输入也变成 `voice_transcript` 事件，并带 `source`，不要直接当成用户输入。

- **方案 A（推荐优先）Discord Bot 音频接入**：用 bot 加入指定语音频道拿到 PCM，再做 STT。
  - 优点：跨平台一致；不依赖系统回环/虚拟声卡；对“语音频道”语义最贴合。
  - 代价：需要用户提供 bot token 与 guild/channel 配置。
- **方案 B（兜底）系统回环（Loopback）**：通过选择输入设备获取“系统播放音频”并做 STT（N-T-AI 类似）。
  - Windows: WASAPI loopback（实现成本相对低）。
  - macOS: 依赖虚拟声卡（如 BlackHole/Loopback），需要明确用户安装与选择流程。

### 4) UI 侧改动边界（避免把旧 UI 搬进来）

- 弹幕显示：先做“侧边栏/独立面板”，不进入主消息流；后续可加“弹幕叠加层”（overlay）。
- 语音频道：以 `source=discord/loopback` 的标签气泡展示，默认折叠；可一键“注入为主对话上下文”。

## 值得借鉴但不直接迁移（来自学习项目）

- `Studying/airi-main`：前端 VAD（AudioWorklet + Worker）与“流式会话保活/降级”思路，适合 CMYKE 的 Realtime 语音链路。
- `Studying/N.E.K.O-main`：能力开关（mcp/computer_use/user_plugin）+ readiness check 的模式，适合 CMYKE 未来做“实时模式/工具模式”的灰度开关。
- `Studying/ai_virtual_mate_web-main`：离线 ASR（sherpa-onnx sense-voice）+ 声纹门控（只响应特定人声）的交互策略，适合做“语音输入的误触防护”。

## 明确不迁移（当前）

| 能力 | 原因 |
|---|---|
| N-T-AI 的整套 Flutter UI/页面结构 | CMYKE 已有独立 UI 架构，直接搬会产生长期维护成本 |
| N-T-AI 的“后端单体大杂烩”式路由堆叠 | CMYKE 目标是 Rust core + 可插拔扩展，需先冻结协议再迁移实现 |

## 下一步（需要你确认的 3 个选择）

1. **Bilibili 弹幕：先做“只显示”还是“显示 + 汇总注入主脑”**？
2. **语音频道：优先 Windows 还是 macOS**？（macOS 需要虚拟声卡方案，开发与用户使用方式都不同）
3. **后端承载：先用 Python sidecar 复用 N-T-AI，还是直接上 Rust 插件协议**？
