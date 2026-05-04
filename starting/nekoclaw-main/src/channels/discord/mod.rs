/*!
 * Discord Channel Module
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 18:40 JST
 */

pub mod bot;
pub mod commands;

// 重新导出公共接口
pub use bot::{DiscordBot, DiscordConfig, DiscordEvent};
pub use commands::{
    create_default_commands, CommandContext, CommandHandler, CommandManager, CommandResult,
    ConfigCommand, HelpCommand, MemoryCommand, StatusCommand,
};

// Note: Channel trait implementation for DiscordBot is in bot.rs
// This avoids duplicate implementation
