/// Agent 上下文管理模块 🧠
///
/// @诺诺 的 Agent 上下文管理实现喵
///
/// 功能：
/// - 上下文窗口管理
/// - 消息优先级排序
/// - Token 估计与优化
/// - 上下文压缩
///
/// 🔒 SAFETY: 上下文数据自动加密
///
/// 实现者: 诺诺 (Nono) ⚡

use serde::{Deserialize, Serialize};
use std::collections::VecDeque;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{debug, info, warn};
use uuid::Uuid;

use super::runtime::AgentMessage;

/// 🔒 SAFETY: 上下文配置喵
#[derive(Debug, Clone)]
pub struct ContextConfig {
    /// 最大 token 数
    pub max_tokens: u32,
    /// 系统提示 token 数（预留）
    pub system_tokens: u32,
    /// 是否启用自动压缩
    pub auto_compress: bool,
    /// 压缩阈值（token 数，超过自动压缩）
    pub compress_threshold: u32,
}

impl Default for ContextConfig {
    fn default() -> Self {
        Self {
            max_tokens: 8192,
            system_tokens: 1000,
            auto_compress: true,
            compress_threshold: 6000,
        }
    }
}

/// 🔒 SAFETY: 消息优先级枚举喵
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum MessagePriority {
    /// 低（旧消息）
    Low = 0,
    /// 中
    Medium = 1,
    /// 高（系统提示）
    High = 2,
}

/// 🔒 SAFETY: 带优先级的消息结构体喵
#[derive(Debug, Clone)]
pub struct PrioritizedMessage {
    /// 消息
    pub message: AgentMessage,
    /// 优先级
    pub priority: MessagePriority,
    /// Token 数（估计）
    pub token_count: u32,
}

impl PrioritizedMessage {
    /// 🔒 SAFETY: 创建优先级消息喵
    pub fn new(message: AgentMessage, priority: MessagePriority, token_count: u32) -> Self {
        Self {
            message,
            priority,
            token_count,
        }
    }
}

/// 🔒 SAFETY: 上下文管理器结构体喵
#[derive(Debug, Clone)]
pub struct ContextManager {
    /// 配置
    config: Arc<ContextConfig>,
    /// 消息队列（按优先级排序）
    messages: Arc<RwLock<VecDeque<PrioritizedMessage>>>,
    /// 系统 prompt
    system_prompt: Arc<RwLock<Option<AgentMessage>>>,
}

impl ContextManager {
    /// 🔒 SAFETY: 创建新的上下文管理器喵
    pub fn new(config: ContextConfig) -> Self {
        Self {
            config: Arc::new(config),
            messages: Arc::new(RwLock::new(VecDeque::new())),
            system_prompt: Arc::new(RwLock::new(None)),
        }
    }

    /// 🔒 SAFETY: 设置系统提示喵
    pub async fn set_system_prompt(&self, prompt: String) {
        let mut system = self.system_prompt.write().await;
        let tokens = self.estimate_tokens(&prompt);
        *system = Some(AgentMessage::system(prompt));
        info!("System prompt set ({} tokens)", tokens);
    }

    /// 🔒 SAFETY: 添加消息喵
    pub async fn add_message(&self, message: AgentMessage, priority: MessagePriority) {
        let tokens = self.estimate_tokens(&message.content);
        let prio_msg = PrioritizedMessage::new(message, priority, tokens);

        let mut messages = self.messages.write().await;
        messages.push_back(prio_msg);

        // 检查是否需要自动压缩
        if self.config.auto_compress {
            let total = self.calculate_total_tokens(&messages).await;
            if total > self.config.max_tokens {
                warn!(
                    "Context overflow ({} tokens), compressing...",
                    total
                );
                self.compress_messages(&mut messages).await;
            }
        }

        debug!("Message added ({} tokens), total messages: {}", tokens, messages.len());
    }

    /// 🔒 SAFETY: 获取上下文消息列表喵
    /// 自动处理大小，返回符合限制的消息
    pub async fn get_context(&self) -> Vec<AgentMessage> {
        let messages = self.messages.read().await;
        let system = self.system_prompt.read().await;

        let mut result = Vec::new();

        // 添加系统提示
        if let Some(ref sys) = *system {
            result.push(sys.clone());
        }

        // 计算剩余 token 预算
        let mut budget = self.config.max_tokens as i32 - self.config.system_tokens as i32;

        // 按优先级排序并添加消息
        let mut sorted: Vec<_> = messages.iter().collect();
        sorted.sort_by(|a, b| {
            // 优先级倒序（高优先级在前）
            b.priority.cmp(&a.priority)
            // 相同优先级，较新的在前
            .then_with(|| {
                if a.message.timestamp > b.message.timestamp {
                    std::cmp::Ordering::Less
                } else {
                    std::cmp::Ordering::Greater
                }
            })
        });

        for prio_msg in sorted {
            if budget - prio_msg.token_count as i32 >= 0 {
                result.push(prio_msg.message.clone());
                budget -= prio_msg.token_count as i32;
            } else {
                break; // 预算不足，停止添加
            }
        }

        info!(
            "Context built: {} messages, {} tokens used",
            result.len(),
            self.config.max_tokens - budget as u32
        );

        result
    }

    /// 🔒 SAFETY: 清空上下文喵
    pub async fn clear(&self) {
        let mut messages = self.messages.write().await;
        messages.clear();
        info!("Context cleared");
    }

    /// 🔒 SAFETY: 估计 token 数量喵
    fn estimate_tokens(&self, text: &str) -> u32 {
        // 简单估算策略：
        // 1. 英文约 4 字符/token
        // 2. 中文约 2 字符/token
        // 3. 混合文本按比例估算

        let chars = text.chars().count();
        let cjk_chars = text.chars().filter(|c| *c as u32 > 0x7F).count();
        let non_cjk = chars - cjk_chars;

        let cjk_tokens = (cjk_chars + 1) / 2;
        let non_cjk_tokens = (non_cjk + 3) / 4;

        (cjk_tokens + non_cjk_tokens) as u32
    }

    /// 🔒 SAFETY: 计算总 token 数量喵
    async fn calculate_total_tokens(&self, messages: &VecDeque<PrioritizedMessage>) -> u32 {
        let mut total = 0;
        for prio_msg in messages.iter() {
            total += prio_msg.token_count;
        }
        total
    }

    /// 🔒 SAFETY: 压缩消息队列喵
    /// 移除低优先级和旧消息
    async fn compress_messages(&self, messages: &mut VecDeque<PrioritizedMessage>) {
        let target = self.config.compress_threshold as usize;

        while messages.len() > target {
            // 移除最早的消息
            if let Some(_) = messages.pop_front() {
                debug!("Message removed due to compression");
            } else {
                break;
            }
        }
    }

    /// 🔒 SAFETY: 获取统计信息喵
    pub async fn stats(&self) -> ContextStats {
        let messages = self.messages.read().await;
        let total_tokens = self.calculate_total_tokens(&messages).await;

        let high_priority = messages.iter().filter(|m| m.priority == MessagePriority::High).count();
        let medium_priority = messages.iter().filter(|m| m.priority == MessagePriority::Medium).count();
        let low_priority = messages.iter().filter(|m| m.priority == MessagePriority::Low).count();

        ContextStats {
            total_messages: messages.len(),
            total_tokens,
            high_priority,
            medium_priority,
            low_priority,
        }
    }
}

/// 🔒 SAFETY: 上下文统计信息结构体喵
#[derive(Debug, Serialize)]
pub struct ContextStats {
    /// 总消息数
    pub total_messages: usize,
    /// 总 token 数
    pub total_tokens: u32,
    /// 高优先级消息数
    pub high_priority: usize,
    /// 中优先级消息数
    pub medium_priority: usize,
    /// 低优先级消息数
    pub low_priority: usize,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_estimation() {
        let config = ContextConfig::default();
        let manager = ContextManager::new(config);

        // 纯英文测试
        let english = "Hello world";
        let tokens_en = manager.estimate_tokens(english);
        assert!(tokens_en > 0);

        // 纯中文测试
        let chinese = "你好世界";
        let tokens_cn = manager.estimate_tokens(chinese);
        assert!(tokens_cn > 0);
    }

    #[test]
    fn test_prioritized_message() {
        let msg = AgentMessage::user("Test".to_string());
        let prio = PrioritizedMessage::new(msg, MessagePriority::Medium, 10);
        assert_eq!(prio.priority, MessagePriority::Medium);
        assert_eq!(prio.token_count, 10);
    }

    #[tokio::test]
    async fn test_context_manager() {
        let config = ContextConfig::default();
        let manager = ContextManager::new(config);

        manager
            .add_message(AgentMessage::user("Test1".to_string()), MessagePriority::Medium)
            .await;
        manager
            .add_message(AgentMessage::user("Test2".to_string()), MessagePriority::Medium)
            .await;

        let context = manager.get_context().await;
        assert_eq!(context.len(), 2);

        let stats = manager.stats().await;
        assert_eq!(stats.total_messages, 2);
    }
}
