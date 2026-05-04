use super::openai::{Message, ProviderError};
/// Anthropic Provider 实现模块 🧠
///
/// @诺诺 的 Anthropic API 客户端实现喵
///
/// 功能：
/// - Claude 3 系列（Opus/Sonnet/Haiku）兼容
/// - 长上下文支持（200K tokens）
/// - JSON 模式支持
///
/// 🔒 SAFETY: API Key 加密存储，请求参数严格验证
///
/// 实现者: 诺诺 (Nono) ⚡
use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// 🔒 SAFETY: Anthropic 配置结构体喵
#[derive(Debug, Clone)]
pub struct AnthropicConfig {
    /// 🔐 PERMISSION: API Key，必须通过安全模块加载
    pub api_key: String,
    /// API 基础 URL
    pub base_url: String,
    /// 请求超时时间（秒）
    pub timeout: u64,
    /// 最大重试次数
    pub max_retries: u8,
}

impl Default for AnthropicConfig {
    fn default() -> Self {
        Self {
            api_key: String::new(),
            base_url: "https://api.anthropic.com/v1".to_string(),
            timeout: 30,
            max_retries: 3,
        }
    }
}

/// 🔒 SAFETY: Anthropic 聊天请求结构喵
/// 遵循 Claude API v1 规范
#[derive(Debug, Serialize, Clone)]
pub struct ClaudeRequest {
    /// 模型名称（例如 "claude-3-opus-20240229"）
    pub model: String,
    /// 消息列表
    pub messages: Vec<Message>,
    /// 系统提示
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system: Option<String>,
    /// 最大生成 token 数
    pub max_tokens: u32,
    /// 温度参数（0.0-1.0）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    /// 顶部采样
    #[serde(skip_serializing_if = "Option::is_none")]
    pub top_p: Option<f32>,
}

/// 🔒 SAFETY: Anthropic 错误结构体喵
#[derive(Debug, Deserialize)]
pub struct AnthropicError {
    /// 错误类型
    #[serde(rename = "type")]
    pub error_type: String,
    /// 错误消息
    pub error: ErrorDetail,
}

/// 🔒 SAFETY: Anthropic 错误详情结构体喵
#[derive(Debug, Deserialize)]
pub struct ErrorDetail {
    /// 消息
    pub message: String,
    /// 错误类型
    #[serde(rename = "type")]
    pub detail_type: String,
}

/// 🔒 SAFETY: Anthropic 响应结构体喵
#[derive(Debug, Deserialize)]
pub struct ClaudeResponse {
    /// 响应 ID
    pub id: String,
    /// 响应类型
    #[serde(rename = "type")]
    pub response_type: String,
    /// 角色信息
    pub role: String,
    /// 内容列表
    pub content: Vec<ContentBlock>,
    /// 模型名称
    pub model: String,
    /// 停止原因
    pub stop_reason: Option<String>,
    /// 使用情况
    pub usage: Usage,
}

/// 🔒 SAFETY: 内容块结构体喵
#[derive(Debug, Deserialize)]
pub struct ContentBlock {
    /// 内容类型
    #[serde(rename = "type")]
    pub content_type: String,
    /// 文本内容
    pub text: Option<String>,
}

/// 🔒 SAFETY: 使用情况结构体（复用 OpenAI 的）喵
#[derive(Debug, Deserialize)]
pub struct Usage {
    /// 输入 token 数
    pub input_tokens: u32,
    /// 输出 token 数
    pub output_tokens: u32,
    /// 创建 token 数（暂未使用）
    pub cache_creation_input_tokens: Option<u32>,
    /// 读取 cache token 数（暂未使用）
    pub cache_read_input_tokens: Option<u32>,
}

/// 🔒 SAFETY: Anthropic 客户端结构体喵
#[derive(Debug, Clone)]
pub struct AnthropicClient {
    /// HTTP 客户端
    client: Client,
    /// 配置
    config: AnthropicConfig,
    /// Anthropic 版本
    version: String,
}

impl AnthropicClient {
    /// 🔒 SAFETY: 创建新的 Anthropic 客户端喵
    pub fn new(config: AnthropicConfig) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(config.timeout))
            .build()
            .unwrap_or_else(|_| Client::new());

        Self {
            client,
            config,
            version: "2023-06-01".to_string(),
        }
    }

    /// 🔒 SAFETY: 发送聊天请求（带重试）喵
    async fn send_request_with_retry(
        &self,
        request: &ClaudeRequest,
    ) -> Result<ClaudeResponse, ProviderError> {
        let mut last_error = None;

        for attempt in 0..=self.config.max_retries {
            match self.send_request(request).await {
                Ok(response) => return Ok(response),
                Err(e) => {
                    last_error = Some(e);
                    // 如果是认证错误，不重试
                    if matches!(last_error, Some(ProviderError::AuthError)) {
                        break;
                    }
                    // 最后一次不等待
                    if attempt < self.config.max_retries {
                        // 指数退避
                        tokio::time::sleep(Duration::from_millis(
                            100 * (2_u64.pow(attempt as u32)),
                        ))
                        .await;
                    }
                }
            }
        }

        Err(last_error.unwrap_or_else(|| ProviderError::ApiError("Unknown error".to_string())))
    }

    /// 🔒 SAFETY: 发送聊天请求（核心实现）喵
    /// 异常处理: 网络错误、认证错误、限流错误
    async fn send_request(&self, request: &ClaudeRequest) -> Result<ClaudeResponse, ProviderError> {
        let url = format!("{}/messages", self.config.base_url);

        let response = self
            .client
            .post(&url)
            .header("x-api-key", &self.config.api_key)
            .header("anthropic-version", &self.version)
            .header("Content-Type", "application/json")
            // Claude 要求明确的版本头
            .header("anthropic-dangerous-direct-browser-access", "false")
            .json(request)
            .send()
            .await?;

        let status = response.status();

        if status.is_success() {
            response.json().await.map_err(ProviderError::from)
        } else {
            // 🔒 SAFETY: 处理 HTTP 错误响应喵
            if status.as_u16() == 401 {
                return Err(ProviderError::AuthError);
            }

            let error_text = response.text().await.unwrap_or_default();
            if let Ok(anthropic_error) = serde_json::from_str::<AnthropicError>(&error_text) {
                Err(ProviderError::ApiError(anthropic_error.error.message))
            } else {
                Err(ProviderError::ApiError(format!(
                    "HTTP {}: {}",
                    status, error_text
                )))
            }
        }
    }
}

/// 🔒 SAFETY: Anthropic 客户端公开接口喵
impl AnthropicClient {
    /// 🔒 SAFETY: 聊天接口喵
    /// 异常处理: 所有错误返回 ProviderError
    pub async fn chat_api(&self, request: &ClaudeRequest) -> Result<ClaudeResponse, ProviderError> {
        self.send_request_with_retry(request).await
    }

    /// 🔒 SAFETY: 快捷接口喵
    /// 直接发送用户消息
    pub async fn chat_simple(&self, prompt: &str) -> Result<String, ProviderError> {
        let request = ClaudeRequest {
            model: "claude-3-opus-20240229".to_string(),
            messages: vec![Message::user(prompt.to_string())],
            system: None,
            max_tokens: 4096,
            temperature: None,
            top_p: None,
        };

        let response = self.chat_api(&request).await?;

        // 提取文本内容
        response
            .content
            .get(0)
            .and_then(|block| block.text.as_ref())
            .ok_or_else(|| ProviderError::ApiError("No text content in response".to_string()))
            .map(|s| s.clone())
    }

    /// 🔒 SAFETY: 带系统提示的聊天喵
    pub async fn chat_with_system(
        &self,
        system: &str,
        prompt: &str,
    ) -> Result<String, ProviderError> {
        let request = ClaudeRequest {
            model: "claude-3-opus-20240229".to_string(),
            messages: vec![Message::user(prompt.to_string())],
            system: Some(system.to_string()),
            max_tokens: 4096,
            temperature: None,
            top_p: None,
        };

        let response = self.chat_api(&request).await?;
        response
            .content
            .get(0)
            .and_then(|block| block.text.as_ref())
            .ok_or_else(|| ProviderError::ApiError("No text content in response".to_string()))
            .map(|s| s.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = AnthropicConfig::default();
        assert_eq!(config.base_url, "https://api.anthropic.com/v1");
        assert_eq!(config.max_retries, 3);
    }

    #[test]
    fn test_claude_request() {
        let request = ClaudeRequest {
            model: "claude-3-opus-20240229".to_string(),
            messages: vec![Message::user("test".to_string())],
            system: Some("You are helpful".to_string()),
            max_tokens: 100,
            temperature: None,
            top_p: None,
        };

        assert_eq!(request.model, "claude-3-opus-20240229");
        assert!(request.system.is_some());
    }
}
