//! # 白名单检查模块
//!
//! ⚠️ SAFETY: 访问控制核心模块，用于限制可执行的命令和访问的路径喵
//!
//! ## 功能说明
//! - 管理可执行命令的白名单喵
//! - 管理可访问路径的白名单喵
//! - 提供快速的 O(1) 查找性能喵
//!
//! ## 使用场景
//! - Shell 命令执行前检查喵
//! - 文件系统访问控制喵
//! - API 端点权限验证喵

use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::path::PathBuf;
use thiserror::Error;

/// 白名单错误类型
#[derive(Error, Debug, Clone)]
pub enum AllowlistError {
    /// 命令不在白名单中喵
    #[error("Command not in whitelist: {0}")]
    CommandNotAllowed(String),

    /// 路径不在白名单中喵
    #[error("Path not in whitelist: {0}")]
    PathNotAllowed(String),

    /// 路径遍历攻击尝试喵
    #[error("Path traversal attack detected: {0}")]
    PathTraversalAttempt(String),
}

/// 命令白名单条目喵
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct CommandAllowlistEntry {
    /// 命令名称（如 "git", "ls", "cat"）
    pub command: String,
    /// 命令描述喵
    pub description: String,
    /// 是否允许带参数喵
    pub allow_args: bool,
    /// 允许的参数模式（正则表达式，空表示不允许参数喵）
    pub arg_pattern: Option<String>,
}

/// 路径白名单条目喵
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct PathAllowlistEntry {
    /// 路径模式（支持 glob 风格喵）
    pub pattern: String,
    /// 路径描述喵
    pub description: String,
    /// 是否允许递归访问喵
    pub recursive: bool,
}

/// 白名单配置喵
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AllowlistConfig {
    /// 命令白名单喵
    pub commands: Vec<CommandAllowlistEntry>,
    /// 路径白名单喵
    pub paths: Vec<PathAllowlistEntry>,
    /// 默认拒绝策略（true=白名单外默认拒绝，false=黑名单模式）
    pub default_deny: bool,
}

/// 白名单服务喵
///
/// 🔐 SAFETY: 核心访问控制模块，必须严格审计喵
#[derive(Clone, Debug)]
pub struct AllowlistService {
    /// 命令白名单（O(1) 查找优化）
    /// 🔐 SAFETY: 不可变的，仅读访问喵
    command_set: HashSet<String>,
    /// 命令详情映射喵
    command_details: HashMap<String, CommandAllowlistEntry>,
    /// 路径白名单喵
    path_set: HashSet<String>,
    /// 默认拒绝策略喵
    default_deny: bool,
}

use std::collections::HashMap;

impl AllowlistService {
    /// 创建白名单服务喵
    ///
    /// ## Arguments
    /// * `config` - 白名单配置喵
    ///
    /// ## Returns
    /// 初始化后的白名单服务喵
    ///
    /// 🔐 PERMISSION: 仅允许安全模块初始化喵
    pub fn new(config: AllowlistConfig) -> Self {
        let mut command_set = HashSet::new();
        let mut command_details = HashMap::new();

        for entry in config.commands {
            command_set.insert(entry.command.clone());
            command_details.insert(entry.command.clone(), entry);
        }

        let mut path_set = HashSet::new();
        for entry in config.paths {
            path_set.insert(entry.pattern);
        }

        Self {
            command_set,
            command_details,
            path_set,
            default_deny: config.default_deny,
        }
    }

    /// 检查命令是否在白名单中喵
    ///
    /// ## Arguments
    /// * `command` - 要检查的命令名称喵
    ///
    /// ## Returns
    /// Ok(CommandAllowlistEntry) = 允许喵，Err = 拒绝喵
    ///
    /// 🔐 PERMISSION: 需要对执行命令进行安全检查喵
    pub fn check_command(&self, command: &str) -> Result<CommandAllowlistEntry, AllowlistError> {
        // 标准化命令名称（小写，移除路径喵）
        let normalized = command.to_lowercase();
        let normalized = normalized
            .split_whitespace()
            .next()
            .unwrap_or("")
            .split('/')
            .last()
            .unwrap_or("");

        if self.command_set.contains(normalized) {
            // 🔒 SAFETY: 使用 ok_or 替代 unwrap() 喵
            self.command_details.get(normalized)
                .cloned()
                .ok_or_else(|| AllowlistError::CommandNotAllowed(command.to_string()))
        } else if self.default_deny {
            Err(AllowlistError::CommandNotAllowed(command.to_string()))
        } else {
            Ok(CommandAllowlistEntry {
                command: command.to_string(),
                description: "Default allowed".to_string(),
                allow_args: false,
                arg_pattern: None,
            })
        }
    }

    /// 检查命令是否允许（简化接口）喵
    ///
    /// ## Arguments
    /// * `command` - 要检查的命令名称喵
    ///
    /// ## Returns
    /// true = 允许喵，false = 拒绝喵
    pub fn is_command_allowed(&self, command: &str) -> bool {
        self.check_command(command).is_ok()
    }

    /// 检查路径是否允许喵
    ///
    /// ## Arguments
    /// * `path` - 要检查的路径喵
    ///
    /// ## Returns
    /// true = 允许喵，false = 拒绝喵
    pub fn is_path_allowed(&self, path: &str) -> bool {
        self.check_path(path).is_ok()
    }

    /// 检查环境变量是否允许喵
    ///
    /// ## Arguments
    /// * `key` - 环境变量名喵
    ///
    /// ## Returns
    /// true = 允许喵（目前默认允许安全的环境变量）
    pub fn is_env_var_allowed(&self, key: &str) -> bool {
        // 安全的环境变量白名单喵
        let safe_vars = ["HOME", "USER", "PATH", "LANG", "TZ", "TERM", "SHELL", "PWD"];
        safe_vars.contains(&key)
    }

    /// 获取允许的命令列表喵
    ///
    /// ## Returns
    /// 允许的命令名称列表喵
    pub fn get_allowed_commands(&self) -> Vec<String> {
        self.command_set.iter().cloned().collect()
    }

    /// 检查路径是否在白名单中喵
    ///
    /// ## Arguments
    /// * `path` - 要检查的路径喵
    ///
    /// ## Returns
    /// Ok(()) = 允许喵，Err = 拒绝喵
    ///
    /// ⚠️ SAFETY: 必须检测路径遍历攻击喵
    /// 🔐 PERMISSION: 需要对文件系统访问进行安全检查喵
    pub fn check_path(&self, path: &str) -> Result<(), AllowlistError> {
        // 1. 检测路径遍历攻击喵
        if path.contains("..")
            || path.starts_with("/etc")
            || path.starts_with("/root")
            || path.contains(".ssh")
            || path.contains(".aws")
            || path.contains("password")
        {
            return Err(AllowlistError::PathTraversalAttempt(path.to_string()));
        }

        // 2. 标准化路径喵
        let normalized = PathBuf::from(path);
        let normalized_str = normalized.to_string_lossy().to_lowercase();

        // 3. 检查白名单喵
        for allowed_pattern in &self.path_set {
            if self.path_matches(&normalized_str, allowed_pattern) {
                return Ok(());
            }
        }

        if self.default_deny {
            Err(AllowlistError::PathNotAllowed(path.to_string()))
        } else {
            Ok(())
        }
    }

    /// 路径匹配检查喵（简化版 glob 匹配）
    fn path_matches(&self, path: &str, pattern: &str) -> bool {
        // 精确匹配喵
        if path == pattern {
            return true;
        }

        // 前缀匹配喵（支持递归访问喵）
        if pattern.ends_with("/**") {
            let prefix = &pattern[..pattern.len() - 3];
            if path.starts_with(prefix) {
                return true;
            }
        }

        // 后缀匹配喵
        if pattern.starts_with("**") {
            let suffix = &pattern[2..];
            if path.ends_with(suffix) {
                return true;
            }
        }

        false
    }
}

/// 默认白名单配置喵
impl Default for AllowlistConfig {
    fn default() -> Self {
        Self {
            commands: vec![
                CommandAllowlistEntry {
                    command: "git".to_string(),
                    description: "Git 版本控制".to_string(),
                    allow_args: true,
                    arg_pattern: Some(r"^[-a-zA-Z0-9_/.= ]+$".to_string()),
                },
                CommandAllowlistEntry {
                    command: "ls".to_string(),
                    description: "列出目录内容".to_string(),
                    allow_args: true,
                    arg_pattern: Some(r"^[-a-zA-Z0-9_/. ]+$".to_string()),
                },
                CommandAllowlistEntry {
                    command: "cat".to_string(),
                    description: "查看文件内容".to_string(),
                    allow_args: true,
                    arg_pattern: Some(r"^[-a-zA-Z0-9_/.]+$".to_string()),
                },
                CommandAllowlistEntry {
                    command: "grep".to_string(),
                    description: "搜索文件内容".to_string(),
                    allow_args: true,
                    arg_pattern: Some(r"^[-a-zA-Z0-9_/.= ]+$".to_string()),
                },
                CommandAllowlistEntry {
                    command: "cargo".to_string(),
                    description: "Rust 构建工具".to_string(),
                    allow_args: true,
                    arg_pattern: Some(r"^[-a-zA-Z0-9_/.= ]+$".to_string()),
                },
                CommandAllowlistEntry {
                    command: "npm".to_string(),
                    description: "Node 包管理器".to_string(),
                    allow_args: true,
                    arg_pattern: Some(r"^[-a-zA-Z0-9_/.= ]+$".to_string()),
                },
                CommandAllowlistEntry {
                    command: "echo".to_string(),
                    description: "输出文本".to_string(),
                    allow_args: true,
                    arg_pattern: Some(r"^[-a-zA-Z0-9_/.= ]+$".to_string()),
                },
                CommandAllowlistEntry {
                    command: "pwd".to_string(),
                    description: "显示当前目录".to_string(),
                    allow_args: false,
                    arg_pattern: None,
                },
                CommandAllowlistEntry {
                    command: "date".to_string(),
                    description: "显示日期时间".to_string(),
                    allow_args: false,
                    arg_pattern: None,
                },
                CommandAllowlistEntry {
                    command: "whoami".to_string(),
                    description: "显示当前用户".to_string(),
                    allow_args: false,
                    arg_pattern: None,
                },
            ],
            paths: vec![
                PathAllowlistEntry {
                    pattern: "/home/ubuntu/.openclaw/**".to_string(),
                    description: "OpenClaw 工作目录".to_string(),
                    recursive: true,
                },
                PathAllowlistEntry {
                    pattern: "/tmp/**".to_string(),
                    description: "临时文件目录".to_string(),
                    recursive: true,
                },
                PathAllowlistEntry {
                    pattern: "/var/log/**".to_string(),
                    description: "日志目录（只读）".to_string(),
                    recursive: true,
                },
            ],
            default_deny: true,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 测试命令白名单检查喵
    #[tokio::test]
    fn test_command_whitelist() {
        let config = AllowlistConfig::default();
        let service = AllowlistService::new(config);

        // 测试允许的命令喵
        assert!(service.check_command("git").is_ok());
        assert!(service.check_command("ls").is_ok());
        assert!(service.check_command("cat").is_ok());

        // 测试拒绝的命令喵
        assert!(service.check_command("rm").is_err());
        assert!(service.check_command("chmod").is_err());
        assert!(service.check_command("sudo").is_err());
    }

    /// 测试路径白名单检查喵
    #[tokio::test]
    fn test_path_whitelist() {
        let config = AllowlistConfig::default();
        let service = AllowlistService::new(config);

        // 测试允许的路径喵
        assert!(service
            .check_path("/home/ubuntu/.openclaw/workspace")
            .is_ok());
        assert!(service.check_path("/tmp/test.txt").is_ok());

        // 测试拒绝的路径喵
        assert!(service.check_path("/etc/passwd").is_err());
        assert!(service.check_path("/root/.ssh/id_rsa").is_err());

        // 测试路径遍历攻击喵
        assert!(service
            .check_path("/home/ubuntu/.openclaw/../../../etc/passwd")
            .is_err());
    }
}
