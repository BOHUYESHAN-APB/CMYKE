//! # SHA256 Hash Tool
//!
//! SHA256 哈希工具喵！
//!
//! 功能：计算字符串或二进制数据的 SHA256 哈希值
//!
//! @诺诺 的第四个工具实现喵

use super::mcp::{Tool, ToolDescription, ToolError, ToolResult};
use serde_json::{json, Value};
use sha2::{Sha256, Digest};

/// 🔒 SAFETY: SHA256 哈希工具喵
///
/// 功能：计算字符串的 SHA256 哈希值
///
/// # 示例
///
/// ```ignore
/// let tool = Sha256Tool;
/// let result = tool.execute(json!({"data": "hello"})).await?;
/// let hash = result.data["hash"].as_str().unwrap();
/// ```
#[derive(Debug, Clone)]
pub struct Sha256Tool;

impl Sha256Tool {
    /// 🔒 SAFETY: 创建新的 SHA256 工具实例喵
    pub fn new() -> Self {
        Self
    }
}

impl Default for Sha256Tool {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl Tool for Sha256Tool {
    /// 🔒 SAFETY: 获取工具描述喵
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "hash_sha256".to_string(),
            description: "计算字符串的 SHA256 哈希值".to_string(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "data": {
                        "type": "string",
                        "description": "要计算哈希的字符串"
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

        // 计算 SHA256 哈希
        let mut hasher = Sha256::new();
        hasher.update(data.as_bytes());
        let result = hasher.finalize();

        // 转换为十六进制字符串
        let hash = format!("{:x}", result);

        Ok(ToolResult {
            success: true,
            data: Some(json!({
                "hash": hash,
                "original": data,
                "algorithm": "SHA-256",
                "length": hash.len()
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
    async fn test_sha256_tool() {
        let tool = Sha256Tool::new();

        // 测试工具描述
        let description = tool.describe();
        assert_eq!(description.name, "hash_sha256");
        assert!(description.description.contains("SHA256"));
        assert!(!description.dangerous);

        // 测试输入验证
        assert!(tool.validate_input(&json!({"data": "hello"})).is_ok());
        assert!(tool.validate_input(&json!({})).is_err());

        // 测试执行
        let result = tool.execute(json!({"data": "hello"})).await.unwrap();
        assert!(result.success);

        // 验证哈希值格式（SHA256 应该是 64 个十六进制字符）
        let hash = result.data.as_ref().unwrap()["hash"].as_str().unwrap();
        assert_eq!(hash.len(), 64);
        assert!(hash.chars().all(|c| c.is_ascii_hexdigit()));

        // 验证返回的结构
        assert_eq!(result.data.as_ref().unwrap()["original"], "hello");
        assert_eq!(result.data.as_ref().unwrap()["algorithm"], "SHA-256");
        assert!(result.data.as_ref().unwrap()["length"].is_number());
    }

    #[tokio::test]
    async fn test_sha256_deterministic() {
        let tool = Sha256Tool::new();

        // 相同的输入应该产生相同的哈希
        let result1 = tool.execute(json!({"data": "test"})).await.unwrap();
        let result2 = tool.execute(json!({"data": "test"})).await.unwrap();

        let hash1 = result1.data.as_ref().unwrap()["hash"].as_str().unwrap();
        let hash2 = result2.data.as_ref().unwrap()["hash"].as_str().unwrap();

        assert_eq!(hash1, hash2);
    }

    #[tokio::test]
    async fn test_sha256_avalanche_effect() {
        let tool = Sha256Tool::new();

        // 不同的输入应该产生完全不同的哈希
        let result1 = tool.execute(json!({"data": "cat"})).await.unwrap();
        let result2 = tool.execute(json!({"data": "dog"})).await.unwrap();

        let hash1 = result1.data.as_ref().unwrap()["hash"].as_str().unwrap();
        let hash2 = result2.data.as_ref().unwrap()["hash"].as_str().unwrap();

        // 哈希值应该完全不同（比特差异率应该接近 50%）
        assert_ne!(hash1, hash2);

        // 计算比特差异
        let diff_bits = hash1.bytes()
            .zip(hash2.bytes())
            .filter(|(a, b)| a != b)
            .count();

        // 应该至少有一定数量的比特差异
        assert!(diff_bits > 20, "Avalanche effect not significant: {} bits differ", diff_bits);
    }
}
