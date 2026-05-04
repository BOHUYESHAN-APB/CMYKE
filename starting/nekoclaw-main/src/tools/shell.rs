/// Shell 工具模块 💻
///
/// @诺诺 的 Shell 命令执行工具实现喵
///
/// 功能：
/// - Shell 命令执行（白名单保护）
/// - 同步/异步执行模式
/// - 超时控制
/// - 输出捕获
///
/// 🔒 SAFETY: 所有命令必须通过 allowlist 检查，禁止任意命令执行
///
/// 实现者: 诺诺 (Nono) ⚡
use crate::security::{AllowlistService, SandboxService};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tracing::warn;

/// 🔒 SAFETY: Shell 工具错误类型喵
#[derive(Debug, Error)]
pub enum ShellError {
    /// 命令不在白名单
    #[error("Command '{0}' is not allowed")]
    CommandNotAllowed(String),
    /// 命令执行失败
    #[error("Command execution failed: {0}")]
    ExecutionFailed(String),
    /// 命令超时
    #[error("Command timed out after {0}s")]
    Timeout(u64),
    /// 路径遍历攻击（检测到 ../）
    #[error("Path traversal detected")]
    PathTraversal,
    /// IO 错误
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),
}

/// 🔒 SAFETY: Shell 执行结果结构体喵
#[derive(Debug, Serialize, Deserialize)]
pub struct ShellResult {
    /// 退出代码
    pub exit_code: i32,
    /// 标准输出
    pub stdout: String,
    /// 标准错误
    pub stderr: String,
    /// 执行时间（毫秒）
    pub duration_ms: u64,
    /// 是否成功
    pub success: bool,
}

impl ShellResult {
    /// 🔒 SAFETY: 创建成功结果喵
    pub fn success(stdout: String, stderr: String, duration_ms: u64) -> Self {
        Self {
            exit_code: 0,
            stdout,
            stderr,
            duration_ms,
            success: true,
        }
    }

    /// 🔒 SAFETY: 创建失败结果喵
    pub fn failure(exit_code: i32, stdout: String, stderr: String, duration_ms: u64) -> Self {
        Self {
            exit_code,
            stdout,
            stderr,
            duration_ms,
            success: false,
        }
    }
}

/// 🔒 SAFETY: Shell 执行请求结构体喵
#[derive(Debug, Clone)]
pub struct ShellRequest {
    /// 命令（需要经过 allowlist 检查）
    pub command: String,
    /// 参数列表（会经过沙箱参数注入防护）
    pub args: Vec<String>,
    /// 工作目录（可选）
    pub work_dir: Option<String>,
    /// 超时时间（秒，默认 30）
    pub timeout_secs: u64,
    /// 环境变量（可选，会经过白名单检查）
    pub env: Option<Vec<(String, String)>>,
}

impl Default for ShellRequest {
    fn default() -> Self {
        Self {
            command: String::new(),
            args: Vec::new(),
            work_dir: None,
            timeout_secs: 30,
            env: None,
        }
    }
}

/// 🔒 SAFETY: Shell 工具结构体喵
#[derive(Debug, Clone)]
pub struct ShellTool {
    /// Allowlist 检查器
    allowlist: Arc<AllowlistService>,
    /// 沙箱执行器
    sandbox: Arc<SandboxService>,
}

impl ShellTool {
    /// 🔒 SAFETY: 创建新的 Shell 工具喵
    pub fn new(allowlist: Arc<AllowlistService>) -> Self {
        let sandbox = Arc::new(SandboxService::new(
            (*allowlist).clone(),
            Default::default(),
        ));
        Self { allowlist, sandbox }
    }

    /// 🔒 SAFETY: 同步执行 Shell 命令喵
    /// 异常处理: 命令不在白名单、执行失败、超时
    pub async fn execute(&self, request: ShellRequest) -> Result<ShellResult, ShellError> {
        let start = std::time::Instant::now();

        // 🔍 检查命令是否在白名单
        if !self.allowlist.is_command_allowed(&request.command) {
            warn!("Command not allowed: {}", request.command);
            return Err(ShellError::CommandNotAllowed(request.command));
        }

        // 🔍 检查工作目录是否在白名单
        if let Some(ref work_dir) = request.work_dir {
            if !self.allowlist.is_path_allowed(work_dir) {
                warn!("Work directory not allowed: {}", work_dir);
                return Err(ShellError::PathTraversal);
            }
        }

        // 🔍 检查环境变量
        if let Some(ref env_vars) = request.env {
            for (key, _) in env_vars {
                if !self.allowlist.is_env_var_allowed(key) {
                    warn!("Environment variable not allowed: {}", key);
                    return Err(ShellError::ExecutionFailed(format!(
                        "Env var '{}' not allowed",
                        key
                    )));
                }
            }
        }

        // 🛡️ 使用沙箱执行命令（自动检查参数注入）
        let timeout = Duration::from_secs(request.timeout_secs);
        let args: Vec<&str> = request.args.iter().map(|s| s.as_str()).collect();
        let result = self
            .sandbox
            .execute_async(
                &request.command,
                &args,
                request.work_dir.as_deref(),
                Some(timeout),
            )
            .await
            .map_err(|e| ShellError::ExecutionFailed(e.to_string()))?;

        let duration = start.elapsed().as_millis() as u64;

        // 解析结果
        if result.exit_code == 0 {
            Ok(ShellResult::success(result.stdout, result.stderr, duration))
        } else {
            Ok(ShellResult::failure(
                result.exit_code,
                result.stdout,
                result.stderr,
                duration,
            ))
        }
    }

    /// 🔒 SAFETY: 快捷接口喵
    /// 执行简单命令（直接传入字符串）
    pub async fn execute_simple(&self, command_line: &str) -> Result<ShellResult, ShellError> {
        let parts: Vec<&str> = command_line.split_whitespace().collect();
        if parts.is_empty() {
            return Err(ShellError::ExecutionFailed("Empty command".to_string()));
        }

        let request = ShellRequest {
            command: parts[0].to_string(),
            args: parts[1..].iter().map(|s| s.to_string()).collect(),
            ..Default::default()
        };

        self.execute(request).await
    }

    /// 🔒 SAFETY: 检查命令是否允许执行喵
    /// 纯检查，不执行
    pub fn is_command_allowed(&self, command: &str) -> bool {
        self.allowlist.is_command_allowed(command)
    }

    /// 🔒 SAFETY: 获取允许的命令列表喵
    pub fn allowed_commands(&self) -> Vec<String> {
        self.allowlist.get_allowed_commands()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shell_result() {
        let success = ShellResult::success("output".to_string(), "".to_string(), 100);
        assert!(success.success);
        assert_eq!(success.exit_code, 0);

        let failure = ShellResult::failure(1, "".to_string(), "error".to_string(), 100);
        assert!(!failure.success);
        assert_eq!(failure.exit_code, 1);
    }

    #[test]
    fn test_shell_request_default() {
        let request = ShellRequest::default();
        assert!(request.command.is_empty());
        assert!(request.args.is_empty());
        assert_eq!(request.timeout_secs, 30);
    }
}
