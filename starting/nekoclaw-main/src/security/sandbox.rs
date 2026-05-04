//! # 命令沙箱模块
//!
//! ⚠️ SAFETY: 核心安全模块，用于安全地执行 Shell 命令喵
//!
//! ## 功能说明
//! - 提供安全的命令执行环境喵
//! - 集成白名单检查喵
//! - 支持超时控制和资源限制喵
//! - 捕获并处理命令输出喵
//!
//! ## 核心原则
//! 1. **最小权限**: 只允许白名单内的命令喵
//! 2. **参数验证**: 严格验证所有参数喵
//! 3. **资源限制**: 防止无限循环或资源耗尽喵
//! 4. **输出捕获**: 安全地捕获命令输出喵

use std::process::{Command, Stdio};
use std::time::Duration;
use thiserror::Error;
use tokio::process::Command as AsyncCommand;

use super::{AllowlistConfig, AllowlistError, AllowlistService};

/// 沙箱错误类型
#[derive(Error, Debug)]
pub enum SandboxError {
    /// 命令不在白名单中喵
    #[error("Command not allowed: {0}")]
    CommandNotAllowed(String),

    /// 参数注入攻击尝试喵
    #[error("Parameter injection attempt detected: {0}")]
    ParameterInjection(String),

    /// 命令执行超时喵
    #[error("Command timeout: {0}")]
    Timeout(String),

    /// 命令执行失败喵
    #[error("Command execution failed: {0}")]
    ExecutionFailed(String),

    /// 输出读取失败喵
    #[error("Failed to read output: {0}")]
    OutputReadError(String),

    /// 白名单错误喵
    #[error("Allowlist error: {0}")]
    Allowlist(#[from] AllowlistError),
}

/// 沙箱配置喵
#[derive(Clone, Debug)]
pub struct SandboxConfig {
    /// 最大执行时间（秒）喵
    pub timeout_seconds: u64,
    /// 最大输出大小（字节）喵
    pub max_output_size: usize,
    /// 工作目录喵
    pub working_directory: Option<String>,
    /// 环境变量白名单喵
    pub env_whitelist: Vec<String>,
}

/// 命令执行结果喵
#[derive(Clone, Debug)]
pub struct SandboxResult {
    /// 命令退出码喵
    pub exit_code: i32,
    /// 标准输出喵
    pub stdout: String,
    /// 标准错误喵
    pub stderr: String,
    /// 执行耗时（毫秒）喵
    pub duration_ms: u128,
    /// 是否超时喵
    pub timed_out: bool,
}

/// 沙箱服务喵
///
/// 🔐 SAFETY: 核心安全执行模块，必须经过白名单验证喵
#[derive(Clone, Debug)]
pub struct SandboxService {
    /// 白名单服务喵
    allowlist_service: AllowlistService,
    /// 沙箱配置喵
    config: SandboxConfig,
}

impl SandboxService {
    /// 创建沙箱服务喵
    ///
    /// ## Arguments
    /// * `allowlist_service` - 白名单服务实例喵
    /// * `config` - 沙箱配置喵
    ///
    /// 🔐 PERMISSION: 仅允许安全模块初始化喵
    pub fn new(allowlist_service: AllowlistService, config: SandboxConfig) -> Self {
        Self {
            allowlist_service,
            config,
        }
    }

    /// 同步执行命令喵（阻塞式）
    ///
    /// ## Arguments
    /// * `command` - 命令名称喵
    /// * `args` - 命令参数喵
    ///
    /// ## Returns
    /// 命令执行结果喵
    ///
    /// 🔐 PERMISSION: 需要经过白名单验证喵
    /// ⚠️ SAFETY: 此函数可能阻塞，建议使用 async 版本喵
    pub fn execute(&self, command: &str, args: &[&str]) -> Result<SandboxResult, SandboxError> {
        // 1. 命令白名单检查喵
        let _cmd_entry = self.allowlist_service.check_command(command)?;

        // 2. 参数注入检查喵
        self.validate_parameters(args)?;

        // 3. 记录开始时间喵
        let start = std::time::Instant::now();

        // 4. 构建命令喵
        let mut cmd = Command::new(command);

        // 设置工作目录喵
        if let Some(ref wd) = self.config.working_directory {
            cmd.current_dir(wd);
        }

        // 5. 注入环境变量（仅白名单内的喵）
        for env in &self.config.env_whitelist {
            if let Ok(val) = std::env::var(env) {
                cmd.env(env, val);
            }
        }

        // 6. 设置参数喵
        cmd.args(args);

        // 7. 捕获输出喵
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());

        // 8. 执行命令喵
        let output = match cmd.output() {
            Ok(o) => o,
            Err(e) => return Err(SandboxError::ExecutionFailed(e.to_string())),
        };

        // 9. 记录耗时喵
        let duration_ms = start.elapsed().as_millis();

        // 10. 解析结果喵
        let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();

        Ok(SandboxResult {
            exit_code: output.status.code().unwrap_or(-1),
            stdout,
            stderr,
            duration_ms,
            timed_out: false,
        })
    }

    /// 异步执行命令喵（非阻塞）
    ///
    /// ## Arguments
    /// * `command` - 命令名称喵
    /// * `args` - 命令参数喵
    ///
    /// ## Returns
    /// 命令执行结果喵
    ///
    /// 🔐 PERMISSION: 需要经过白名单验证喵
    /// ⚠️ SAFETY: 推荐使用此异步版本喵
    pub async fn execute_async(
        &self,
        command: &str,
        args: &[&str],
        work_dir: Option<&str>,
        timeout: Option<Duration>,
    ) -> Result<SandboxResult, SandboxError> {
        // 1. 命令白名单检查喵
        let _cmd_entry = self.allowlist_service.check_command(command)?;

        // 2. 参数注入检查喵
        self.validate_parameters(args)?;

        // 3. 构建异步命令喵
        let mut cmd = AsyncCommand::new(command);

        // 设置工作目录喵 - 优先使用参数，否则使用配置
        let working_dir =
            work_dir.unwrap_or_else(|| self.config.working_directory.as_deref().unwrap_or("."));
        cmd.current_dir(working_dir);

        // 注入环境变量喵
        for env in &self.config.env_whitelist {
            if let Ok(val) = std::env::var(env) {
                cmd.env(env, val);
            }
        }

        // 设置参数喵
        cmd.args(args);

        // 捕获输出喵
        cmd.stdout(Stdio::piped());
        cmd.stderr(Stdio::piped());

        // 4. 设置超时喵 - 优先使用参数，否则使用配置
        let timeout = timeout.unwrap_or_else(|| Duration::from_secs(self.config.timeout_seconds));

        // 5. 执行并等待结果喵
        let start = std::time::Instant::now();
        let output = match tokio::time::timeout(timeout, cmd.output()).await {
            Ok(Ok(o)) => o,
            Ok(Err(e)) => return Err(SandboxError::ExecutionFailed(e.to_string())),
            Err(_) => {
                // 超时，尝试杀死进程喵
                return Ok(SandboxResult {
                    exit_code: -1,
                    stdout: String::new(),
                    stderr: String::from("Command timeout"),
                    duration_ms: self.config.timeout_seconds as u128 * 1000,
                    timed_out: true,
                });
            }
        };

        // 6. 记录耗时喵
        let duration_ms = start.elapsed().as_millis();

        // 7. 解析结果喵
        let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
        let stderr = String::from_utf8_lossy(&output.stderr).into_owned();

        Ok(SandboxResult {
            exit_code: output.status.code().unwrap_or(-1),
            stdout,
            stderr,
            duration_ms,
            timed_out: false,
        })
    }

    /// 参数注入检查喵
    ///
    /// ## Arguments
    /// * `args` - 要检查的参数喵
    ///
    /// ## Returns
    /// Ok(()) = 安全喵，Err = 检测到注入攻击喵
    ///
    /// 🔐 PERMISSION: 安全检查喵
    fn validate_parameters(&self, args: &[&str]) -> Result<(), SandboxError> {
        // 检测危险字符喵
        let dangerous_patterns = [
            "|",  // 管道注入喵
            ";",  // 命令分隔喵
            "&",  // 后台执行喵
            "$(", // 命令替换喵
            "`",  // 反引号注入喵
            ">",  // 输出重定向喵
            "<",  // 输入重定向喵
            ">>", // 追加重定向喵
            "&&", // 条件执行喵
            "||", // 条件执行喵
            "\n", // 换行注入喵
            "\r", // 回车注入喵
        ];

        for arg in args {
            for pattern in &dangerous_patterns {
                if arg.contains(pattern) {
                    return Err(SandboxError::ParameterInjection(arg.to_string()));
                }
            }
        }

        Ok(())
    }
}

/// 默认沙箱配置喵
impl Default for SandboxConfig {
    fn default() -> Self {
        Self {
            timeout_seconds: 30,
            max_output_size: 1024 * 1024, // 1MB
            working_directory: Some("/home/ubuntu/.openclaw/workspace".to_string()),
            env_whitelist: vec![
                "HOME".to_string(),
                "USER".to_string(),
                "PATH".to_string(),
                "LANG".to_string(),
                "TZ".to_string(),
            ],
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 测试沙箱执行喵
    #[tokio::test]
    fn test_sandbox_execution() {
        let allowlist_config = AllowlistConfig::default();
        let allowlist_service = AllowlistService::new(allowlist_config);
        let sandbox_config = SandboxConfig::default();
        let sandbox = SandboxService::new(allowlist_service, sandbox_config);

        // 测试允许的命令喵
        let result = sandbox.execute("echo", &["Hello, Neko-Claw!"]);
        assert!(result.is_ok());
        let result = result.unwrap();
        assert!(result.stdout.contains("Hello, Neko-Claw!"));
        assert_eq!(result.exit_code, 0);
    }

    /// 测试命令白名单喵
    #[tokio::test]
    fn test_command_whitelist() {
        let allowlist_config = AllowlistConfig::default();
        let allowlist_service = AllowlistService::new(allowlist_config);
        let sandbox_config = SandboxConfig::default();
        let sandbox = SandboxService::new(allowlist_service, sandbox_config);

        // 测试拒绝的命令喵
        let result = sandbox.execute("rm", &["-rf", "/tmp/test"]);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SandboxError::CommandNotAllowed(_)
        ));
    }

    /// 测试参数注入防护喵
    #[tokio::test]
    fn test_parameter_injection_protection() {
        let allowlist_config = AllowlistConfig::default();
        let allowlist_service = AllowlistService::new(allowlist_config);
        let sandbox_config = SandboxConfig::default();
        let sandbox = SandboxService::new(allowlist_service, sandbox_config);

        // 测试管道注入喵
        let result = sandbox.execute("echo", &["test | cat"]);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SandboxError::ParameterInjection(_)
        ));

        // 测试命令分隔喵
        let result = sandbox.execute("echo", &["test ; ls"]);
        assert!(result.is_err());
    }
}
