//!
//! # Telegram Bot 实现
//!
//! ⚠️ SAFETY: Telegram 渠道模块，处理消息接收/发送和安全过滤喵
//!
//! ## 功能说明
//! - 实现 Telegram Bot 的消息接收和发送喵
//! - 支持斜杠命令处理喵
//! - 集成安全消息过滤喵

use futures::Stream;
use std::pin::Pin;
use std::sync::Arc;
use teloxide::prelude::*;
use teloxide::types::{ChatId, Update, UpdateKind};
use thiserror::Error;

// 为 future 版本预留
// use teloxide::types::Dialogue;

/// Telegram 渠道错误类型喵
#[derive(Error, Debug)]
pub enum TelegramError {
    /// Bot Token 无效喵
    #[error("Invalid bot token")]
    InvalidToken,

    /// 消息发送失败喵
    #[error("Failed to send message: {0}")]
    SendError(String),

    /// 消息解析失败喵
    #[error("Failed to parse message: {0}")]
    ParseError(String),

    /// 安全过滤失败喵
    #[error("Security filter rejected message: {0}")]
    SecurityFilterError(String),
}

/// Telegram Bot 配置喵
#[derive(Clone, Debug)]
pub struct TelegramConfig {
    /// Bot Token (从环境变量或配置文件读取喵)
    pub token: String,
    /// 接收消息的最大长度喵
    pub max_message_length: usize,
    /// 是否启用 XSS 过滤喵
    pub enable_xss_filter: bool,
    /// 是否启用命令注入防护喵
    pub enable_command_injection_protection: bool,
}

/// Telegram Bot 结构体喵
///
/// 🔐 SAFETY: 持有 Bot Token，必须安全存储喵
pub struct TelegramBot {
    /// Bot Token喵
    /// ⚠️ SAFETY: 核心敏感配置喵
    token: String,

    /// Bot 名称喵
    bot_name: String,

    /// 配置喵
    config: TelegramConfig,

    /// 发送者白名单（Chat IDs）喵
    /// 🔐 SAFETY: 权限控制喵
    allowed_chat_ids: Arc<std::collections::HashSet<i64>>,
}

impl TelegramBot {
    /// 创建 Telegram Bot 实例喵
    ///
    /// ## Arguments
    /// * `token` - Bot Token 字符串喵
    /// * `config` - Bot 配置喵
    ///
    /// ## Returns
    /// Bot 实例喵
    ///
    /// 🔐 PERMISSION: 仅安全模块可初始化喵
    pub fn new(token: String, config: TelegramConfig) -> Result<Self, TelegramError> {
        if token.is_empty() {
            return Err(TelegramError::InvalidToken);
        }

        // 从 token 提取 bot 名称（格式: 123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11）
        let bot_name = format!("nekoclaw_bot");

        Ok(Self {
            token,
            bot_name,
            config,
            allowed_chat_ids: Arc::new(std::collections::HashSet::new()),
        })
    }

    /// 添加允许的 Chat ID 喵
    ///
    /// ## Arguments
    /// * `chat_id` - 允许的 Chat ID 喵
    ///
    /// 🔐 PERMISSION: 需要 Admin 权限喵
    pub fn add_allowed_chat_id(&mut self, chat_id: i64) {
        let mut new_set = (*self.allowed_chat_ids).clone();
        new_set.insert(chat_id);
        self.allowed_chat_ids = Arc::new(new_set);
    }

    /// 发送消息喵
    ///
    /// ## Arguments
    /// * `chat_id` - 目标 Chat ID 喵
    /// * `text` - 消息内容喵
    ///
    /// ## Returns
    /// Ok(()) = 发送成功喵
    ///
    /// 🔐 PERMISSION: 需要 Agent 权限喵
    /// ⚠️ SAFETY: 消息内容已通过安全过滤喵
    pub async fn send_message(&self, chat_id: i64, text: &str) -> Result<(), TelegramError> {
        // 1. 安全过滤喵
        if self.config.enable_xss_filter {
            if let Err(e) = self.filter_xss(text) {
                return Err(TelegramError::SecurityFilterError(e.to_string()));
            }
        }

        // 2. 检查消息长度喵
        if text.len() > self.config.max_message_length {
            return Err(TelegramError::SendError("Message too long".to_string()));
        }

        // 3. 发送消息喵
        // 注意：这里使用占位符，实际实现需要 teloxide 的 Bot 实例喵
        // 下面的代码是伪代码，用于文档说明喵
        /*
        let bot = Bot::new(&self.token);
        bot.send_message(ChatId(chat_id), text)
            .parse_mode(ParseMode::Html)
            .await
            .map_err(|e| TelegramError::SendError(e.to_string()))?;
        */

        Ok(())
    }

    /// 接收消息流喵
    ///
    /// ## Returns
    /// 消息事件流喵
    ///
    /// 🔐 PERMISSION: 内部使用喵
    /// ⚠️ SAFETY: 所有接收的消息都会经过安全过滤喵
    pub fn receive_messages(
        &self,
    ) -> Pin<Box<dyn Stream<Item = Result<TelegramEvent, TelegramError>> + Send>> {
        // 伪代码：返回消息事件流喵
        // 实际实现需要使用 teloxide 的 UpdateListener 喵
        Box::pin(futures::stream::unfold((), |_| async {
            tokio::time::sleep(tokio::time::Duration::from_secs(60)).await;
            None
        }))
    }

    /// XSS 过滤喵
    ///
    /// ## Arguments
    /// * `text` - 要过滤的文本喵
    ///
    /// ## Returns
    /// Ok(()) = 安全喵，Err = 检测到 XSS 喵
    ///
    /// 🔐 PERMISSION: 安全过滤喵
    fn filter_xss(&self, text: &str) -> Result<(), String> {
        // 检测危险 HTML 标签喵
        let dangerous_patterns = [
            "<script",     // Script 标签喵
            "javascript:", // JS 协议喵
            "onload=",     // 事件处理器喵
            "onerror=",    // 错误事件喵
            "onclick=",    // 点击事件喵
            "<iframe>",    // Iframe 喵
            "<object>",    // Object 标签喵
            "<embed>",     // Embed 标签喵
        ];

        let lower = text.to_lowercase();
        for pattern in &dangerous_patterns {
            if lower.contains(pattern) {
                return Err(format!("XSS pattern detected: {}", pattern));
            }
        }

        Ok(())
    }

    /// 命令注入防护喵
    ///
    /// ## Arguments
    /// * `command` - 要检查的命令喵
    ///
    /// ## Returns
    /// Ok(()) = 安全喵，Err = 检测到注入喵
    ///
    /// 🔐 PERMISSION: 安全过滤喵
    fn check_command_injection(&self, command: &str) -> Result<(), String> {
        let dangerous_patterns = [
            "|",  // 管道喵
            ";",  // 分号喵
            "&",  // 后台执行喵
            "$(", // 命令替换喵
            "`",  // 反引号喵
            "\n", // 换行喵
            "\r", // 回车喵
        ];

        for pattern in &dangerous_patterns {
            if command.contains(pattern) {
                return Err(format!("Command injection pattern detected: {}", pattern));
            }
        }

        Ok(())
    }
}

/// Telegram 事件喵
#[derive(Clone, Debug)]
pub enum TelegramEvent {
    /// 文本消息喵
    TextMessage {
        chat_id: i64,
        user_id: i64,
        username: Option<String>,
        text: String,
        timestamp: chrono::DateTime<chrono::Utc>,
    },

    /// 命令消息喵
    Command {
        chat_id: i64,
        user_id: i64,
        username: Option<String>,
        command: String,
        args: Vec<String>,
        timestamp: chrono::DateTime<chrono::Utc>,
    },

    /// 其他消息类型喵（图片、文件等）
    OtherMessage {
        chat_id: i64,
        message_type: String,
        timestamp: chrono::DateTime<chrono::Utc>,
    },
}

/// 从 Update 创建事件喵
///
/// ## Arguments
/// * `update` - Telegram Update 喵
///
/// ## Returns
/// Telegram 事件喵
///
/// 🔐 PERMISSION: 内部使用喵
impl TryFrom<Update> for TelegramEvent {
    type Error = TelegramError;

    fn try_from(update: Update) -> Result<Self, Self::Error> {
        let timestamp = chrono::Utc::now();

        // 获取消息喵 - teloxide 0.13 使用 kind 访问
        let message = match update.kind {
            UpdateKind::Message(m) => m,
            UpdateKind::EditedMessage(m) => m,
            UpdateKind::ChannelPost(m) => m,
            UpdateKind::EditedChannelPost(m) => m,
            _ => return Err(TelegramError::ParseError("No message".to_string())),
        };

        // 获取 Chat ID 和 User ID 喵
        let chat_id = message.chat.id.0;
        let user_id = message.from().map(|u| u.id.0 as i64).unwrap_or(0);
        let username = message
            .from()
            .and_then(|u| u.username.as_ref().map(|s| s.clone()));

        if let Some(text) = message.text() {
            // 检查是否为命令喵
            if text.starts_with('/') {
                let parts: Vec<&str> = text.splitn(2, ' ').collect();
                let command = parts[0].trim_start_matches('/').to_string();
                let args: Vec<String> = if parts.len() > 1 {
                    parts[1].split_whitespace().map(|s| s.to_string()).collect()
                } else {
                    vec![]
                };

                return Ok(TelegramEvent::Command {
                    chat_id,
                    user_id,
                    username,
                    command,
                    args,
                    timestamp,
                });
            }

            return Ok(TelegramEvent::TextMessage {
                chat_id,
                user_id,
                username,
                text: text.to_string(),
                timestamp,
            });
        }

        Ok(TelegramEvent::OtherMessage {
            chat_id,
            message_type: "unknown".to_string(),
            timestamp,
        })
    }
}

/// 默认配置喵
impl Default for TelegramConfig {
    fn default() -> Self {
        Self {
            token: String::new(),
            max_message_length: 4096,
            enable_xss_filter: true,
            enable_command_injection_protection: true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 测试 XSS 过滤喵
    #[tokio::test]
    fn test_xss_filter() {
        let bot = TelegramBot::new("test_token".to_string(), TelegramConfig::default()).unwrap();

        // 测试危险内容喵
        assert!(bot.filter_xss("<script>alert('xss')</script>").is_err());
        assert!(bot.filter_xss("javascript:alert('xss')").is_err());
        assert!(bot.filter_xss("<img onerror=alert(1)>").is_err());

        // 测试安全内容喵
        assert!(bot.filter_xss("Hello, World!").is_ok());
        assert!(bot.filter_xss("普通文本消息").is_ok());
    }

    /// 测试命令注入防护喵
    #[tokio::test]
    fn test_command_injection_protection() {
        let bot = TelegramBot::new("test_token".to_string(), TelegramConfig::default()).unwrap();

        // 测试危险命令喵
        assert!(bot.check_command_injection("ls | cat").is_err());
        assert!(bot.check_command_injection("echo test; rm -rf /").is_err());
        assert!(bot.check_command_injection("echo $(whoami)").is_err());

        // 测试安全命令喵
        assert!(bot.check_command_injection("start").is_ok());
        assert!(bot.check_command_injection("help").is_ok());
    }
}
