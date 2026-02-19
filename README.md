# CMYKE

CMYKE 是一个面向 **实时交流模型（Realtime/Voice-first）**、**多模态**、**可插拔智能体** 的跨平台架构原型。
当前仓库先落地 Flutter UI 与本地数据层；后续将把“工具/记忆/插件/编排”等能力逐步迁移到可部署的 Rust 后端，并保留
Python 作为可选扩展层（HTTP/MCP 等方式对接）。

> 设计取向（与传统“桌面陪伴/单端应用”不同）
> - **多平台交付优先**：Windows/macOS/Linux/Android/iOS 同一套 UI 与协议。
> - **企业化/工程化优先**：可部署、可观测、可审计、可配置，便于团队迭代与落地。
> - **Realtime 优先**：把低延迟语音/实时对话模型作为一等公民，而不是“普通聊天的附属模式”。

相关参考与演进脉络可在 `Studying/N-T-AI-main/` 中看到（历史项目与设计文档）；CMYKE 更强调跨平台与实时模式的工程化收敛。

## CMYKE 五大维度

- C — Cognitive：注意力、记忆、推理、决策、元认知。
- M — Multimodal：语音、视觉、表情、动作的融合与同步。
- Y — Yielding / Yottascale：高质量实时产出与大规模承载能力。
- K — Knowledge / Key：结构化/非结构化知识与关键工具入口。
- E — Evolving / Empathetic：持续学习与情感智能。

## 目录 / Table of Contents

- [核心能力 / Core Capabilities](#核心能力--core-capabilities)
- [项目结构 / Project Layout](#项目结构--project-layout)
- [快速开始 / Quickstart](#快速开始--quickstart)
- [Rust 后端（REST）/ Rust Backend (REST)](#rust-后端rest-rust-backend-rest)
- [模型与语音接入（当前）/ Providers](#模型与语音接入当前--providers)
- [路线图 / Roadmap](#路线图--roadmap)
- [第三方组件与许可 / Third-Party Attributions](#第三方组件与许可--third-party-attributions)
- [许可证 / License](#许可证--license)

## 核心能力 / Core Capabilities

- **Realtime/Voice-first**：以低延迟实时对话模型为核心路线（并为后续的控制代理/工具编排预留通道）。
- **多模态输入输出**：文本、语音（TTS/STT/流式音频）、图片（Vision Agent 回退）、以及表情/动作事件总线。
- **四级记忆系统**：会话摘要（L1）/ 核心记忆（L2）/ 日记记忆（L3）/ 知识库（L4），并支持导入/导出与编辑 UI。
- **小模型 Agent 拆分**：用更小的模型承担“记忆抽取/动作选择”等结构化决策，降低主模型负担。
- **本地存储与可迁移性**：SQLite 落地在 `Documents/cmyke/`，导出生成可阅读的 `.md`。
- **后端可部署（进行中）**：Rust REST 后端骨架已加入，用于逐步承载企业化能力（鉴权、审计、插件、工具执行等）。

## 项目结构 / Project Layout

- `lib/main.dart` / `lib/app.dart`：CMYKE 入口 UI 与视觉基调。
- `lib/features/chat/`：ChatGPT 风格聊天界面（多会话 + 记忆层级）。
- `lib/features/settings/`：模型能力配置与 Provider Catalog。
- `lib/features/memory/`：四级记忆编辑页面。
- `docs/ARCHITECTURE.md`：架构与记忆层级设计草案。
- `android/` `ios/` `macos/` `windows/` `linux/` `web/`：Flutter 平台工程。

## 快速开始 / Quickstart

```bash
flutter pub get
flutter run
```

## Rust 后端（REST）/ Rust Backend (REST)

仓库已包含最小 Rust REST 后端骨架：`backend-rust/`（先以健康检查与部署形态为主）。

```powershell
.\tools\run_backend.ps1
# 或
cd backend-rust
cargo run
```

健康检查：`GET http://127.0.0.1:4891/health`

> 说明：移动端“本地 sidecar 后端进程”会受系统限制；因此 CMYKE 的默认策略是 **后端可独立部署（REST/WS）**，Flutter 全平台统一走网络协议。

## 模型与语音接入（当前）/ Providers

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

## 路线图 / Roadmap

- 冻结实时事件协议（文本/音频/工具/渲染）。
- Rust 微内核作为实时总线，Flutter 负责交互与渲染。
- Python 作为可选插件/模型服务，通过 MCP 或统一协议注册。
- 记忆系统持续增强：向量检索 + 关键词召回 + 去重/合并/归档工具链。

## 第三方组件与许可 / Third-Party Attributions

为保证工程与合规信息可追溯，CMYKE 对第三方依赖做了编号化登记（含路径、用途、上游来源、许可证）：

- 运行时直接使用：three.js / @pixiv/three-vrm / @pixiv/three-vrm-animation / ES Module Shims / 字体资源 / VRMA 动作包 / OpenCode CLI。
- 学习与引用项目（设计参考）：`Studying/deep_research/openclaw`、`Studying/deep_research/openclaw-skills`、`Studying/deep_research/free-OKC` 等。

完整清单见：`docs/THIRD_PARTY_ATTRIBUTIONS.md`

## 许可证 / License

本仓库以 Apache-2.0 许可证开源，详见 `LICENSE`。
