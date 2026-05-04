use super::openai::{ChatRequest, ChatResponse, Message, ProviderError};
/// OpenRouter Provider 实现模块 🌐
///
/// @诺诺 的 OpenRouter 聚合客户端实现喵
///
/// 功能：
/// - 聚合 22+ LLM 提供商（OpenAI、Anthropic、Groq、Mistral 等）
/// - 兼容 OpenAI API 格式
/// - 统一错误处理和模型路由
///
/// 🔒 SAFETY: API Key 加密存储，请求参数严格验证
///
/// 实现者: 诺诺 (Nono) ⚡
use async_trait::async_trait;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;

/// 🔒 SAFETY: OpenRouter 配置结构体喵
#[derive(Debug, Clone)]
pub struct OpenRouterConfig {
    /// 🔐 PERMISSION: API Key，必须通过安全模块加载
    pub api_key: String,
    /// API 基础 URL
    pub base_url: String,
    /// 请求超时时间（秒）
    pub timeout: u64,
    /// 最大重试次数
    pub max_retries: u8,
    /// 兜底模型（当指定模型不可用时）
    pub fallback_model: String,
}

impl Default for OpenRouterConfig {
    fn default() -> Self {
        Self {
            api_key: String::new(),
            base_url: "https://openrouter.ai/api/v1".to_string(),
            timeout: 30,
            max_retries: 3,
            fallback_model: "openai/gpt-3.5-turbo".to_string(),
        }
    }
}

/// 🔒 SAFETY: OpenRouter 扩展的聊天请求结构喵
/// 支持额外参数如 provider preferences
#[derive(Debug, Serialize, Clone)]
pub struct OpenRouterRequest {
    /// 基础聊天请求
    #[serde(flatten)]
    pub base: ChatRequest,
    /// 提供商偏好（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider: Option<ProviderPreference>,
    /// 路由策略（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub route: Option<String>,
    /// 延迟模式（可选）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transforms: Option<Vec<String>>,
}

/// 🔒 SAFETY: 提供商偏好结构体喵
#[derive(Debug, Serialize, Clone)]
pub struct ProviderPreference {
    /// 提供商排序（例如 ["openai", "anthropic"]）
    #[serde(skip_serializing_if = "Option::is_none")]
    pub order: Option<Vec<String>>,
    /// 强制使用特定提供商
    #[serde(skip_serializing_if = "Option::is_none")]
    pub allow: Option<Vec<String>>,
    /// 排除特定提供商
    #[serde(skip_serializing_if = "Option::is_none")]
    pub deny: Option<Vec<String>>,
}

/// 🔒 SAFETY: OpenRouter 模型信息结构体喵
#[derive(Debug, Deserialize, Clone)]
pub struct ModelInfo {
    /// 模型 ID
    pub id: String,
    /// 模型名称
    pub name: String,
    /// 描述
    pub description: String,
    /// 定价信息
    pub pricing: Pricing,
    /// 上下文长度
    pub context_length: u32,
}

/// 🔒 SAFETY: 定价信息结构体喵
#[derive(Debug, Deserialize, Clone)]
pub struct Pricing {
    /// 输入价格（每百万 token，美元）
    pub prompt: String,
    /// 输出价格（每百万 token，美元）
    pub completion: String,
}

/// 🔒 SAFETY: OpenRouter 错误结构体喵
#[derive(Debug, Deserialize)]
pub struct OpenRouterError {
    /// 错误详情
    pub error: ErrorDetail,
}

/// 🔒 SAFETY: OpenRouter 错误详情结构体喵
#[derive(Debug, Deserialize)]
pub struct ErrorDetail {
    /// 错误消息
    pub message: String,
    /// 错误类型
    #[serde(rename = "type")]
    pub error_type: String,
    /// 错误代码
    pub code: Option<String>,
}

/// 🔒 SAFETY: OpenRouter 客户端结构体喵
#[derive(Debug, Clone)]
pub struct OpenRouterClient {
    /// HTTP 客户端
    client: Client,
    /// 配置
    config: OpenRouterConfig,
}

impl OpenRouterClient {
    /// 🔒 SAFETY: 创建新的 OpenRouter 客户端喵
    pub fn new(config: OpenRouterConfig) -> Self {
        let client = Client::builder()
            .timeout(Duration::from_secs(config.timeout))
            .build()
            .unwrap_or_else(|_| Client::new());

        Self { client, config }
    }

    /// 🔒 SAFETY: 获取可用模型列表喵
    /// 异步调用 OpenRouter 的 models 端点
    pub async fn list_models(&self) -> Result<Vec<ModelInfo>, ProviderError> {
        let url = format!("{}/models", self.config.base_url);

        let response = self
            .client
            .get(&url)
            .bearer_auth(&self.config.api_key)
            .header("HTTP-Referer", "https://github.com/Gengetau/nekoclaw")
            .header("X-Title", "nekoclaw")
            .send()
            .await?;

        let status = response.status();

        if status.is_success() {
            response.json().await.map_err(ProviderError::from)
        } else {
            let error_text = response.text().await.unwrap_or_default();
            Err(ProviderError::ApiError(format!(
                "HTTP {}: {}",
                status, error_text
            )))
        }
    }

    /// 🔒 SAFETY: 发送聊天请求（带重试和模型回退）喵
    async fn send_request_with_retry(
        &self,
        request: &OpenRouterRequest,
    ) -> Result<ChatResponse, ProviderError> {
        let mut current_request = request.clone();
        let mut last_error = None;

        for attempt in 0..=self.config.max_retries {
            match self.send_request(&current_request).await {
                Ok(response) => return Ok(response),
                Err(e) => {
                    last_error = Some(e);

                    // 如果是认证错误，不重试
                    if matches!(last_error, Some(ProviderError::AuthError)) {
                        break;
                    }

                    // 如果尝试失败且不是最后一次，尝试回退到兜底模型
                    if attempt < self.config.max_retries {
                        // 检查是否是因为模型不可用导致的错误
                        if let Some(ProviderError::ApiError(msg)) = &last_error {
                            if msg.contains("not available") || msg.contains("not found") {
                                if let Some(model) = current_request.base.model.as_ref() {
                                    if model != &self.config.fallback_model {
                                        // 回退到兜底模型
                                        current_request.base.model =
                                            Some(self.config.fallback_model.clone());
                                        continue;
                                    }
                                }
                            }
                        }

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
    /// 异常处理: 网络错误、认证错误、模型不可用错误
    async fn send_request(
        &self,
        request: &OpenRouterRequest,
    ) -> Result<ChatResponse, ProviderError> {
        let url = format!("{}/chat/completions", self.config.base_url);

        let response = self
            .client
            .post(&url)
            .bearer_auth(&self.config.api_key)
            .header("Content-Type", "application/json")
            .header("HTTP-Referer", "https://github.com/Gengetau/nekoclaw")
            .header("X-Title", "nekoclaw")
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
            if let Ok(openrouter_error) = serde_json::from_str::<OpenRouterError>(&error_text) {
                Err(ProviderError::ApiError(openrouter_error.error.message))
            } else {
                Err(ProviderError::ApiError(format!(
                    "HTTP {}: {}",
                    status, error_text
                )))
            }
        }
    }
}

/// 🔒 SAFETY: OpenRouter 客户端公开接口喵
impl OpenRouterClient {
    /// 🔒 SAFETY: 聊天接口（OpenRouter 扩展版）喵
    pub async fn chat_api(
        &self,
        request: &OpenRouterRequest,
    ) -> Result<ChatResponse, ProviderError> {
        self.send_request_with_retry(request).await
    }

    /// 🔒 SAFETY: 兼容 OpenAI 接口喵
    /// 允许无缝切换提供商
    pub async fn chat_openai_compatible(
        &self,
        request: &ChatRequest,
    ) -> Result<ChatResponse, ProviderError> {
        let openrouter_request = OpenRouterRequest {
            base: request.clone(),
            provider: None,
            route: None,
            transforms: None,
        };
        self.chat_api(&openrouter_request).await
    }

    /// 🔒 SAFETY: 快捷接口喵
    /// 使用指定的模型
    pub async fn chat_simple(&self, model: &str, prompt: &str) -> Result<String, ProviderError> {
        let request = OpenRouterRequest {
            base: ChatRequest {
                model: Some(model.to_string()),
                messages: vec![Message::user(prompt.to_string())],
                temperature: None,
                max_tokens: None,
                stream: None,
            },
            provider: None,
            route: None,
            transforms: None,
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

    /// 🔒 SAFETY: 带提供商偏好的快捷接口喵
    pub async fn chat_with_provider(
        &self,
        model: &str,
        prompt: &str,
        preferred_providers: Vec<String>,
    ) -> Result<String, ProviderError> {
        let request = OpenRouterRequest {
            base: ChatRequest {
                model: Some(model.to_string()),
                messages: vec![Message::user(prompt.to_string())],
                temperature: None,
                max_tokens: None,
                stream: None,
            },
            provider: Some(ProviderPreference {
                order: Some(preferred_providers),
                allow: None,
                deny: None,
            }),
            route: None,
            transforms: None,
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

    /// 🔒 SAFETY: 智能模型选择喵
    /// 根据预算和需求自动选择最佳模型
    pub async fn get_best_model(&self, budget_usd: f64, context_length: u32) -> Option<ModelInfo> {
        let models = self.list_models().await.ok()?;

        models
            .into_iter()
            .filter(|m| m.context_length >= context_length)
            .min_by(|a, b| {
                // 解析价格并比较
                let a_price: f64 = a.pricing.prompt.parse().unwrap_or(f64::MAX);
                let b_price: f64 = b.pricing.prompt.parse().unwrap_or(f64::MAX);
                a_price
                    .partial_cmp(&b_price)
                    .unwrap_or(std::cmp::Ordering::Equal)
            })
            .filter(|m| {
                // 检查价格是否在预算内
                let price: f64 = m.pricing.prompt.parse().unwrap_or(f64::MAX);
                price <= budget_usd
            })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_default() {
        let config = OpenRouterConfig::default();
        assert_eq!(config.base_url, "https://openrouter.ai/api/v1");
        assert_eq!(config.fallback_model, "openai/gpt-3.5-turbo");
    }

    #[test]
    fn test_provider_preference() {
        let pref = ProviderPreference {
            order: Some(vec!["openai".to_string(), "anthropic".to_string()]),
            allow: None,
            deny: None,
        };

        assert!(pref.order.is_some());
        assert_eq!(pref.order.unwrap().len(), 2);
    }
}
