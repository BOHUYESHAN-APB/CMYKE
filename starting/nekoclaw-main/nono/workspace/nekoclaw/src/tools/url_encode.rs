//! # URL Encode Tool
//!
//! URL 编码工具喵！
//!
//! 功能：将字符串进行 URL 编码（百分比编码）
//!
//! @诺诺 的第五个工具实现喵

use super::mcp::{Tool, ToolDescription, ToolError, ToolResult};
use serde_json::{json, Value};
use percent_encoding::{utf8_percent_encode, AsciiSet, CONTROLS};

/// 🔒 SAFETY: URL 编码字符集喵
///
/// 保留除字母数字以外需要编码的字符
const FRAGMENT: &AsciiSet = &CONTROLS
    .add(b' ')
    .add(b'"')
    .add(b'<')
    .add(b'>')
    .add(b'`')
    .add(b'%'); // 确保 % 也被编码避免重复编码

/// 🔒 SAFETY: URL 编码工具喵
///
/// 功能：将字符串进行 URL 编码
///
/// # 示例
///
/// ```ignore
/// let tool = UrlEncodeTool;
/// let result = tool.execute(json!({"data": "hello world"})).await?;
/// let encoded = result.data["encoded"].as_str().unwrap();
/// ```
#[derive(Debug, Clone)]
pub struct UrlEncodeTool;

impl UrlEncodeTool {
    /// 🔒 SAFETY: 创建新的 URL 编码工具实例喵
    pub fn new() -> Self {
        Self
    }
}

impl Default for UrlEncodeTool {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl Tool for UrlEncodeTool {
    /// 🔒 SAFETY: 获取工具描述喵
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "url_encode".to_string(),
            description: "将字符串进行 URL 编码（百分比编码）".to_string(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "data": {
                        "type": "string",
                        "description": "要编码的字符串"
                    }
                },
                "required": ["data"]
            }),
            category: Some("utility".to_string()),
            dangerous: false,
            required_permissions: None,
        }
    }

    /// 🔒 SAFETY: 验证输入参数喵
    fn validate_input(&self, input: &Value) -> Result<(), ToolError> {
        if !input.is_object() {
            return Err(ToolError::ValidationError(
                "Input must be a JSON object".to_string(),
            ));
        }

        if input.get("data").is_none() {
            return Err(ToolError::ValidationError(
                "Missing required field: 'data'".to_string(),
            ));
        }

        if let Some(data) = input.get("data") {
            if !data.is_string() {
                return Err(ToolError::ValidationError(
                    "'data' must be a string".to_string(),
                ));
            }
        }

        Ok(())
    }

    /// 🔒 SAFETY: 执行工具喵
    async fn execute(&self, input: Value) -> Result<ToolResult, ToolError> {
        let start = std::time::Instant::now();

        let data = input["data"].as_str().ok_or_else(|| {
            ToolError::ValidationError("'data' field is missing or invalid".to_string())
        })?;

        // URL 编码
        let encoded = utf8_percent_encode(data, FRAGMENT).to_string();

        Ok(ToolResult {
            success: true,
            data: Some(json!({
                "encoded": encoded,
                "original": data,
                "length": encoded.len()
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
    async fn test_url_encode_tool() {
        let tool = UrlEncodeTool::new();

        // 测试工具描述
        let description = tool.describe();
        assert_eq!(description.name, "url_encode");
        assert!(description.description.contains("URL"));
        assert!(!description.dangerous);

        // 测试输入验证
        assert!(tool.validate_input(&json!({"data": "hello"})).is_ok());
        assert!(tool.validate_input(&json!({})).is_err());

        // 测试执行（空格编码）
        let result = tool.execute(json!({"data": "hello world"})).await.unwrap();
        assert!(result.success);

        let encoded = result.data.as_ref().unwrap()["encoded"].as_str().unwrap();
        assert_eq!(encoded, "hello%20world");
    }

    #[tokio::test]
    async fn test_url_encode_special_chars() {
        let tool = UrlEncodeTool::new();

        // 测试特殊字符编码
        let result = tool.execute(json!({"data": "hello@example.com?test=1"})).await.unwrap();
        let encoded = result.data.as_ref().unwrap()["encoded"].as_str().unwrap();

        assert_eq!(encoded, "hello%40example.com%3Ftest=1");
    }

    #[tokio::test]
    async fn test_url_encode_chinese() {
        let tool = UrlEncodeTool::new();

        // 测试中文编码
        let result = tool.execute(json!({"data": "诺诺"})).await.unwrap();
        let encoded = result.data.as_ref().unwrap()["encoded"].as_str().unwrap();

        // 中文字符应该被编码
        assert_ne!(encoded, "诺诺");
    }
}
