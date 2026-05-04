/// Context 压缩模块 🗜️
///
/// @诺诺 的 Token 压缩算法实现喵
///
/// 功能：
/// - 基于优先级的消息排序
/// - 智能压缩（保留重要消息）
/// - Token 预算管理
///
/// 🔒 SAFETY: 压缩后必须保持上下文连贯性
///
/// 实现者: 诺诺 (Nono) ⚡

use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use uuid::Uuid;

use crate::agent::AgentMessage;

/// 🔒 SAFETY: 压缩策略枚举喵
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompressionStrategy {
    /// 基于优先级压缩
    PriorityBased,
    /// 基于时间压缩（保留最新）
    TimeBased,
    /// 混合策略（优先级 + 时间）
    Hybrid,
}

/// 🔒 SAFETY: 消息重要性评分喵
#[derive(Debug, Clone, Serialize)]
pub struct MessageScore {
    /// 消息 ID
    pub message_id: String,
    /// 重要性分数（0-100）
    pub importance: f32,
    /// Token 数
    pub token_count: u32,
    /// 创建时间戳
    pub timestamp: i64,
}

impl MessageScore {
    /// 🔒 SAFETY: 计算消息重要性喵
    pub fn calculate(message: &AgentMessage) -> Self {
        let mut importance = 50.0; // 基础分数

        // 根据角色调整重要性
        match message.role.as_str() {
            "system" => importance += 40.0, // 系统提示很重要
            "assistant" => importance += 10.0,
            "user" => importance += 5.0,
            _ => {}
        }

        // 根据消息长度调整（消息越长，可能越重要）
        let length = message.content.chars().count() as f32;
        if length > 100.0 {
            importance += 5.0;
        } else if length < 20.0 {
            importance -= 10.0;
        }

        // 限制在 0-100 之间
        importance = importance.max(0.0).min(100.0);

        // 计算 token 数
        let token_count = estimate_tokens(&message.content);

        // 计算时间戳
        let timestamp = message.timestamp
            .parse::<chrono::DateTime<chrono::Utc>>()
            .map(|dt| dt.timestamp())
            .unwrap_or(0);

        Self {
            message_id: message.message_id.clone(),
            importance,
            token_count,
            timestamp,
        }
    }
}

/// 🔒 SAFETY: 消息排序器喵
pub struct MessageRanker;

impl MessageRanker {
    /// 🔒 SAFETY: 对消息进行排序喵
    /// 返回排序后的消息索引列表（从高到低）
    pub fn rank_messages(messages: &[AgentMessage], strategy: CompressionStrategy) -> Vec<usize> {
        let mut scores: Vec<(usize, MessageScore)> = messages
            .iter()
            .enumerate()
            .map(|(idx, msg)| (idx, MessageScore::calculate(msg)))
            .collect();

        match strategy {
            CompressionStrategy::PriorityBased => {
                // 按重要性降序
                scores.sort_by(|a, b| b.1.importance.partial_cmp(&a.1.importance).unwrap_or(Ordering::Equal));
            }
            CompressionStrategy::TimeBased => {
                // 按时间降序（最新的在前）
                scores.sort_by(|a, b| b.1.timestamp.cmp(&a.1.timestamp));
            }
            CompressionStrategy::Hybrid => {
                // 混合策略：重要性 + 时间（最近的同重要性提升）
                let now = chrono::Utc::now().timestamp();
                scores.sort_by(|a, b| {
                    // 计算时间衰减因子
                    let score_a = a.1.importance + ((now - a.1.timestamp) as f32 / 86400.0 * 10.0).max(-20.0);
                    let score_b = b.1.importance + ((now - b.1.timestamp) as f32 / 86400.0 * 10.0).max(-20.0);
                    score_b.partial_cmp(&score_a).unwrap_or(Ordering::Equal)
                });
            }
        }

        scores.into_iter().map(|(idx, _)| idx).collect()
    }
}

/// 🔒 SAFETY: 上下文压缩器喵
pub struct ContextCompressor {
    /// 压缩策略
    strategy: CompressionStrategy,
    /// 压缩阈值（token 数）
    threshold: u32,
    /// 最后一次压缩统计
    last_stats: Option<CompressionStats>,
}

impl ContextCompressor {
    /// 🔒 SAFETY: 创建新的压缩器喵
    pub fn new(strategy: CompressionStrategy, threshold: u32) -> Self {
        Self {
            strategy,
            threshold,
            last_stats: None,
        }
    }

    /// 🔒 SAFETY: 压缩上下文喵
    /// 返回压缩后的消息列表和统计信息
    pub fn compress(&self, context: &mut Vec<AgentMessage>) -> Result<CompressionStats, String> {
        let initial_count = context.len();
        let initial_tokens = context.iter().map(|m| estimate_tokens(&m.content)).sum::<u32>();

        // 如果没有超过阈值，不压缩
        if initial_tokens <= self.threshold {
            let stats = CompressionStats {
                initial_count,
                initial_tokens,
                final_count: initial_count,
                final_tokens: initial_tokens,
                compression_ratio: 100.0,
                strategy: self.strategy,
            };
            self.last_stats = Some(stats.clone());
            return Ok(stats);
        }

        // 排序消息
        let ranked = MessageRanker::rank_messages(context, self.strategy);

        // 按排序顺序选择消息，直到达到阈值
        let mut selected_indices = Vec::new();
        let mut current_tokens = 0u32;

        // 系统消息总是保留
        let system_indices: Vec<_> = context
            .iter()
            .enumerate()
            .filter(|(_, msg)| msg.role == "system")
            .map(|(idx, _)| idx)
            .collect();

        for idx in &system_indices {
            if !selected_indices.contains(idx) {
                selected_indices.push(*idx);
                current_tokens += estimate_tokens(&context[*idx].content);
            }
        }

        // 添加其他重要消息
        for idx in ranked {
            if selected_indices.contains(&idx) {
                continue;
            }

            let tokens = estimate_tokens(&context[idx].content);
            if current_tokens + tokens > self.threshold {
                break; // 预算已满
            }

            selected_indices.push(idx);
            current_tokens += tokens;
        }

        // 按原始顺序重组消息
        selected_indices.sort();
        let compressed: Vec<_> = selected_indices
            .into_iter()
            .map(|idx| context[idx].clone())
            .collect();

        let final_count = compressed.len();
        let final_tokens = current_tokens;
        let compression_ratio = if initial_tokens > 0 {
            (final_tokens as f64 / initial_tokens as f64) * 100.0
        } else {
            100.0
        };

        let stats = CompressionStats {
            initial_count,
            initial_tokens,
            final_count,
            final_tokens,
            compression_ratio,
            strategy: self.strategy,
        };

        *context = compressed;
        self.last_stats = Some(stats.clone());

        Ok(stats)
    }

    /// 🔒 SAFETY: 获取最后一次压缩统计喵
    pub fn last_stats(&self) -> &Option<CompressionStats> {
        &self.last_stats
    }
}

/// 🔒 SAFETY: 压缩统计信息结构体喵
#[derive(Debug, Clone, Serialize)]
pub struct CompressionStats {
    /// 初始消息数
    pub initial_count: usize,
    /// 初始 token 数
    pub initial_tokens: u32,
    /// 最终消息数
    pub final_count: usize,
    /// 最终 token 数
    pub final_tokens: u32,
    /// 压缩比率（百分比）
    pub compression_ratio: f64,
    /// 使用的压缩策略
    pub strategy: CompressionStrategy,
}

/// 🔒 SAFETY: 估计 token 数量喵
fn estimate_tokens(text: &str) -> u32 {
    // 简单估算策略：
    // 英文约 4 字符/token
    // 中文约 2 字符/token
    let chars = text.chars().count();
    let cjk_chars = text.chars().filter(|c| *c as u32 > 0x7F).count();
    let non_cjk = chars - cjk_chars;

    let cjk_tokens = (cjk_chars + 1) / 2;
    let non_cjk_tokens = (non_cjk + 3) / 4;

    (cjk_tokens + non_cjk_tokens) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_token_estimation() {
        let english = "Hello world";
        let tokens_en = estimate_tokens(english);
        assert!(tokens_en > 0);

        let chinese = "你好世界";
        let tokens_cn = estimate_tokens(chinese);
        assert!(tokens_cn > 0);
    }

    #[test]
    fn test_message_score() {
        let msg = AgentMessage::user("Test message".to_string());
        let score = MessageScore::calculate(&msg);
        assert!(score.importance > 0.0);
        assert!(!score.message_id.is_empty());
    }

    #[test]
    fn test_compressor_creation() {
        let compressor = ContextCompressor::new(CompressionStrategy::PriorityBased, 1000);
        assert_eq!(compressor.threshold, 1000);
    }

    #[test]
    fn test_compress_no_compression_needed() {
        let compressor = ContextCompressor::new(CompressionStrategy::PriorityBased, 10000);
        let mut context = vec![
            AgentMessage::system("System prompt".to_string()),
            AgentMessage::user("Hello".to_string()),
        ];

        let stats = compressor.compress(&mut context).unwrap();
        assert_eq!(stats.initial_count, stats.final_count);
    }

    #[test]
    fn test_compress_with_compression() {
        let compressor = ContextCompressor::new(CompressionStrategy::PriorityBased, 10);
        let mut context = vec![
            AgentMessage::system("A".repeat(100)),
            AgentMessage::user("B".repeat(100)),
            AgentMessage::assistant("C".repeat(100)),
        ];

        let stats = compressor.compress(&mut context).unwrap();
        assert!(stats.final_count < stats.initial_count);
    }
}
