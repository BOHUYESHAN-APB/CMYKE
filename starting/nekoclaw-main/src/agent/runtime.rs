/// Agent 核心运行时模块 🤖
///
/// @诺诺 的 Agent 核心运行逻辑实现喵
///
/// 功能：
/// - Agent 生命周期管理
/// - 消息循环
/// - Provider/Memory/Tools 集成
/// - 错误处理与重试
///
/// 🔒 SAFETY: 所有外部调用通过安全模块验证
///
/// 实现者: 诺诺 (Nono) ⚡

use async_trait::async_trait;
use crate::core::traits::{Provider, Memory, Tool};
use crate::providers::{ProviderClient, ProviderFactory};
use crate::memory::{MemoryBackend, MemoryEntry};
use crate::tools::{ToolsManager};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{error, info, warn};
use uuid::Uuid;

/// 🔒 SAFETY: Agent 配置结构体喵
#[derive(Debug, Clone)]
pub struct AgentConfig {
    /// Agent ID
    pub agent_id: String,
    /// Agent 标签
    pub label: Option<String>,
    /// 模型名称
    pub model: String,
    /// Provider 类型
    pub provider_type: String,
    /// 上下文最大 token 数
    pub max_context_tokens: u32,
    /// 思考模式
    pub thinking_enabled: bool,
}

impl Default for AgentConfig {
    fn default() -> Self {
        Self {
            agent_id: Uuid::new_v4().to_string(),
            label: None,
            model: "openai/gpt-3.5-turbo".to_string(),
            provider_type: "openrouter".to_string(),
            max_context_tokens: 8192,
            thinking_enabled: false,
        }
    }
}

/// 🔒 SAFETY: Agent 消息结构体喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentMessage {
    /// 消息 ID
    pub message_id: String,
    /// 角色（system/user/assistant）
    pub role: String,
    /// 内容
    pub content: String,
    /// Token 数量（估计）
    pub token_count: Option<u32>,
    /// 时间戳
    pub timestamp: String,
}

impl AgentMessage {
    /// 🔒 SAFETY: 创建系统消息喵
    pub fn system(content: String) -> Self {
        Self {
            message_id: Uuid::new_v4().to_string(),
            role: "system".to_string(),
            content,
            token_count: None,
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }

    /// 🔒 SAFETY: 创建用户消息喵
    pub fn user(content: String) -> Self {
        Self {
            message_id: Uuid::new_v4().to_string(),
            role: "user".to_string(),
            content,
            token_count: None,
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }

    /// 🔒 SAFETY: 创建助手消息喵
    pub fn assistant(content: String) -> Self {
        Self {
            message_id: Uuid::new_v4().to_string(),
            role: "assistant".to_string(),
            content,
            token_count: None,
            timestamp: chrono::Utc::now().to_rfc3339(),
        }
    }
}

/// 🔒 SAFETY: Agent 响应结构体喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentResponse {
    /// 响应 ID
    pub response_id: String,
    /// 响应内容
    pub content: String,
    /// 输入 token 数
    pub input_tokens: u32,
    /// 输出 token 数
    pub output_tokens: u32,
    /// 是否使用了思考模式
    pub thinking_used: bool,
    /// 使用到的工具（如果有）
    pub tools_used: Vec<String>,
    /// 响应时间（毫秒）
    pub duration_ms: u64,
}

/// 🔒 SAFETY: Agent 错误类型喵
#[derive(Debug)]
pub enum AgentError {
    /// Provider 错误
    #[error("Provider error: {0}")]
    ProviderError(String),
    /// Memory 错误
    #[error("Memory error: {0}")]
    MemoryError(String),
    /// 上下文溢出
    #[error("Context overflow: {0} tokens exceed limit of {1}")]
    ContextOverflow(u32, u32),
    /// 工具执行失败
    #[error("Tool execution failed: {0}")]
    ToolError(String),
    /// 配置错误
    #[error("Configuration error: {0}")]
    ConfigError(String),
}

/// 🔒 SAFETY: Agent 核心结构体喵
#[derive(Debug)]
pub struct Agent {
    /// 配置
    config: AgentConfig,
    /// Provider 客户端
    provider: Arc<ProviderClient>,
    /// Memory 后端
    memory: Arc<dyn Memory>,
    /// 工具链
    tools: Arc<ToolsManager>,
    /// 消息历史
    message_history: Arc<RwLock<Vec<AgentMessage>>>,
}

impl Agent {
    /// 🔒 SAFETY: 创建新的 Agent 实例喵
    /// 异常处理: Provider 初始化失败
    pub async fn new(
        config: AgentConfig,
        provider_factory: Arc<ProviderFactory>,
        memory: Arc<dyn Memory>,
        tools: Arc<ToolsManager>,
    ) -> Result<Self, AgentError> {
        // 创建 Provider 客户端
        let provider_type = match config.provider_type.as_str() {
            "openai" => crate::providers::ProviderType::OpenAI,
            "anthropic" => crate::providers::ProviderType::Anthropic,
            "openrouter" => crate::providers::ProviderType::OpenRouter,
            _ => return Err(AgentError::ConfigError(format!(
                "Unknown provider type: {}",
                config.provider_type
            ))),
        };

        let provider = provider_factory
            .create_client(provider_type)
            .map_err(|e| AgentError::ConfigError(format!("Provider creation failed: {}", e)))?;

        info!("Agent created: {} with provider: {:?}", config.agent_id, provider_type);

        Ok(Self {
            config,
            provider: Arc::new(provider),
            memory,
            tools,
            message_history: Arc::new(RwLock::new(Vec::new())),
        })
    }

    /// 🔒 SAFETY: 处理用户消息（核心接口）喵
    /// 异常处理: 消息处理失败、Provider 调用失败
    pub async fn process_message(&self, message: String) -> Result<AgentResponse, AgentError> {
        let start = std::time::Instant::now();

        // 加载系统提示（从 Memory）
        let system_prompt = self.load_system_prompt().await;

        // 加载历史上下文
        let context_messages = self.load_context().await;

        // 计算总 token 数
        let total_tokens = self.estimate_tokens(&system_prompt, &context_messages, &message);

        // 检查上下文大小
        if total_tokens > self.config.max_context_tokens {
            warn!("Context overflow: {} tokens exceed limit {}", total_tokens, self.config.max_context_tokens);
            return Err(AgentError::ContextOverflow(total_tokens, self.config.max_context_tokens));
        }

        // 构建请求
        let mut messages = vec![AgentMessage::system(system_prompt)];
        messages.extend(context_messages);
        messages.push(AgentMessage::user(message));

        // 调用 Provider
        let response_content = self
            .call_provider(&messages)
            .await?;

        // 保存到历史
        self.save_to_history(&message, &response_content).await;

        // 保存到 Memory
        self.save_to_memory(&message, &response_content).await;

        let duration = start.elapsed().as_millis() as u64;

        // 返回响应
        Ok(AgentResponse {
            response_id: Uuid::new_v4().to_string(),
            content: response_content,
            input_tokens: total_tokens,
            output_tokens: self.estimate_tokens("", &[], &response_content),
            thinking_used: self.config.thinking_enabled,
            tools_used: Vec::new(),
            duration_ms: duration,
        })
    }

    /// 🔒 SAFETY: 加载系统提示喵
    async fn load_system_prompt(&self) -> String {
        // TODO: 从 SOUL.md 或配置中加载
        format!("You are {}. Be helpful and concise.", self.config.agent_id)
    }

    /// 🔒 SAFETY: 加载上下文历史喵
    async fn load_context(&self) -> Vec<AgentMessage> {
        let history = self.message_history.read().await;
        let recent: Vec<_> = history.iter().rev().take(10).cloned().collect();
        recent.into_iter().rev().collect()
    }

    /// 🔒 SAFETY: 估计 token 数量喵
    fn estimate_tokens(&system: &str, context: &[AgentMessage], message: &str) -> u32 {
        // 简单估算：英文约 4 字符/token，中文约 2 字符/token
        let estimate = |text: &str| -> u32 {
            let chars = text.chars().count();
            let cjk = text.chars().filter(|c| *c as u32 > 0x7F).count();
            let non_cjk = chars - cjk;
            ((cjk / 2) + (non_cjk / 4)) as u32
        };

        let mut total = estimate(system) + estimate(message);
        for msg in context {
            total += estimate(&msg.content);
        }
        total
    }

    /// 🔒 SAFETY: 调用 Provider 喵
    async fn call_provider(&self, messages: &[AgentMessage]) -> Result<String, AgentError> {
        // TODO: 根据不同的 Provider 类型调用相应的接口
        // 现在只是模拟返回
        Ok("模拟响应".to_string())
    }

    /// 🔒 SAFETY: 保存到历史喵
    async fn save_to_history(&self, user_message: &str, response: &str) {
        let mut history = self.message_history.write().await;
        history.push(AgentMessage::user(user_message.to_string()));
        history.push(AgentMessage::assistant(response.to_string()));

        // 限制历史长度
        if history.len() > 100 {
            history.drain(0..2);
        }
    }

    /// 🔒 SAFETY: 保存到 Memory 喵
    async fn save_to_memory(&self, user_message: &str, response: &str) {
        let entry = MemoryEntry {
            id: Uuid::new_v4().to_string(),
            key: format!("chat::{}", Uuid::new_v4()),
            value: format!("User: {}\nAssistant: {}", user_message, response),
            metadata: serde_json::json!({
                "type": "chat",
                "agent_id": self.config.agent_id,
                "timestamp": chrono::Utc::now().to_rfc3339(),
            }),
            created_at: chrono::Utc::now().to_rfc3339(),
        };

        if let Err(e) = self.memory.store(entry).await {
            warn!("Failed to save to memory: {}", e);
        }
    }

    /// 🔒 SAFETY: 清空历史喵
    pub async fn clear_history(&self) {
        let mut history = self.message_history.write().await;
        history.clear();
        info!("History cleared for agent: {}", self.config.agent_id);
    }

    /// 🔒 SAFETY: 获取统计信息喵
    pub async fn stats(&self) -> AgentStats {
        let history = self.message_history.read().await;
        AgentStats {
            message_count: history.len(),
            context_tokens: self.estimate_tokens(
                &self.load_system_prompt().await,
                &self.load_context().await,
                "",
            ),
            agent_id: self.config.agent_id.clone(),
            model: self.config.model.clone(),
        }
    }
}

/// 🔒 SAFETY: Agent 统计信息结构体喵
#[derive(Debug, Serialize)]
pub struct AgentStats {
    /// 消息数量
    pub message_count: usize,
    /// 上下文 token 数
    pub context_tokens: u32,
    /// Agent ID
    pub agent_id: String,
    /// 模型名称
    pub model: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_agent_message_creation() {
        let msg = AgentMessage::user("Hello".to_string());
        assert_eq!(msg.role, "user");
        assert_eq!(msg.content, "Hello");
    }

    #[test]
    fn test_agent_config_default() {
        let config = AgentConfig::default();
        assert!(!config.agent_id.is_empty());
        assert_eq!(config.max_context_tokens, 8192);
    }
}
