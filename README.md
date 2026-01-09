# CMYKE

CMYKE 是一个面向实时、多模态、可插拔智能体的跨平台架构原型。当前仓库先落地
Flutter UI 入口，后续将与 Rust 实时内核与 Python 扩展服务对接。

## CMYKE 五大维度

- C — Cognitive：注意力、记忆、推理、决策、元认知。
- M — Multimodal：语音、视觉、表情、动作的融合与同步。
- Y — Yielding / Yottascale：高质量实时产出与大规模承载能力。
- K — Knowledge / Key：结构化/非结构化知识与关键工具入口。
- E — Evolving / Empathetic：持续学习与情感智能。

## 目录定位

 - `lib/main.dart` / `lib/app.dart`：CMYKE 入口 UI 与视觉基调。
- `lib/features/chat/`：ChatGPT 风格聊天界面（多会话 + 记忆层级）。
- `lib/features/settings/`：模型能力配置与 Provider Catalog。
- `lib/features/memory/`：四级记忆编辑页面。
- `docs/ARCHITECTURE.md`：架构与记忆层级设计草案。
- `android/` `ios/` `macos/` `windows/` `linux/` `web/`：Flutter 平台工程。

## 开发启动

```bash
flutter pub get
flutter run
```

## 模型与语音接入（当前）

- 在应用内点击右上角“调参”进入 **模型与能力配置**。
- 普通/Realtime/Omni 路由均基于 OpenAI-compatible `/v1/chat/completions`。
- Omni/Realtime 若返回音频分片（`delta.audio.data`），会在前端边收边播。
- TTS Provider 使用 OpenAI-compatible `/v1/audio/speech`（支持 SiliconFlow 等）。
- STT 目前仍使用本地语音识别（远程 STT 接入预留中）。

常用 Provider Base URL 参考：
- OpenAI: `https://api.openai.com/v1`
- SiliconFlow: `https://api.siliconflow.cn/v1`
- DashScope (Qwen Omni): `https://dashscope.aliyuncs.com/compatible-mode/v1`
- StepFun: `https://api.stepfun.com/v1`
- LM Studio: `http://localhost:1234/v1`
- Ollama (native): `http://localhost:11434` (协议选 Ollama Native)

## 后续规划

- 冻结实时事件协议（文本/音频/工具/渲染）。
- Rust 微内核作为实时总线，Flutter 负责交互与渲染。
- Python 作为可选插件/模型服务，通过 MCP 或统一协议注册。
- 记忆系统从 JSON 迁移到 SQLite + 向量库，支持 4 层级记忆调度。
