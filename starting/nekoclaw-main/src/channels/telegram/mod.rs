//!
//! # Telegram Channel Module
//!
//! ⚠️ SAFETY: Telegram 渠道模块喵
//!
//! ## 功能说明
//! - 实现 Telegram Bot 的消息接收和发送喵
//! - 支持斜杠命令处理喵
//! - 集成安全消息过滤喵
//!
//! ## 模块结构
//! - `bot`: Telegram Bot 核心实现喵
//! - `commands`: 命令解析和路由喵
//!
//! ## 使用说明
//! ```rust
//! use nekoclaw::channels::telegram::{TelegramBot, TelegramConfig};
//!
//! let config = TelegramConfig::default();
//! let bot = TelegramBot::new("your_token".to_string(), config)?;
//! ```

pub mod bot;
pub mod commands;

pub use bot::{TelegramBot, TelegramConfig, TelegramError, TelegramEvent};
pub use commands::{CommandConfig, CommandResponse, CommandService, Role};
