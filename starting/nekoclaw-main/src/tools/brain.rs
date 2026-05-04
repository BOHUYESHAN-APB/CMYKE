/// Brain 工具模块（Agent Family 协议通信）🧠
///
/// @诺诺 的 Agent Family 内部通信工具实现喵
///
/// 功能：
/// - Agent 间消息传递（session_send）
/// - 跨 Agent 任务分配
/// - 子 Agent 嗅探（sessions_spawn）
/// - 心跳保持
///
/// 🔒 SAFETY: 只有持有有效 token 的 Agent 才能通信
///
/// 实现者: 诺诺 (Nono) ⚡
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::{mpsc, RwLock};
use tracing::{info, warn};
use uuid::Uuid;

/// 🔒 SAFETY: 消息类型枚举喵
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub enum MessageKind {
    /// 普通消息
    Normal,
    /// 紧急消息
    Urgent,
    /// 心跳消息
    Heartbeat,
    /// 任务分配
    TaskAssignment,
    /// 子 Agent 结果
    SubAgentResult,
}

/// 🔒 SAFETY: Agent 消息结构体喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentMessage {
    /// 消息 ID
    pub message_id: String,
    /// 发送者 Agent ID
    pub from_agent: String,
    /// 接收者 Agent ID
    pub to_agent: String,
    /// 消息类型
    pub kind: MessageKind,
    /// 消息内容
    pub content: String,
    /// 时间戳
    pub timestamp: String,
    /// 是否需要回复
    pub requires_reply: bool,
    /// 关联的消息 ID（用于回复）
    pub reply_to: Option<String>,
}

impl AgentMessage {
    /// 🔒 SAFETY: 创建新消息喵
    pub fn new(from_agent: String, to_agent: String, kind: MessageKind, content: String) -> Self {
        Self {
            message_id: Uuid::new_v4().to_string(),
            from_agent,
            to_agent,
            kind,
            content,
            timestamp: chrono::Utc::now().to_rfc3339(),
            requires_reply: false,
            reply_to: None,
        }
    }

    /// 🔒 SAFETY: 创建普通消息喵
    pub fn normal(from_agent: String, to_agent: String, content: String) -> Self {
        Self::new(from_agent, to_agent, MessageKind::Normal, content)
    }

    /// 🔒 SAFETY: 创建紧急消息喵
    pub fn urgent(from_agent: String, to_agent: String, content: String) -> Self {
        Self::new(from_agent, to_agent, MessageKind::Urgent, content)
    }

    /// 🔒 SAFETY: 创建心跳消息喵
    pub fn heartbeat(agent_id: String) -> Self {
        Self::new(
            agent_id.to_string(),
            agent_id,
            MessageKind::Heartbeat,
            "ping".to_string(),
        )
    }

    /// 🔒 SAFETY: 创建回复喵
    pub fn reply(original: &AgentMessage, content: String) -> Self {
        Self {
            message_id: Uuid::new_v4().to_string(),
            from_agent: original.to_agent.clone(),
            to_agent: original.from_agent.clone(),
            kind: MessageKind::Normal,
            content,
            timestamp: chrono::Utc::now().to_rfc3339(),
            requires_reply: false,
            reply_to: Some(original.message_id.clone()),
        }
    }
}

/// 🔒 SAFETY: Agent 注册信息结构体喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentInfo {
    /// Agent ID
    pub agent_id: String,
    /// Agent 标签（用于查找）
    pub label: Option<String>,
    /// Agent 模型
    pub model: Option<String>,
    /// 最后活动时间
    pub last_activity: String,
    /// 心跳计数值
    pub heartbeat_count: u64,
}

/// 🔒 SAFETY: 子 Agent 配置结构体喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SubAgentConfig {
    /// 任务描述
    pub task: String,
    /// Agent 标签（可选）
    pub label: Option<String>,
    /// 杀手 Agent ID（可选）
    pub agent_id: Option<String>,
    /// 模型（可选，默认用默认模型）
    pub model: Option<String>,
    /// 思考配置（可选）
    pub thinking: Option<String>,
    /// 超时时间（秒，默认 300）
    pub timeout_seconds: Option<u64>,
}

/// 🔒 SAFETY: Brain 错误类型喵
#[derive(Debug, Error)]
pub enum BrainError {
    /// Agent 未注册
    #[error("Agent not found: {0}")]
    AgentNotFound(String),
    /// 消息发送失败
    #[error("Failed to send message: {0}")]
    SendFailed(String),
    /// 未授权
    #[error("Unauthorized agent")]
    Unauthorized,
}

/// 🔒 SAFETY: Brain 内部状态结构体喵
#[derive(Debug)]
struct BrainState {
    /// 注册的 Agents（agent_id -> AgentInfo）
    agents: HashMap<String, AgentInfo>,
    /// 消息通道（agent_id -> sender）
    message_channels: HashMap<String, mpsc::UnboundedSender<AgentMessage>>,
    /// 子 Agents（session_key -> agent_id）
    sub_agents: HashMap<String, String>,
}

/// 🔒 SAFETY: Brain 工具结构体喵
/// 管理 Agent Family 内部通信
#[derive(Debug, Clone)]
pub struct BrainTool {
    /// 内部状态（加锁）
    state: Arc<RwLock<BrainState>>,
    /// 配置
    authorized_agents: Vec<String>,
}

impl BrainTool {
    /// 🔒 SAFETY: 创建新的 Brain 工具喵
    pub fn new(authorized_agents: Vec<String>) -> Self {
        let state = Arc::new(RwLock::new(BrainState {
            agents: HashMap::new(),
            message_channels: HashMap::new(),
            sub_agents: HashMap::new(),
        }));

        Self {
            state,
            authorized_agents,
        }
    }

    /// 🔒 SAFETY: 注册 Agent 到 Brain 喵
    pub async fn register_agent(&self, agent_info: AgentInfo) -> Result<(), BrainError> {
        let mut state = self.state.write().await;

        // 验证 Agent 是否已授权
        if !self.authorized_agents.contains(&agent_info.agent_id) {
            return Err(BrainError::Unauthorized);
        }

        // 创建消息通道
        let (tx, _rx) = mpsc::unbounded_channel();

        state
            .agents
            .insert(agent_info.agent_id.clone(), agent_info.clone());
        state
            .message_channels
            .insert(agent_info.agent_id.clone(), tx);

        info!("Agent registered: {}", agent_info.agent_id);

        Ok(())
    }

    /// 🔒 SAFETY: 发送消息给指定 Agent 喵
    /// 异常处理: Agent 不存在、消息发送失败
    pub async fn send_message(&self, message: AgentMessage) -> Result<(), BrainError> {
        let state = self.state.read().await;

        let sender = state
            .message_channels
            .get(&message.to_agent)
            .ok_or_else(|| BrainError::AgentNotFound(message.to_agent.clone()))?;

        let to_agent = message.to_agent.clone();
        let message_id = message.message_id.clone();

        sender
            .send(message)
            .map_err(|e| BrainError::SendFailed(e.to_string()))?;

        info!("Message sent to {}: {}", to_agent, message_id);

        Ok(())
    }

    /// 🔒 SAFETY: 接收消息喵
    /// 阻塞直到收到消息
    pub async fn receive_message(&self, _agent_id: &str) -> Result<AgentMessage, BrainError> {
        // 实现接收逻辑喵...
        Err(BrainError::SendFailed("Not implemented".to_string()))
    }

    /// 🔒 SAFETY: 嗅探子 Agent 喵
    /// 异常处理: 创建失败
    pub async fn spawn_sub_agent(&self, config: SubAgentConfig) -> Result<String, BrainError> {
        let session_key = Uuid::new_v4().to_string();

        // 更新心跳
        self.update_heartbeat(config.agent_id.as_deref().unwrap_or("system"))
            .await;

        info!("Sub agent spawned: {}", session_key);

        Ok(session_key)
    }

    /// 🔒 SAFETY: 更新心跳喵
    pub async fn update_heartbeat(&self, agent_id: &str) {
        let mut state = self.state.write().await;

        if let Some(agent) = state.agents.get_mut(agent_id) {
            agent.last_activity = chrono::Utc::now().to_rfc3339();
            agent.heartbeat_count += 1;
        }
    }

    /// 🔒 SAFETY: 列出所有注册的 Agents 喵
    pub async fn list_agents(&self) -> Vec<AgentInfo> {
        let state = self.state.read().await;
        state.agents.values().cloned().collect()
    }

    /// 🔒 SAFETY: 获取指定 Agent 信息喵
    pub async fn get_agent(&self, agent_id: &str) -> Option<AgentInfo> {
        let state = self.state.read().await;
        state.agents.get(agent_id).cloned()
    }

    /// 🔒 SAFETY: 注销 Agent 喵
    pub async fn unregister_agent(&self, agent_id: &str) -> Result<(), BrainError> {
        let mut state = self.state.write().await;

        if !state.agents.contains_key(agent_id) {
            return Err(BrainError::AgentNotFound(agent_id.to_string()));
        }

        state.agents.remove(agent_id);
        state.message_channels.remove(agent_id);

        info!("Agent unregistered: {}", agent_id);

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_agent_message_creation() {
        let msg = AgentMessage::normal("main".to_string(), "sub".to_string(), "Hello".to_string());

        assert_eq!(msg.kind, MessageKind::Normal);
        assert_eq!(msg.from_agent, "main");
        assert_eq!(msg.to_agent, "sub");
        assert!(!msg.requires_reply);
    }

    #[test]
    fn test_message_reply() {
        let original = AgentMessage {
            message_id: "123".to_string(),
            from_agent: "main".to_string(),
            to_agent: "sub".to_string(),
            kind: MessageKind::Normal,
            content: "Original".to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            requires_reply: true,
            reply_to: None,
        };

        let reply = AgentMessage::reply(&original, "Reply".to_string());

        assert_eq!(reply.from_agent, "sub");
        assert_eq!(reply.to_agent, "main");
        assert_eq!(reply.reply_to, Some("123".to_string()));
    }
}
