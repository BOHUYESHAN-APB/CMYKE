# 学习项目可迁移点（候选清单）

目标：只迁移“可长期维护的设计/模块”，避免把学习项目整包搬进来。

## `Studying/airi-main`（moeru-ai/airi）

| 候选 | 价值 | 建议落地到 CMYKE | 参考位置（示例） | 形态 |
|---|---|---|---|---|
| 前端 VAD 管线（AudioWorklet + Worker） | 低延迟、抗抖动地做说话检测，适合实时语音对话与打断 | 用在 CMYKE 的“Realtime 语音输入”链路：VAD 只负责分段与事件，不承担 STT | `Studying/airi-main/apps/stage-web/src/workers/vad/process.worklet.ts`、`Studying/airi-main/apps/stage-web/src/workers/vad/vad.ts` | Rebuild（按同思路重写） |
| 流式会话保活与降级策略 | 实时 WS/流式易断，需要 idle teardown、自动重连、fallback | CMYKE 的 Realtime 网关：统一重连策略与“降级到本地 STT/TTS” | `Studying/airi-main/apps/stage-web/src/pages/index.vue`（VAD 启停、保活注释） | Rebuild |
| VRM 表情/动作调度思路（眨眼、注视漂移、idle） | 让角色“更活”，减少静态站桩感 | CMYKE `assets/live3d/viewer.html` 已在吸收部分思路，后续可拆成可配置模块 | AIRI 文档与 stage-ui 相关目录（以实现为准） | Rebuild |
| WebSocket Inspector / Devtools 思路 | 调试实时交互链路很关键 | 给 CMYKE 增加“事件总线监视器”（voice/danmaku/tool/expression） | `Studying/airi-main/apps/stage-web/src/pages/settings/system/developer.vue`（入口线索） | Rebuild |

## `Studying/N.E.K.O-main`（wehos/N.E.K.O）

| 候选 | 价值 | 建议落地到 CMYKE | 参考位置（示例） | 形态 |
|---|---|---|---|---|
| 能力开关 + readiness check（mcp/computer_use/user_plugin） | 让复杂能力可灰度启用，避免“开了就炸” | CMYKE 的 ModeRouter/ToolRouter：把工具链/实时链路都做成可检测、可降级的 capability | `Studying/N.E.K.O-main/agent_server.py`（`agent_flags`、启用检查） | Rebuild |
| 任务执行管线从多进程简化为协程直跑的取舍 | 降低复杂度与 IPC 成本 | CMYKE 的工具执行器：优先在单进程异步里做隔离（超时/取消/并发限制） | `Studying/N.E.K.O-main/agent_server.py`（注释对比旧新架构） | Rebuild |

## `Studying/ai_virtual_mate_web-main`（swordswind/ai_virtual_mate_web）

| 候选 | 价值 | 建议落地到 CMYKE | 参考位置（示例） | 形态 |
|---|---|---|---|---|
| 离线 ASR（sherpa-onnx SenseVoice） | 本地可跑、延迟可控，不依赖云 | 作为 CMYKE “本地 STT 后端”候选（与 Rust 后端或 Flutter 插件集成） | `Studying/ai_virtual_mate_web-main/asr.py` | Rebuild |
| 声纹门控（只响应特定人声） | 大幅降低误触发，适合直播/嘈杂环境 | CMYKE 语音输入的“安全阀”：speaker verify 通过才把转写注入 | `Studying/ai_virtual_mate_web-main/asr.py`（speaker embedding） | Rebuild |
| 多渲染后端（Live2D/MMD/VRM）“统一入口”思路 | 降低 UI 与渲染耦合 | CMYKE 的 Avatar Stage：统一动作/表情事件输入，不关心渲染实现 | `Studying/ai_virtual_mate_web-main/main.py` 等（以结构参考为主） | Rebuild |
