# Third-Party Attributions

本文件用于记录 CMYKE 当前实际使用或明确引用的第三方项目、资源与许可信息。

更新时间：2026-02-19

## 1) 运行时使用（产品功能直接依赖）

| ID | 组件 | 用途 | 本地路径/集成点 | 上游来源 | 许可证 |
|---|---|---|---|---|---|
| TP-RUN-001 | three.js + addons (OrbitControls/GLTFLoader/BufferGeometryUtils) | Live3D Web 渲染与加载 | `assets/live3d/vendor/three.module.js`、`assets/live3d/vendor/OrbitControls.js`、`assets/live3d/vendor/GLTFLoader.js`、`assets/live3d/vendor/utils/BufferGeometryUtils.js`；运行入口 `assets/live3d/viewer.html`；拷贝逻辑 `lib/features/common/live3d_preview.dart` | https://github.com/mrdoob/three.js | MIT |
| TP-RUN-002 | @pixiv/three-vrm | VRM 模型加载与运行时处理 | `assets/live3d/vendor/three-vrm.module.js`；`assets/live3d/viewer.html` | https://github.com/pixiv/three-vrm | MIT |
| TP-RUN-003 | @pixiv/three-vrm-animation | VRMA 动画处理 | `assets/live3d/vendor/three-vrm-animation.module.js`；`assets/live3d/viewer.html` | https://github.com/pixiv/three-vrm | MIT |
| TP-RUN-004 | ES Module Shims | 浏览器模块兼容层 | `assets/live3d/vendor/es-module-shims.js`；`lib/features/common/live3d_preview.dart` | https://github.com/guybedford/es-module-shims | MIT |
| TP-RUN-005 | MiSans 字体 | UI 字体 | `assets/fonts/misans/*`；声明见 `pubspec.yaml` | https://hyperos.mi.com/font/download | MiSans 字体许可协议（非 MIT） |
| TP-RUN-006 | HarmonyOS Sans SC 字体 | UI 字体 | `assets/fonts/harmonyos_sans/*`；声明见 `pubspec.yaml` | 华为 HarmonyOS Sans 发布渠道 | HarmonyOS Sans Fonts License（非 MIT） |
| TP-RUN-007 | VRoid VRMA Motion Pack | 预置动作动画 | `assets/live3d/animations/vroid_vrma_motion_pack/*` | pixiv VRoid Project | 见包内条款（非 MIT，要求标注动画署名） |
| TP-RUN-008 | OpenCode CLI (`opencode-ai`) | 深度研究工具执行/网关委派 | Rust 网关调用点：`backend-rust/src/main.rs`（`/api/v1/opencode/run`） | npm `opencode-ai` | MIT（`npm view opencode-ai license`） |

备注：
- `TP-RUN-007` 的署名要求：`Animation credits to pixiv Inc.'s VRoid Project`（或日文原文）。
- Flutter/pub 生态依赖（如 `http`、`sqflite`、`speech_to_text` 等）由 `pubspec.yaml` 管理，许可证可在应用内 License 页面查看。

## 2) 学习与引用项目（设计参考，不默认随产品发布）

这些目录主要用于方案研究、协议对齐与迁移分析。默认不作为 CMYKE 发布包的直接运行时依赖。

| ID | 项目 | 本地路径 | 用途边界 | 上游来源 | 许可证 |
|---|---|---|---|---|---|
| TP-REF-001 | free-OKC | `Studying/deep_research/free-OKC` | 研究工具契约、VM 沙箱与工具注册机制 | https://github.com/kexinoh/free-OKC | MIT |
| TP-REF-002 | openclaw | `Studying/deep_research/openclaw` | 研究网关守护进程、onboarding、通道接入设计 | https://github.com/openclaw/openclaw | MIT |
| TP-REF-003 | openclaw-skills | `Studying/deep_research/openclaw-skills` | 研究 SKILL 工件结构与技能仓库组织 | https://clawdhub.com（skills backup） | MIT |
| TP-REF-004 | nanobot-cn | `Studying/deep_research/nanobot-cn` | 研究代理流程与工程组织 | https://github.com/HKUDS/nanobot | MIT |
| TP-REF-005 | coze-studio | `Studying/deep_research/coze-studio` | 研究多资源编排与平台化 UI 组织 | https://github.com/coze-dev/coze-studio | Apache-2.0（见 `Studying/deep_research/coze-studio/LICENSE-APACHE`） |
| TP-REF-006 | zeroclaw | `Studying/deep_research/zeroclaw` | 研究代理系统提示词、工具循环与工程组织 | https://github.com/zeroclaw-labs/zeroclaw | MIT |
| TP-REF-007 | OpenManus | `Studying/universal-agent/openmanus/OpenManus-main` | Manus-like sandbox/flow、工具与技能工作流参考 | https://github.com/FoundationAgents/OpenManus | MIT |
| TP-REF-008 | OpenCowork | `Studying/universal-agent/opencowork/opencowork-main` | 深度研究工作流与协作式编排参考 | （上游链接待确认；README 示例为占位 `yourusername/opencowork`） | MIT |
| TP-REF-009 | DeepResearchAgent | `Studying/universal-agent/deepresearchagent/DeepResearchAgent-main` | 研究代理流程、browser/terminal/file 工具集参考 | https://github.com/SkyworkAI/DeepResearchAgent | Public Domain / The Unlicense（见上游 LICENSE） |
| TP-REF-010 | Skywork Super Agents | `Studying/universal-agent/skywork-super-agents/Skywork-Super-Agents-main` | 多智能体分工与任务编排参考 | https://github.com/Skywork-ai/Skywork-Super-Agents | MIT |
| TP-REF-011 | Ultimate Agent Skills Collection | （不克隆入仓库） | skills 仓库集合索引，用于挑选并导入可用 skills | https://github.com/ZhanlinCui/Ultimate-Agent-Skills-Collection | （以其仓库 LICENSE 为准，待确认） |

## 3) 维护规则

- 新增第三方代码/资源后，必须在本文件追加一条 `TP-*` 记录。
- 记录至少包含：用途、路径、来源、许可证。
- 若许可证待确认，必须明确标注“待确认”，在发布前补齐。
