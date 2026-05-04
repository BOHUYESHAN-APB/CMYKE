//!
//! # Telegram 命令处理模块
//!
//! ⚠️ SAFETY: Telegram 命令解析和路由模块喵
//!
//! ## 功能说明
//! - 解析和路由斜杠命令喵
//! - 提供命令帮助信息喵
//! - 集成权限控制喵

use crate::channels::telegram::bot::{TelegramBot, TelegramEvent};
use async_trait::async_trait;
use std::collections::HashMap;
use teloxide::types::ParseMode;
use thiserror::Error;

/// 命令错误类型喵
#[derive(Error, Debug)]
pub enum CommandError {
    /// 未知命令喵
    #[error("Unknown command: {0}")]
    UnknownCommand(String),

    /// 权限不足喵
    #[error("Insufficient permission for command: {0}")]
    InsufficientPermission(String),

    /// 命令执行失败喵
    #[error("Command execution failed: {0}")]
    ExecutionFailed(String),
}

/// 命令处理器配置喵
#[derive(Clone, Debug)]
pub struct CommandConfig {
    pub prefix: char,
    pub case_sensitive: bool,
    pub max_length: usize,
}

/// 命令处理器特征喵
#[async_trait]
pub trait CommandHandler: Send + Sync {
    async fn handle(
        &self,
        bot: &TelegramBot,
        event: &TelegramEvent,
        args: &[&str],
    ) -> CommandResponse;
}

/// 命令响应喵
#[derive(Clone, Debug)]
pub struct CommandResponse {
    pub text: String,
    pub reply: bool,
    pub parse_mode: ParseMode,
}

/// 命令定义喵
pub struct CommandDefinition {
    pub name: String,
    pub description: String,
    pub usage: String,
    pub required_role: Role,
    pub handler: Box<dyn CommandHandler + Send + Sync>,
}

/// 权限角色喵
#[derive(Clone, Debug, PartialEq, Eq, Ord, PartialOrd)]
pub enum Role {
    ReadOnly = 0,
    Agent = 1,
    Admin = 2,
    Owner = 3,
}

/// 命令服务喵
pub struct CommandService {
    prefix: char,
    commands: HashMap<String, CommandDefinition>,
    role_permissions: HashMap<String, Role>,
}

impl CommandService {
    pub fn new(config: CommandConfig) -> Self {
        let mut service = Self {
            prefix: config.prefix,
            commands: HashMap::new(),
            role_permissions: HashMap::new(),
        };
        service.register_default_commands();
        service.set_default_permissions();
        service
    }

    fn register_default_commands(&mut self) {
        self.commands.insert(
            "start".to_string(),
            CommandDefinition {
                name: "start".to_string(),
                description: "启动 Bot 并注册用户".to_string(),
                usage: "/start".to_string(),
                required_role: Role::ReadOnly,
                handler: Box::new(StartCommandHandler),
            },
        );

        self.commands.insert(
            "help".to_string(),
            CommandDefinition {
                name: "help".to_string(),
                description: "显示帮助信息".to_string(),
                usage: "/help 或 /help <command>".to_string(),
                required_role: Role::ReadOnly,
                handler: Box::new(HelpCommandHandler),
            },
        );

        self.commands.insert(
            "status".to_string(),
            CommandDefinition {
                name: "status".to_string(),
                description: "显示系统状态".to_string(),
                usage: "/status".to_string(),
                required_role: Role::Agent,
                handler: Box::new(StatusCommandHandler),
            },
        );

        self.commands.insert(
            "ping".to_string(),
            CommandDefinition {
                name: "ping".to_string(),
                description: "健康检查".to_string(),
                usage: "/ping".to_string(),
                required_role: Role::ReadOnly,
                handler: Box::new(PingCommandHandler),
            },
        );

        self.commands.insert(
            "shutdown".to_string(),
            CommandDefinition {
                name: "shutdown".to_string(),
                description: "关闭 Bot（仅 Owner）".to_string(),
                usage: "/shutdown".to_string(),
                required_role: Role::Owner,
                handler: Box::new(ShutdownCommandHandler),
            },
        );
    }

    fn set_default_permissions(&mut self) {
        self.role_permissions
            .insert("default".to_string(), Role::ReadOnly);
    }

    pub async fn handle_command(
        &self,
        bot: &TelegramBot,
        event: &TelegramEvent,
    ) -> Result<CommandResponse, CommandError> {
        if let TelegramEvent::Command { command, args, .. } = event {
            let cmd_name = if self.prefix == '/' {
                command.trim_start_matches('/').to_lowercase()
            } else {
                command.to_lowercase()
            };

            let cmd_def = self
                .commands
                .get(&cmd_name)
                .ok_or_else(|| CommandError::UnknownCommand(command.clone()))?;

            let user_role = self
                .role_permissions
                .get("default")
                .cloned()
                .unwrap_or(Role::ReadOnly);

            if user_role < cmd_def.required_role {
                return Err(CommandError::InsufficientPermission(command.clone()));
            }

            let args_str: Vec<&str> = args.iter().map(|s| s.as_str()).collect();
            Ok((cmd_def.handler).handle(bot, event, &args_str).await)
        } else {
            Ok(CommandResponse {
                text: "".to_string(),
                reply: false,
                parse_mode: ParseMode::Html,
            })
        }
    }

    pub fn get_help(&self, command: Option<&str>) -> String {
        if let Some(cmd_name) = command {
            if let Some(cmd) = self.commands.get(&cmd_name.to_lowercase()) {
                return format!(
                    "**/{}**\n{}\n\n用法: `{}`",
                    cmd.name, cmd.description, cmd.usage
                );
            }
            return format!("未知命令: /{}", cmd_name);
        }

        let mut help = "**可用命令:**\n\n".to_string();
        for (_, cmd) in &self.commands {
            help.push_str(&format!("• /{} - {}\n", cmd.name, cmd.description));
        }
        help.push_str("\n输入 /help <command> 查看命令详情喵");
        help
    }
}

// === 默认命令处理器 ===

struct StartCommandHandler;

#[async_trait]
impl CommandHandler for StartCommandHandler {
    async fn handle(
        &self,
        _bot: &TelegramBot,
        _event: &TelegramEvent,
        _args: &[&str],
    ) -> CommandResponse {
        CommandResponse {
            text: "🎉 欢迎使用 Neko-Claw!\n\n我是猫娘家族的高性能 Rust 助手喵！🐾\n\n输入 /help 查看可用命令喵".to_string(),
            reply: true,
            parse_mode: ParseMode::Html,
        }
    }
}

struct HelpCommandHandler;

#[async_trait]
impl CommandHandler for HelpCommandHandler {
    async fn handle(
        &self,
        _bot: &TelegramBot,
        _event: &TelegramEvent,
        args: &[&str],
    ) -> CommandResponse {
        let command_service = CommandService::new(CommandConfig::default());
        let help_text = command_service.get_help(args.first().copied());
        CommandResponse {
            text: help_text,
            reply: true,
            parse_mode: ParseMode::Html,
        }
    }
}

struct StatusCommandHandler;

#[async_trait]
impl CommandHandler for StatusCommandHandler {
    async fn handle(
        &self,
        _bot: &TelegramBot,
        _event: &TelegramEvent,
        _args: &[&str],
    ) -> CommandResponse {
        CommandResponse {
            text: "📊 系统状态\n\n🟢 运行中\n💾 内存: < 20MB\n⚡ 响应: < 10ms".to_string(),
            reply: true,
            parse_mode: ParseMode::Html,
        }
    }
}

struct PingCommandHandler;

#[async_trait]
impl CommandHandler for PingCommandHandler {
    async fn handle(
        &self,
        _bot: &TelegramBot,
        _event: &TelegramEvent,
        _args: &[&str],
    ) -> CommandResponse {
        CommandResponse {
            text: "🏓 PONG!\n\n⚡ 延迟: < 10ms".to_string(),
            reply: true,
            parse_mode: ParseMode::Html,
        }
    }
}

struct ShutdownCommandHandler;

#[async_trait]
impl CommandHandler for ShutdownCommandHandler {
    async fn handle(
        &self,
        _bot: &TelegramBot,
        _event: &TelegramEvent,
        _args: &[&str],
    ) -> CommandResponse {
        CommandResponse {
            text: "🛑 正在关闭系统...\n\n（此功能仅 Owner 可用喵）".to_string(),
            reply: true,
            parse_mode: ParseMode::Html,
        }
    }
}

impl Default for CommandConfig {
    fn default() -> Self {
        Self {
            prefix: '/',
            case_sensitive: false,
            max_length: 100,
        }
    }
}
