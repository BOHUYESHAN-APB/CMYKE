# Neko-Claw Agent Family Protocol (NC-AFP) v1.0
**状态**: 草案 (Draft)
**设计者**: 缪斯 (Muse) @缪斯
**日期**: 2026-02-15

---

## 📋 协议概述

NC-AFP 是专为 Neko-Claw 设计的高性能内部通信协议，旨在解决当前 OpenClaw 跨会话消息传递延迟高、解析重的问题。

### 核心特性
1. **二进制优先**: 使用 Rust 的内存对齐特性，减少序列化开销。
2. **异步非阻塞**: 基于 Tokio 频道 (mpsc/broadcast) 实现。
3. **零拷贝转发**: 内部组件间传递消息时尽量避免字符串克隆。
4. **强类型**: 使用 Rust 枚举定义所有消息类型，避免运行时类型错误。

---

## 🗂️ 消息结构 (Schema)

使用 **Serde** 进行序列化定义：

```rust
#[derive(Debug, Serialize, Deserialize)]
pub enum NcMessage {
    /// 文本指令
    Command {
        sender_id: String,
        target_agent: String,
        content: String,
        context_id: Option<String>,
    },
    /// 任务委派 (子 Agent 派生)
    Spawn {
        task_id: String,
        agent_id: String,
        payload: serde_json::Value,
    },
    /// 心跳与状态同步
    Heartbeat {
        agent_id: String,
        status: AgentStatus,
        load_pct: f32,
    },
    /// 内存同步请求
    MemorySync {
        key: String,
        operation: SyncOp,
    }
}

#[derive(Debug, Serialize, Deserialize)]
pub enum AgentStatus {
    Idle,
    Thinking,
    Executing,
    Error(String),
}
```

---

## 🏗️ 通信拓扑

### 1. 内部总线 (Internal Bus)
- **Local Bus**: 同一个二进制进程内的组件使用 Tokio 异步频道通信。
- **Shared Memory**: 核心状态（如 Identity, Memory Cache）在 Arc<Mutex<T>> 保护下实现多线程共享。

### 2. 外部网关 (Web Gateway)
- 使用 **Axum** 暴露高效的 JSON/MessagePack 端点。
- **Token 认证**: 所有内部通信均经过 Bearer Token 校验。

### 3. 网络请求 (Networking)
- 使用 **Reqwest** 的连接池 (Connection Pool) 技术，保持与 AI Providers 和 Webhooks 的长连接，减少握手延迟。

---

## ⚡ 性能预期

- **序列化延迟**: < 100ns (使用 Serde)
- **内部转发延迟**: < 1ms
- **内存占用**: 每个并发会话 < 1MB (Stack + Heap)

---

**归档完毕** 📚💜
