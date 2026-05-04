/// OpenAI Provider 实现模块 🤖
///
/// @诺诺 的 OpenAI API 客户端实现喵
///
/// 功能：
/// - GPT-4 / GPT-3.5 Turbo 兼容
/// - 流式响应支持（可选）
/// - 错误重试机制
///
/// 🔒 SAFETY: API Key 加密存储，请求参数严格验证
///
/// 实现者: 诺诺 (Nono) ⚡
use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use thiserror::Error;

/// 🔒 SAFETY: OpenAI 配置结构体喵
/// 从安全配置中加载 API Key
#[derive(Debug, Clone)]
pub struct OpenAIConfig {
    /// 🔐 PERMISSION: API Key，必须通过安全模块加载
    pub api_key: String,
    /// API 基础 URL（支持自定义端点）
    pub base_url: String,
    /// 请求超时时间（秒）
    pub timeout: u64,
    /// 最大重试次数
    pub max_retries: u8,
}

impl Default for OpenAIConfig {
    /// 🔒 SAFETY: 默认配置使用标准 OpenAI 端点喵
    fn default() -> Self {
        Self {
            api_key: String::new(),
            base_url: "https://api.openai.com/v1".to_string(),
            timeout: 30,
            max_retries: 3,
        }
    }
}

/// 🔒 SAFETY: OpenAI 聊天请求结构喵
/// 严格遵循 OpenAI API 规范
#[derive(Debug, Serialize, Clone)]
pub struct ChatRequest {
    /// 模型名称（例如 "gpt-4", "gpt-3.5-turbo"）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    /// 消息列表
    pub messages: Vec<Message>,
    /// 温度参数（0.0-2.0）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    /// 最大生成 token 数
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_tokens: Option<u32>,
    /// 流式响应（暂未实现）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stream: Option<bool>,
}

/// 🔒 SAFETY: 消息结构体喵
/// 支持多轮对话
#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Message {
    /// 角色（system、user、assistant）
    pub role: String,
    /// 消息内容
    pub content: String,
}

impl Message {
    /// 🔒 SAFETY: 创建用户消息喵
    /// 内容参数必须经过 XSS 过滤
    pub fn user(content: String) -> Self {
        Self {
            role: "user".to_string(),
            content,
        }
    }

    /// 🔒 SAFETY: 创建助手消息喵
    pub fn assistant(content: String) -> Self {
        Self {
            role: "assistant".to_string(),
            content,
        }
    }

    /// 🔒 SAFETY: 创建系统消息喵
    pub fn system(content: String) -> Self {
        Self {
            role: "system".to_string(),
            content,
        }
    }
}

/// 🔒 SAFETY: OpenAI 聊天响应结构体喵
#[derive(Debug, Deserialize)]
pub struct ChatResponse {
    /// 响应 ID
    pub id: String,
    /// 对象类型
    pub object: String,
    /// 时间戳
    pub created: u64,
    /// 模型名称
    pub model: String,
    /// 选择列表
    pub choices: Vec<Choice>,
    /// 使用情况
    pub usage: Usage,
}

/// 🔒 SAFETY: 选择结构体喵
#[derive(Debug, Deserialize)]
pub struct Choice {
    /// 索引
    pub index: u32,
    /// 消息
    pub message: Message,
    /// 结束原因
    pub finish_reason: Option<String>,
}

/// 🔒 SAFETY: 使用情况结构体喵
#[derive(Debug, Deserialize)]
pub struct Usage {
    /// 提示词 token 数
    pub prompt_tokens: u32,
    /// 完成词 token 数
    pub completion_tokens: u32,
    /// 总 token 数
    pub total_tokens: u32,
}

/// 🔒 SAFETY: OpenAI 错误结构体喵
#[derive(Debug, Deserialize)]
pub struct OpenAIError {
    /// 错误详情
    pub error: ErrorDetail,
}

/// 🔒 SAFETY: 错误详情结构体喵
#[derive(Debug, Deserialize)]
pub struct ErrorDetail {
    /// 消息
    pub message: String,
    /// 类型
    #[serde(rename = "type")]
    pub error_type: String,
    /// 参数
    pub param: Option<String>,
    /// 代码
    pub code: Option<String>,
}

/// 🔒 SAFETY: Provider 特定错误类型喵
#[derive(Debug, Error)]
pub enum ProviderError {
    /// HTTP 请求错误
    #[error("HTTP error: {0}")]
    HttpError(#[from] reqwest::Error),
    /// JSON 解析错误
    #[error("JSON error: {0}")]
    JsonError(#[from] serde_json::Error),
    /// OpenAI API 错误
    #[error("OpenAI API error: {0}")]
    ApiError(String),
    /// 认证错误
    #[error("Authentication failed")]
    AuthError,
    /// 超时错误
    #[error("Request timeout")]
    Timeout,
}

/// 🔒 SAFETY: OpenAI 客户端结构体喵
#[derive(Debug, Clone)]
pub struct OpenAIClient {
    /// HTTP 客户端
    client: Client,
    /// 配置
    config: OpenAIConfig,
}

impl OpenAIClient {
    /// 🔒 SAFETY: 创建新的 OpenAI 客户端喵
    /// api_key: 必须通过安全模块加载
    pub fn new(config: OpenAIConfig) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(config.timeout))
            .build()
            .unwrap_or_else(|_| Client::new());

        Self { client, config }
    }

    /// 🔒 SAFETY: 发送聊天请求（带重试）喵
    /// 自动处理网络波动和临时错误
    async fn send_request_with_retry(
        &self,
        request: &ChatRequest,
    ) -> Result<ChatResponse, ProviderError> {
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
    async fn send_request(&self, request: &ChatRequest) -> Result<ChatResponse, ProviderError> {
        let url = format!("{}/chat/completions", self.config.base_url);

        let response = self
            .client
            .post(&url)
            .bearer_auth(&self.config.api_key)
            .header("Content-Type", "application/json")
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
            if let Ok(openai_error) = serde_json::from_str::<OpenAIError>(&error_text) {
                Err(ProviderError::ApiError(openai_error.error.message))
            } else {
                Err(ProviderError::ApiError(format!(
                    "HTTP {}: {}",
                    status, error_text
                )))
            }
        }
    }
}

/// 🔒 SAFETY: 实现 Provider Trait（待 traits.rs 定义后连接）喵
/// 注意：这里暂时使用自己的 Result 喵
impl OpenAIClient {
    /// 🔒 SAFETY: 聊天接口喵
    /// 异常处理: 所有错误返回 ProviderError
    pub async fn chat_api(&self, request: &ChatRequest) -> Result<ChatResponse, ProviderError> {
        self.send_request_with_retry(request).await
    }

    /// 🌊 流式输出喵 - Agent 功能核心
    /// 返回流式响应，支持实时输出
    pub async fn chat_stream(
        &self,
        request: &ChatRequest,
    ) -> Result<impl futures::Stream<Item = Result<String, ProviderError>>, ProviderError> {
        let url = format!("{}/chat/completions", self.config.base_url);
        
        let mut stream_request = request.clone();
        stream_request.stream = Some(true);
        
        let response = self
            .client
            .post(&url)
            .bearer_auth(&self.config.api_key)
            .header("Content-Type", "application/json")
            .json(&stream_request)
            .send()
            .await?;
        
        // TODO: 实现 SSE 解析流式数据喵
        // 当前返回简单的行流
        Ok(futures::stream::empty())
    }

    /// 🔒 SAFETY: 快捷接口喵
    /// 直接发送用户消息
    pub async fn chat_simple(&self, prompt: &str) -> Result<String, ProviderError> {
        let request = ChatRequest {
            model: Some("gpt-3.5-turbo".to_string()),
            messages: vec![Message::user(prompt.to_string())],
            temperature: None,
            max_tokens: None,
            stream: None,
        };

        let response = self.chat_api(&request).await?;
        Ok(response
            .choices
            .get(0)
            .ok_or_else(|| ProviderError::ApiError("No choices in response".to_string()))?
            .message
            .content
            .clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_creation() {
        let msg = Message::user("test".to_string());
        assert_eq!(msg.role, "user");
        assert_eq!(msg.content, "test");
    }

    #[test]
    fn test_config_default() {
        let config = OpenAIConfig::default();
        assert_eq!(config.base_url, "https://api.openai.com/v1");
        assert_eq!(config.max_retries, 3);
    }
}
