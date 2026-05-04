//! # Timestamp Tool
//!
//! 时间戳工具喵！
//!
//! 功能：返回当前 Unix 时间戳（秒）
//!
//! @诺诺 的第一个工具实现喵

use super::mcp::{Tool, ToolDescription, ToolError, ToolResult};
use serde_json::{json, Value};
use std::time::{SystemTime, UNIX_EPOCH};

/// 🔒 SAFETY: Timestamp 工具喵
///
/// 功能：获取当前的 Unix 时间戳（秒）
///
/// # 示例
///
/// ```ignore
/// let tool = TimestampTool;
/// let result = tool.execute(json!({})).await?;
/// ```
#[derive(Debug, Clone)]
pub struct TimestampTool;

impl TimestampTool {
    /// 🔒 SAFETY: 创建新的 Timestamp 工具实例喵
    pub fn new() -> Self {
        Self
    }
}

impl Default for TimestampTool {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl Tool for TimestampTool {
    /// 🔒 SAFETY: 获取工具描述喵
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "timestamp".to_string(),
            description: "获取当前 Unix 时间戳（秒）".to_string(),
            input_schema: json!({
                "type": "object",
                "properties": {},
                "required": []
            }),
            category: Some("utility".to_string()),
            dangerous: false,
            required_permissions: None,
        }
    }

    /// 🔒 SAFETY: 验证输入参数喵
    ///
    /// Timestamp 工具不需要任何参数
    fn validate_input(&self, input: &Value) -> Result<(), ToolError> {
        if !input.is_object() {
            return Err(ToolError::ValidationError(
                "Input must be a JSON object".to_string(),
            ));
        }
        Ok(())
    }

    /// 🔒 SAFETY: 执行工具喵
    ///
    /// 返回：{"timestamp": 1234567890, "success": true}
    ///
    /// # 错误
    ///
    /// 理论上不应该失败，如果 SystemTime 溢出则返回错误
    async fn execute(&self, _input: Value) -> Result<ToolResult, ToolError> {
        let start = std::time::Instant::now();

        // 获取当前系统时间
        let duration = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| ToolError::ExecutionFailed(format!("获取系统时间失败: {}", e)))?;

        // 转换为秒
        let timestamp = duration.as_secs();

        Ok(ToolResult {
            success: true,
            data: Some(json!({
                "timestamp": timestamp,
                "unit": "seconds"
            })),
            error: None,
            duration_ms: Some(start.elapsed().as_millis() as u64),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_timestamp_tool() {
        let tool = TimestampTool::new();

        // 测试工具描述
        let description = tool.describe();
        assert_eq!(description.name, "timestamp");
        assert!(description.description.contains("时间戳"));
        assert!(!description.dangerous);

        // 测试输入验证
        assert!(tool.validate_input(&json!({})).is_ok());

        // 测试执行
        let result = tool.execute(json!({})).await.unwrap();
        assert!(result.success);

        // 验证时间戳格式
        let timestamp = result.data["timestamp"].as_u64().unwrap();
        assert!(timestamp > 1000000000); // 时间戳应该大于 2001 年

        // 验证返回的结构
        assert!(result.data["unit"].is_string());
        assert_eq!(result.data["unit"], "seconds");
    }

    #[tokio::test]
    async fn test_timestamp_format() {
        let tool = TimestampTool::new();
        let result = tool.execute(json!({})).await.unwrap();

        let result_json = serde_json::to_string_pretty(&result).unwrap();
        println!("{}", result_json);
    }
}
