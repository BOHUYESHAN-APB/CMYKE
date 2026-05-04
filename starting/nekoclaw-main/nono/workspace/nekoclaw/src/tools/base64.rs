//! # Base64 Tools
//!
//! Base64 编解码工具喵！
//!
//! 功能：
//! - Base64 编码：将字符串或二进制数据编码为 Base64
//! - Base64 解码：将 Base64 字符串解码为原始数据
//!
//! @诺诺 的第三个工具实现喵

use super::mcp::{Tool, ToolDescription, ToolError, ToolResult};
use serde_json::{json, Value};
use base64::{encode, decode};

/// 🔒 SAFETY: Base64 编码工具喵
///
/// 功能：将字符串编码为 Base64
///
/// # 示例
///
/// ```ignore
/// let tool = Base64EncodeTool;
/// let result = tool.execute(json!({"data": "hello"})).await?;
/// let encoded = result.data["encoded"].as_str().unwrap();
/// ```
#[derive(Debug, Clone)]
pub struct Base64EncodeTool;

impl Base64EncodeTool {
    /// 🔒 SAFETY: 创建新的 Base64 编码工具实例喵
    pub fn new() -> Self {
        Self
    }
}

impl Default for Base64EncodeTool {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl Tool for Base64EncodeTool {
    /// 🔒 SAFETY: 获取工具描述喵
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "base64_encode".to_string(),
            description: "将字符串编码为 Base64".to_string(),
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

        // Base64 编码
        let encoded = encode(data);

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

/// 🔒 SAFETY: Base64 解码工具喵
///
/// 功能：将 Base64 字符串解码为原始字符串
///
/// # 示例
///
/// ```ignore
/// let tool = Base64DecodeTool;
/// let result = tool.execute(json!({"data": "aGVsbG8="})).await?;
/// let decoded = result.data["decoded"].as_str().unwrap();
/// ```
#[derive(Debug, Clone)]
pub struct Base64DecodeTool;

impl Base64DecodeTool {
    /// 🔒 SAFETY: 创建新的 Base64 解码工具实例喵
    pub fn new() -> Self {
        Self
    }
}

impl Default for Base64DecodeTool {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl Tool for Base64DecodeTool {
    /// 🔒 SAFETY: 获取工具描述喵
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "base64_decode".to_string(),
            description: "将 Base64 字符串解码为原始字符串".to_string(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "data": {
                        "type": "string",
                        "description": "要解码的 Base64 字符串"
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

        // Base64 解码
        let decoded_bytes = decode(data).map_err(|e| {
            ToolError::ExecutionFailed(format!("Base64 解码失败: {}", e))
        })?;

        // 尝试转换为 UTF-8 字符串
        let decoded = String::from_utf8(decoded_bytes).map_err(|e| {
            ToolError::ExecutionFailed(format!("解码结果不是有效的 UTF-8 字符串: {}", e))
        })?;

        Ok(ToolResult {
            success: true,
            data: Some(json!({
                "decoded": decoded,
                "original": data,
                "length": decoded.len(),
                "is_utf8": true
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
    async fn test_base64_encode_tool() {
        let tool = Base64EncodeTool::new();

        // 测试工具描述
        let description = tool.describe();
        assert_eq!(description.name, "base64_encode");
        assert!(description.description.contains("Base64"));
        assert!(!description.dangerous);

        // 测试输入验证
        assert!(tool.validate_input(&json!({"data": "hello"})).is_ok());
        assert!(tool.validate_input(&json!({})).is_err());

        // 测试执行
        let result = tool.execute(json!({"data": "hello"})).await.unwrap();
        assert!(result.success);

        // 验证编码结果
        let encoded = result.data.as_ref().unwrap()["encoded"].as_str().unwrap();
        assert_eq!(encoded, "aGVsbG8=");

        // 验证返回的结构
        assert_eq!(result.data.as_ref().unwrap()["original"], "hello");
        assert!(result.data.as_ref().unwrap()["length"].is_number());
    }

    #[tokio::test]
    async fn test_base64_decode_tool() {
        let tool = Base64DecodeTool::new();

        // 测试工具描述
        let description = tool.describe();
        assert_eq!(description.name, "base64_decode");
        assert!(description.description.contains("Base64"));

        // 测试执行
        let result = tool.execute(json!({"data": "aGVsbG8="})).await.unwrap();
        assert!(result.success);

        // 验证解码结果
        let decoded = result.data.as_ref().unwrap()["decoded"].as_str().unwrap();
        assert_eq!(decoded, "hello");

        // 验证返回的结构
        assert_eq!(result.data.as_ref().unwrap()["original"], "aGVsbG8=");
        assert!(result.data.as_ref().unwrap()["is_utf8"], true);
    }

    #[tokio::test]
    async fn test_base64_roundtrip() {
        let encode_tool = Base64EncodeTool::new();
        let decode_tool = Base64DecodeTool::new();

        let original = "Hello, Nono! ⚡";

        // 编码
        let encode_result = encode_tool.execute(json!({"data": original})).await.unwrap();
        let encoded = encode_result.data.as_ref().unwrap()["encoded"].as_str().unwrap();

        // 解码
        let decode_result = decode_tool.execute(json!({"data": encoded})).await.unwrap();
        let decoded = decode_result.data.as_ref().unwrap()["decoded"].as_str().unwrap();

        // 验证往返
        assert_eq!(decoded, original);
    }
}
