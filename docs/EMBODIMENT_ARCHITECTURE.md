# 具身/外部控制架构（Draft）

目标：在 **Realtime/Omni 实时交流模式**下，让 CMYKE 可选地接入“具身控制”（例如 VRChat 角色控制、机器人控制），并且做到可审计、可中断、可扩展。

硬边界：
- **标准模式（Standard Chat）不接入具身控制**，避免把“聊天工具链”和“外部执行器”混在一起。
- 具身控制链路必须是 **JSON-first**：内部组件之间只用结构化协议通信，不靠自然语言互相转述。

本文件是长期设计草案，先冻结“边界 + 协议 + 里程碑”，实现可后续分阶段推进。

## 1) 角色分工（谁是老子 / 谁是手脚）

在实时交流模式下，把系统拆成 6 类职责，避免互相越权：

1. Boss（主脑：Realtime/Omni）
- 负责：对话、低延迟意图、把用户目标转成结构化约束
- 不负责：重工具链、多轮检索、长文档、直接操纵外部世界

2. Manager（参谋/调度：Standard 大模型）
- 负责：检索/归纳/规划/安全检查/状态压缩，减轻 Boss 的上下文压力
- 输出：`WorldState` 摘要、`ControlPlan`、`SafetyDecision`

3. Spine（具身控制器：VLA 模型，可插拔）
- 负责：把“观测 + 目标 + 当前状态”映射成短周期动作 `ActionFrame`（例如 5-10Hz）
- 不负责：工具检索、长文本写作

4. Eyes（观测：Perception）
- 负责：窗口捕获/帧采样/OCR/可选视觉特征提取，形成紧凑 `Observation`

5. Arms/Hands（执行器：Adapters/Actuators）
- 负责：把 `ActionFrame` 变成具体外部动作（VRChat OSC、键鼠注入、UIA 等）
- 不负责：理解与决策

6. Gate（安全闸门：Policy Engine）
- 负责：动作白名单、速率限制、轴回零/按钮抬起、急停、权限提示
- 任何外部动作必须先过 Gate 再执行

## 2) 模式路由（硬路由，避免串台）

标准模式（Standard）：
- 允许：工具/检索/写作/深度研究
- 禁止：任何外部执行器（VRChat/键鼠/UIA/机器人动作），禁止 VLA

实时模式（Realtime/Omni）：
- 默认：只对话（Boss）
- 仅当用户显式开启“外部控制/具身模式”并选择目标适配器时：
  - Boss -> Manager：请求压缩状态/安全检查/计划
  - Boss -> Spine：请求基于观测输出动作
  - Spine -> Gate -> Arms：执行动作

## 3) JSON-first 协议（v0）

### 3.1 通用信封（Envelope）

所有内部消息建议统一为：

```json
{
  "v": 0,
  "type": "observation|control_request|action_frame|safety_decision|log_event",
  "trace_id": "emb_1700000000000_0",
  "session_id": "chat_session_id",
  "ts_ms": 1700000000000,
  "payload": {}
}
```

约定：
- `trace_id` 全链路贯通（观测 -> 决策 -> 执行 -> 回放）
- `payload` 严格按 schema（后续可用 JSON Schema 冻结）

### 3.2 Observation（观测）

```json
{
  "frame": {
    "source": "window_capture",
    "w": 1920,
    "h": 1080,
    "sha256": "..."
  },
  "ocr": [
    {"text": "xxx", "x": 10, "y": 20, "w": 300, "h": 40}
  ],
  "ui_state": {
    "active_window": "VRChat",
    "scene_hint": "menu|world|loading|unknown"
  }
}
```

说明：
- 不把整张图塞进模型上下文；用 `sha256` + 受控的“视觉摘要”做注入
- 需要时由 Manager/Perception 走专门的视觉能力生成摘要（预算可控）

### 3.3 ControlRequest（Boss -> Manager/Spine）

```json
{
  "goal": "让 VRChat 角色走到门口",
  "constraints": {
    "max_duration_ms": 30000,
    "max_actions_per_sec": 10,
    "safety_level": "strict"
  },
  "target": {
    "adapter": "vrchat_osc",
    "world_id": "",
    "avatar_id": ""
  }
}
```

### 3.4 ActionFrame（Spine -> Gate -> Arms）

```json
{
  "seq": 12,
  "dt_ms": 100,
  "move": {"x": 0.0, "y": 0.6},
  "buttons": {"jump": false, "use": false},
  "avatar_params": {
    "GestureLeft": 1,
    "GestureRight": 0
  },
  "reason": "target visible, approach"
}
```

执行器必须保证：
- 轴有“回零策略”
- 按钮有“抬起策略”
- 超时/取消立即停机

### 3.5 SafetyDecision（Gate 输出）

```json
{
  "allow": true,
  "reject_reason": "",
  "applied_limits": {
    "max_actions_per_sec": 10,
    "max_axis_abs": 0.8
  }
}
```

## 4) 审计与回放（必须）

建议每个会话把具身链路落地为 JSONL：
- `Documents/cmyke/workspace/<session_id>/logs/embodiment_observations.jsonl`
- `Documents/cmyke/workspace/<session_id>/logs/embodiment_actions.jsonl`
- `Documents/cmyke/workspace/<session_id>/logs/embodiment_safety.jsonl`

每行一条 Envelope，便于：
- 复现“为什么动了”
- Debug（卡住/抽搐/误触发）
- 未来做离线训练数据（可选）

## 5) VRChat 适配器（规划）

目标：把 `ActionFrame` 映射为 VRChat OSC 输入与头像参数（只做执行，不做推理）。

适配器建议能力：
- `/input/*` 轴与按钮（移动、跳跃等）
- `/avatar/parameters/*` 参数（表情/手势/开关）

实现上要严格做：
- 速率限制
- 抖动滤波（避免摇杆噪声）
- 急停（hotkey + UI 按钮）

## 6) 算力与部署（前置现实）

VLA/具身模型推理通常需要独立算力设备。建议把 Spine 设计成“远端服务/本地插件”二选一：
- 本地：NVIDIA GPU（桌面或边缘设备）
- 远端：同局域网推理服务器

你提到的目标设备（示例）：
- Jetson Thor（边缘推理）
- DGX Spark（小型推理主机）

备注：在没有硬件的阶段，也可以先用“Mock Spine”（规则/脚本）打通 Eyes/Gate/Arms 的工程链路。

## 7) 里程碑（建议）

E0（无 AI）：VRChat OSC 执行器 + 手工控制面板 + 日志
- 验收：能稳定走路/停下/回零，不抖、不粘键，可急停

E1（有观测）：窗口捕获 + OCR/视觉摘要 + Safety Gate
- 验收：观测与动作都可回放，安全策略可配置

E2（接入 AI）：Boss/Manager 输出 JSON 计划 + Spine 输出 ActionFrame
- 验收：可中断、可降级（AI 失败回到手动/停机）

