//! # MCP Adapter for Shell Tool
//!
//! 🔧 将现有的 Shell 工具适配为 MCP 兼容的工具
//!
//! @诺诺 的 MCP 适配器实现喵
//!
//! ## 功能
//! - ShellTool → MCP Tool 转换
//! - 参数 schema 生成
//! - 结果格式化
//!
//! 🔒 SAFETY: 保留所有安全检查
//!
//! Author: 诺诺 (Nono) ⚡

use super::mcp::{Tool, ToolDescription, ToolError, ToolResult};
use super::shell::{ShellError, ShellRequest, ShellTool};
use serde_json::json;

/// 🔒 SAFETY: MCP 兼容的 Shell 工具喵
pub struct McpShellTool {
    inner: ShellTool,
}

impl McpShellTool {
    /// 🔒 SAFETY: 从 ShellTool 创建 MCP 工具喵
    pub fn new(shell_tool: ShellTool) -> Self {
        Self { inner: shell_tool }
    }

    /// 🔒 SAFETY: 获取内部 ShellTool 引用喵
    pub fn inner(&self) -> &ShellTool {
        &self.inner
    }
}

#[async_trait::async_trait]
impl Tool for McpShellTool {
    /// 🔒 SAFETY: 获取工具描述喵
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "shell".to_string(),
            description: "Execute shell commands in a safe sandbox. Commands must be in the allowlist.".to_string(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "Command to execute (must be in allowlist)"
                    },
                    "args": {
                        "type": "array",
                        "items": {
                            "type": "string"
                        },
                        "description": "Command arguments"
                    },
                    "timeout": {
                        "type": "integer",
                        "description": "Timeout in seconds (default: 30)",
                        "default": 30
                    }
                },
                "required": ["command"]
            }),
            category: Some("system".to_string()),
            dangerous: true,
            required_permissions: Some(vec!["shell.execute".to_string()]),
        }
    }

    /// 🔒 SAFETY: 验证输入参数喵
    fn validate_input(&self, input: &serde_json::Value) -> Result<(), ToolError> {
        // 检查必需字段
        if !input.is_object() {
            return Err(ToolError::ValidationError(
                "Input must be a JSON object".to_string(),
            ));
        }

        if input.get("command").is_none() {
            return Err(ToolError::ValidationError(
                "Missing required field: 'command'".to_string(),
            ));
        }

        // 验证 command 字段
        if let Some(cmd) = input.get("command") {
            if !cmd.is_string() {
                return Err(ToolError::ValidationError(
                    "'command' must be a string".to_string(),
                ));
            }
        }

        // 验证 args 字段
        if let Some(args) = input.get("args") {
            if !args.is_array() {
                return Err(ToolError::ValidationError(
                    "'args' must be an array".to_string(),
                ));
            }
        }

        // 验证 timeout 字段
        if let Some(timeout) = input.get("timeout") {
            if !timeout.is_number() {
                return Err(ToolError::ValidationError(
                    "'timeout' must be a number".to_string(),
                ));
            }
        }

        Ok(())
    }

    /// 🔒 SAFETY: 执行工具喵
    async fn execute(&self, input: serde_json::Value) -> Result<ToolResult, ToolError> {
        let start = std::time::Instant::now();

        // 解析输入
        let command = input
            .get("command")
            .and_then(|c| c.as_str())
            .ok_or_else(|| ToolError::ValidationError("Missing 'command' field".to_string()))?;

        let args: Vec<String> = input
            .get("args")
            .and_then(|a| a.as_array())
            .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
            .unwrap_or_default();

        let timeout_secs: u64 = input
            .get("timeout")
            .and_then(|t| t.as_u64())
            .unwrap_or(30);

        // 创建 ShellRequest
        let mut request = ShellRequest::default();
        request.command = command.to_string();
        request.args = args;
        request.timeout_secs = timeout_secs;

        // 执行
        let shell_result = self.inner.execute(request).await.map_err(|e| {
            ToolError::ExecutionFailed(match e {
                ShellError::CommandNotAllowed(cmd) => {
                    format!("Command '{}' is not in allowlist", cmd)
                }
                ShellError::ExecutionFailed(msg) => format!("Execution failed: {}", msg),
                ShellError::Timeout(secs) => format!("Command timed out after {}s", secs),
                ShellError::PathTraversal => "Path traversal detected".to_string(),
                ShellError::Io(err) => format!("IO error: {}", err),
            })
        })?;

        // 转换结果
        let data = json!({
            "exit_code": shell_result.exit_code,
            "stdout": shell_result.stdout,
            "stderr": shell_result.stderr,
            "duration_ms": shell_result.duration_ms,
            "success": shell_result.success
        });

        Ok(ToolResult::success(data, start.elapsed().as_millis() as u64))
    }
}

/// 🔒 SAFETY: Echo 工具（测试用）喵
pub struct EchoTool;

#[async_trait::async_trait]
impl Tool for EchoTool {
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "echo".to_string(),
            description: "Echo the input message back. Safe for testing.".to_string(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "message": {
                        "type": "string",
                        "description": "Message to echo back"
                    }
                },
                "required": ["message"]
            }),
            category: Some("test".to_string()),
            dangerous: false,
            required_permissions: None,
        }
    }

    fn validate_input(&self, input: &serde_json::Value) -> Result<(), ToolError> {
        if !input.is_object() {
            return Err(ToolError::ValidationError(
                "Input must be a JSON object".to_string(),
            ));
        }

        if input.get("message").is_none() {
            return Err(ToolError::ValidationError(
                "Missing required field: 'message'".to_string(),
            ));
        }

        Ok(())
    }

    async fn execute(&self, input: serde_json::Value) -> Result<ToolResult, ToolError> {
        let start = std::time::Instant::now();

        let message = input
            .get("message")
            .and_then(|m| m.as_str())
            .ok_or_else(|| ToolError::ValidationError("Invalid 'message' field".to_string()))?;

        Ok(ToolResult::success(
            json!({
                "original": message,
                "echoed": format!("Echo: {}", message)
            }),
            start.elapsed().as_millis() as u64,
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_echo_tool() {
        let tool = EchoTool;

        let input = json!({
            "message": "Hello, World!"
        });

        let result = tool.execute(input).await.unwrap();
        assert!(result.success);
        assert!(result.data.is_some());
    }

    #[test]
    fn test_validate_input() {
        let tool = EchoTool;

        // Valid input
        let valid = json!({"message": "test"});
        assert!(tool.validate_input(&valid).is_ok());

        // Missing required field
        let invalid = json!({"other": "field"});
        assert!(tool.validate_input(&invalid).is_err());
    }
}
