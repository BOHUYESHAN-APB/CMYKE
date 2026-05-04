//! # UUID Tool
//!
//! UUID 工具喵！
//!
//! 功能：生成随机 UUID（v4）
//!
//! @诺诺 的第二个工具实现喵

use super::mcp::{Tool, ToolDescription, ToolError, ToolResult};
use serde_json::{json, Value};
use uuid::Uuid;

/// 🔒 SAFETY: UUID 工具喵
///
/// 功能：生成随机 UUID（v4）
///
/// # 示例
///
/// ```ignore
/// let tool = UuidTool;
/// let result = tool.execute(json!({})).await?;
/// let uuid = result.data["uuid"].as_str().unwrap();
/// ```
#[derive(Debug, Clone)]
pub struct UuidTool;

impl UuidTool {
    /// 🔒 SAFETY: 创建新的 UUID 工具实例喵
    pub fn new() -> Self {
        Self
    }
}

impl Default for UuidTool {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl Tool for UuidTool {
    /// 🔒 SAFETY: 获取工具描述喵
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "uuid".to_string(),
            description: "生成随机 UUID（v4）".to_string(),
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
    /// UUID 工具不需要任何参数
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
    /// 返回：{"uuid": "550e8400-e29b-41d4-a716-446655440000", "success": true}
    ///
    /// # 错误
    ///
    /// 理论上不应该失败，UUID 生成是纯函数
    async fn execute(&self, _input: Value) -> Result<ToolResult, ToolError> {
        let start = std::time::Instant::now();

        // 生成 UUID v4
        let uuid = Uuid::new_v4();

        Ok(ToolResult {
            success: true,
            data: Some(json!({
                "uuid": uuid.to_string(),
                "version": 4,
                "format": "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
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
    async fn test_uuid_tool() {
        let tool = UuidTool::new();

        // 测试工具描述
        let description = tool.describe();
        assert_eq!(description.name, "uuid");
        assert!(description.description.contains("UUID"));
        assert!(!description.dangerous);

        // 测试输入验证
        assert!(tool.validate_input(&json!({})).is_ok());

        // 测试执行
        let result = tool.execute(json!({})).await.unwrap();
        assert!(result.success);

        // 验证 UUID 格式
        let uuid = result.data.as_ref().unwrap()["uuid"].as_str().unwrap();
        let parsed = Uuid::parse_str(uuid).unwrap();
        assert_eq!(parsed.get_version_num(), 4); // v4 UUID

        // 验证返回的结构
        assert!(result.data.as_ref().unwrap()["version"].is_number());
        assert_eq!(result.data.as_ref().unwrap()["version"], 4);
        assert!(result.data.as_ref().unwrap()["format"].is_string());
    }

    #[tokio::test]
    async fn test_uuid_uniqueness() {
        let tool = UuidTool::new();

        // 测试 UUID 唯一性
        let result1 = tool.execute(json!({})).await.unwrap();
        let result2 = tool.execute(json!({})).await.unwrap();

        let uuid1 = result1.data.as_ref().unwrap()["uuid"].as_str().unwrap();
        let uuid2 = result2.data.as_ref().unwrap()["uuid"].as_str().unwrap();

        // 两个 UUID 应该不同
        assert_ne!(uuid1, uuid2);
    }
}
