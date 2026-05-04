//! # CSV Parse Tool
//!
//! CSV 解析工具喵！
//!
//! 功能：解析 CSV 字符串为 JSON 数组
//!
//! @诺诺 的第六个工具实现喵

use super::mcp::{Tool, ToolDescription, ToolError, ToolResult};
use serde_json::{json, Value};
use csv::{ReaderBuilder, StringRecord};
use std::io::Cursor;

/// 🔒 SAFETY: CSV 解析工具喵
///
/// 功能：解析 CSV 字符串为 JSON 数组
///
/// # 示例
///
/// ```ignore
/// let tool = CsvParseTool;
/// let result = tool.execute(json!({"data": "name,age\nAlice,30\nBob,25"})).await?;
/// let parsed = result.data["parsed"].as_array().unwrap();
/// ```
#[derive(Debug, Clone)]
pub struct CsvParseTool;

impl CsvParseTool {
    /// 🔒 SAFETY: 创建新的 CSV 解析工具实例喵
    pub fn new() -> Self {
        Self
    }
}

impl Default for CsvParseTool {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl Tool for CsvParseTool {
    /// 🔒 SAFETY: 获取工具描述喵
    fn describe(&self) -> ToolDescription {
        ToolDescription {
            name: "csv_parse".to_string(),
            description: "解析 CSV 字符串为 JSON 数组".to_string(),
            input_schema: json!({
                "type": "object",
                "properties": {
                    "data": {
                        "type": "string",
                        "description": "要解析的 CSV 字符串"
                    },
                    "has_header": {
                        "type": "boolean",
                        "description": "CSV 是否有头部行（默认 true）",
                        "default": true
                    },
                    "delimiter": {
                        "type": "string",
                        "description": "分隔符（默认为逗号）",
                        "default": ","
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

        let has_header = input["has_header"].as_bool().unwrap_or(true);
        let delimiter = match input["delimiter"].as_str() {
            Some(s) => s.chars().next().unwrap_or(','),
            None => ','
        };

        // 创建 CSV 读取器
        let reader = ReaderBuilder::new()
            .has_headers(has_header)
            .delimiter(delimiter as u8)
            .from_reader(Cursor::new(data));

        // 解析 CSV
        let mut headers = Vec::new();
        let mut records = Vec::new();

        let mut rdr = ReaderBuilder::new()
            .has_headers(has_header)
            .delimiter(delimiter as u8)
            .from_reader(Cursor::new(data));

        if has_header {
            headers = rdr.headers()
                .map_err(|e| ToolError::ExecutionFailed(format!("读取 CSV 头部失败: {}", e)))?
                .iter()
                .map(|s| s.to_string())
                .collect();
        }

        for (i, result) in rdr.records(). enumerate() {
            let record = result.map_err(|e| {
                ToolError::ExecutionFailed(format!("解析 CSV 记录 {} 失败: {}", i, e))
            })?;

            let mut json_record = serde_json::Map::new();

            if has_header && !headers.is_empty() {
                // 使用头部作为键
                for (j, field) in record.iter().enumerate() {
                    let key = if j < headers.len() {
                        &headers[j]
                    } else {
                        &format!("col{}", j)
                    };
                    json_record.insert(key.clone(), json!(field));
                }
            } else {
                // 使用索引作为键
                for (j, field) in record.iter().enumerate() {
                    json_record.insert(format!("col{}", j), json!(field));
                }
            }

            records.push(json!(json_record));
        }

        Ok(ToolResult {
            success: true,
            data: Some(json!({
                "parsed": records,
                "count": records.len(),
                "has_header": has_header,
                "headers": headers
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
    async fn test_csv_parse_tool() {
        let tool = CsvParseTool::new();

        // 测试工具描述
        let description = tool.describe();
        assert_eq!(description.name, "csv_parse");
        assert!(description.description.contains("CSV"));
        assert!(!description.dangerous);

        // 测试输入验证
        assert!(tool.validate_input(&json!({"data": "name,age\nAlice,30"})).is_ok());
        assert!(tool.validate_input(&json!({})).is_err());

        // 测试执行
        let result = tool.execute(json!({
            "data": "name,age\nAlice,30\nBob,25",
            "has_header": true
        })).await.unwrap();

        assert!(result.success);

        let parsed = result.data.as_ref().unwrap()["parsed"].as_array().unwrap();
        assert_eq!(parsed.len(), 2);

        // 验证第一条记录
        let first = &parsed[0];
        assert_eq!(first["name"], "Alice");
        assert_eq!(first["age"], "30");

        // 验证头部
        let headers = result.data.as_ref().unwrap()["headers"].as_array().unwrap();
        assert_eq!(headers[0], "name");
        assert_eq!(headers[1], "age");
    }

    #[tokio::test]
    async fn test_csv_parse_no_header() {
        let tool = CsvParseTool::new();

        let result = tool.execute(json!({
            "data": "Alice,30\nBob,25",
            "has_header": false
        })).await.unwrap();

        let parsed = result.data.as_ref().unwrap()["parsed"].as_array().unwrap();
        assert_eq!(parsed.len(), 2);

        // 验证使用索引作为键
        assert_eq!(parsed[0]["col0"], "Alice");
        assert_eq!(parsed[0]["col1"], "30");
    }
}
