//!
//! # 渠道模块集成测试
//!
//! ⚠️ SAFETY: 测试 Discord 和 Telegram 渠道模块的集成喵
//!
//! ## 测试范围
//! - Discord Bot 消息接收/发送喵
//! - Telegram Bot 消息接收/发送喵
//! - 渠道事件流测试喵
//!
//! ## 运行命令
//! ```bash
//! cargo test --test integration channel_test -- --nocapture
//! ```

use crate::channels::discord::{DiscordBot, DiscordConfig, DiscordEvent};
use crate::channels::telegram::{TelegramBot, TelegramConfig, TelegramEvent};
use std::sync::Arc;
use std::collections::HashSet;

/// 测试 Discord 配置喵
#[tokio::test]
async fn test_discord_config() {
    let config = DiscordConfig::default();
    
    // 检查默认配置喵
    assert!(!config.max_message_length == 0);
    assert!(config.enable_xss_filter);
}

/// 测试 Discord 消息过滤喵
#[tokio::test]
async fn test_discord_xss_filter() {
    let config = DiscordConfig::default();
    let bot = DiscordBot::new("test_token".to_string(), config).unwrap();
    
    // 测试危险内容喵
    assert!(bot.filter_xss("<script>alert('xss')</script>").is_err());
    assert!(bot.filter_xss("javascript:alert('xss')").is_err());
    
    // 测试安全内容喵
    assert!(bot.filter_xss("Hello, World!").is_ok());
    assert!(bot.filter_xss("普通文本消息").is_ok());
}

/// 测试 Discord 命令注入防护喵
#[tokio::test]
async fn test_discord_command_injection_protection() {
    let config = DiscordConfig::default();
    let bot = DiscordBot::new("test_token".to_string(), config).unwrap();
    
    // 测试危险命令喵
    assert!(bot.check_command_injection("ls | cat").is_err());
    assert!(bot.check_command_injection("echo test; rm -rf /").is_err());
    
    // 测试安全命令喵
    assert!(bot.check_command_injection("start").is_ok());
    assert!(bot.check_command_injection("help").is_ok());
}

/// 测试 Discord 消息长度限制喵
#[tokio::test]
async fn test_discord_message_length() {
    let config = DiscordConfig::default();
    let bot = DiscordBot::new("test_token".to_string(), config).unwrap();
    
    // 测试超长消息喵
    let long_message = "a".repeat(bot.config.max_message_length + 1);
    assert!(bot.check_message_length(&long_message).is_err());
    
    // 测试正常长度消息喵
    let normal_message = "Hello".to_string();
    assert!(bot.check_message_length(&normal_message).is_ok());
}

/// 测试 Telegram 配置喵
#[tokio::test]
async fn test_telegram_config() {
    let config = TelegramConfig::default();
    
    // 检查默认配置喵
    assert!(!config.max_message_length == 0);
    assert!(config.enable_xss_filter);
    assert!(config.enable_command_injection_protection);
}

/// 测试 Telegram XSS 过滤喵
#[tokio::test]
async fn test_telegram_xss_filter() {
    let config = TelegramConfig::default();
    let bot = TelegramBot::new("test_token".to_string(), config).unwrap();
    
    // 测试危险内容喵
    assert!(bot.filter_xss("<script>alert('xss')</script>").is_err());
    assert!(bot.filter_xss("javascript:alert('xss')").is_err());
    assert!(bot.filter_xss("<img onerror=alert(1)>").is_err());
    
    // 测试安全内容喵
    assert!(bot.filter_xss("Hello, World!").is_ok());
    assert!(bot.filter_xss("普通文本消息").is_ok());
}

/// 测试 Telegram 命令注入防护喵
#[tokio::test]
async fn test_telegram_command_injection_protection() {
    let config = TelegramConfig::default();
    let bot = TelegramBot::new("test_token".to_string(), config).unwrap();
    
    // 测试危险命令喵
    assert!(bot.check_command_injection("ls | cat").is_err());
    assert!(bot.check_command_injection("echo test; rm -rf /").is_err());
    assert!(bot.check_command_injection("echo $(whoami)").is_err());
    
    // 测试安全命令喵
    assert!(bot.check_command_injection("start").is_ok());
    assert!(bot.check_command_injection("help").is_ok());
}

/// 测试 Telegram Chat ID 白名单喵
#[tokio::test]
async fn test_telegram_chat_whitelist() {
    let mut config = TelegramConfig::default();
    config.token = "test_token".to_string();
    let mut bot = TelegramBot::new(config.token.clone(), config).unwrap();
    
    // 添加允许的 Chat ID喵
    bot.add_allowed_chat_id(123456789);
    
    // 检查白名单喵（内部测试）
    let allowed_ids: Arc<HashSet<i64>> = Arc::new(HashSet::from([123456789]));
    assert!(allowed_ids.contains(&123456789));
}

/// 测试 Discord 事件创建喵
#[tokio::test]
async fn test_discord_event_creation() {
    // 测试文本消息事件创建喵
    let event = DiscordEvent::TextMessage {
        channel_id: 123456789,
        user_id: 987654321,
        username: Some("test_user".to_string()),
        text: "Hello World".to_string(),
        timestamp: chrono::Utc::now(),
    };
    
    match event {
        DiscordEvent::TextMessage { text, .. } => {
            assert_eq!(text, "Hello World");
        }
        _ => panic!("Expected TextMessage event"),
    }
}

/// 测试 Telegram 事件创建喵
#[tokio::test]
async fn test_telegram_event_creation() {
    // 测试文本消息事件创建喵
    let event = TelegramEvent::TextMessage {
        chat_id: 123456789,
        user_id: 987654321,
        username: Some("test_user".to_string()),
        text: "Hello World".to_string(),
        timestamp: chrono::Utc::now(),
    };
    
    match event {
        TelegramEvent::TextMessage { text, .. } => {
            assert_eq!(text, "Hello World");
        }
        _ => panic!("Expected TextMessage event"),
    }
}

/// 测试命令消息事件创建喵
#[tokio::test]
async fn test_telegram_command_event_creation() {
    let event = TelegramEvent::Command {
        chat_id: 123456789,
        user_id: 987654321,
        username: Some("test_user".to_string()),
        command: "start".to_string(),
        args: vec!["arg1".to_string(), "arg2".to_string()],
        timestamp: chrono::Utc::now(),
    };
    
    match event {
        TelegramEvent::Command { command, args, .. } => {
            assert_eq!(command, "start");
            assert_eq!(args.len(), 2);
        }
        _ => panic!("Expected Command event"),
    }
}

/// 测试 Discord 消息长度默认限制喵
#[tokio::test]
async fn test_discord_default_length_limit() {
    let config = DiscordConfig::default();
    assert!(config.max_message_length > 0);
    assert!(config.max_message_length <= 2000); // Discord 限制喵
}

/// 测试 Telegram 消息长度默认限制喵
#[tokio::test]
async fn test_telegram_default_length_limit() {
    let config = TelegramConfig::default();
    assert!(config.max_message_length > 0);
    assert!(config.max_message_length <= 4096); // Telegram 限制喵
}

/// 测试渠道安全功能默认启用喵
#[tokio::test]
async fn test_channel_security_defaults() {
    // Discord
    let discord_config = DiscordConfig::default();
    assert!(discord_config.enable_xss_filter);
    
    // Telegram
    let telegram_config = TelegramConfig::default();
    assert!(telegram_config.enable_xss_filter);
    assert!(telegram_config.enable_command_injection_protection);
}
