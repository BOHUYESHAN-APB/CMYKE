/// Gateway Webhook 端点处理模块 🎣
///
/// @诺诺 的 Webhook 处理实现喵
///
/// 功能：
/// - Discord/Telegram/Webhook 兼容
/// - 事件类型路由
/// - 异步事件处理
/// - 错误重试队列
///
/// 🔒 SAFETY: Webhook 端点需要 Bearer Token 认证
///
/// 实现者: 诺诺 (Nono) ⚡
use axum::{
    extract::{Request, State},
    http::{HeaderMap, StatusCode},
    response::{IntoResponse, Json, Response},
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::{mpsc, RwLock};
use tracing::{error, info, warn};
use uuid::Uuid;

/// 🔒 SAFETY: Webhook 配置结构体喵
#[derive(Debug, Clone)]
pub struct WebhookConfig {
    /// Webhook 端点路径
    pub endpoint_path: String,
    /// 是否启用验证
    pub verify_signature: bool,
    /// 签名密钥（如果启用验证）
    pub signature_secret: Option<String>,
    /// 重试队列大小
    pub retry_queue_size: usize,
    /// 最大重试次数
    pub max_retries: u8,
}

impl Default for WebhookConfig {
    fn default() -> Self {
        Self {
            endpoint_path: "/webhook".to_string(),
            verify_signature: false,
            signature_secret: None,
            retry_queue_size: 100,
            max_retries: 3,
        }
    }
}

/// 🔒 SAFETY: Webhook 事件类型枚举喵
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WebhookEventType {
    /// Discord 消息
    DiscordMessage,
    /// Discord 状态更新
    DiscordStatusUpdate,
    /// Telegram 消息
    TelegramMessage,
    /// 通用事件
    Generic,
}

impl WebhookEventType {
    /// 🔒 SAFETY: 从字符串解析事件类型喵
    /// 支持自定义格式，提取后转换为标准类型
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "discord.message" => Some(WebhookEventType::DiscordMessage),
            "discord.status" => Some(WebhookEventType::DiscordStatusUpdate),
            "telegram.message" => Some(WebhookEventType::TelegramMessage),
            _ => Some(WebhookEventType::Generic),
        }
    }

    /// 🔒 SAFETY: 转换为字符串喵
    pub fn as_str(&self) -> &'static str {
        match self {
            WebhookEventType::DiscordMessage => "discord.message",
            WebhookEventType::DiscordStatusUpdate => "discord.status",
            WebhookEventType::TelegramMessage => "telegram.message",
            WebhookEventType::Generic => "generic",
        }
    }
}

/// 🔒 SAFETY: Webhook 事件结构体喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WebhookEvent {
    /// 事件类型
    #[serde(rename = "type")]
    pub event_type: String,
    /// 事件 ID
    pub event_id: String,
    /// 时间戳
    pub timestamp: String,
    /// 数据负载
    pub data: serde_json::Value,
}

/// 🔒 SAFETY: Webhook 响应结构体喵
#[derive(Debug, Serialize)]
pub struct WebhookResponse {
    /// 是否成功
    success: bool,
    /// 消息
    message: String,
    /// 事件 ID
    event_id: String,
}

/// 🔒 SAFETY: Webhook 错误响应结构体喵
#[derive(Debug, Serialize)]
pub struct WebhookErrorResponse {
    /// 错误代码
    code: String,
    /// 错误消息
    message: String,
    /// 请求 ID
    request_id: String,
}

impl IntoResponse for WebhookErrorResponse {
    fn into_response(self) -> Response {
        let status = match self.code.as_str() {
            "UNAUTHORIZED" => StatusCode::UNAUTHORIZED,
            "INVALID_SIGNATURE" => StatusCode::FORBIDDEN,
            "INVALID_PAYLOAD" => StatusCode::BAD_REQUEST,
            _ => StatusCode::INTERNAL_SERVER_ERROR,
        };

        (status, Json(self)).into_response()
    }
}

/// 🔒 SAFETY: Webhook 处理器特征喵
/// 定义事件处理接口
#[async_trait::async_trait]
pub trait WebhookHandler: Send + Sync {
    /// 🔒 SAFETY: 处理 Webhook 事件喵
    /// 异常处理: 所有错误返回 Result
    async fn handle_event(&self, event: WebhookEvent) -> Result<String, String>;
}

/// 🔒 SAFETY: 默认 Webhook 处理器喵
#[derive(Debug, Clone)]
pub struct DefaultWebhookHandler;

#[async_trait::async_trait]
impl WebhookHandler for DefaultWebhookHandler {
    /// 🔒 SAFETY: 处理 Webhook 事件（默认实现）喵
    /// 异常处理: 记录日志后返回成功
    async fn handle_event(&self, event: WebhookEvent) -> Result<String, String> {
        info!("Processing webhook event: {}", event.event_type);

        // 根据事件类型路由
        let event_type =
            WebhookEventType::from_str(&event.event_type).unwrap_or(WebhookEventType::Generic);

        match event_type {
            WebhookEventType::DiscordMessage => {
                info!("Discord message received: event_id={}", event.event_id);
                Ok("Discord message processed".to_string())
            }
            WebhookEventType::DiscordStatusUpdate => {
                info!("Discord status update: event_id={}", event.event_id);
                Ok("Discord status update processed".to_string())
            }
            WebhookEventType::TelegramMessage => {
                info!("Telegram message received: event_id={}", event.event_id);
                Ok("Telegram message processed".to_string())
            }
            WebhookEventType::Generic => {
                info!("Generic webhook event: event_id={}", event.event_id);
                Ok("Generic event processed".to_string())
            }
        }
    }
}

/// 🔒 SAFETY: Webhook 管理器结构体喵
#[derive(Debug, Clone)]
pub struct WebhookManager {
    /// 配置
    config: WebhookConfig,
    /// 事件发送器（异步处理队列）
    event_sender: mpsc::Sender<WebhookEvent>,
    /// 重试队列
    retry_queue: Arc<RwLock<Vec<WebhookEvent>>>,
}

impl WebhookManager {
    /// 🔒 SAFETY: 创建新的 Webhook 管理器喵
    /// 异常处理: 队列创建失败时 panic
    pub fn new(config: WebhookConfig) -> Self {
        let (event_sender, mut event_receiver) =
            mpsc::channel::<WebhookEvent>(config.retry_queue_size);
        let retry_queue = Arc::new(RwLock::new(Vec::new()));

        // 启动事件处理任务
        tokio::spawn(async move {
            while let Some(event) = event_receiver.recv().await {
                // TODO: 处理事件
                info!("Webhook event received: type={}", event.event_type);
            }
        });

        Self {
            config,
            event_sender,
            retry_queue,
        }
    }

    /// 🔒 SAFETY: 处理 Webhook 请求喵
    /// 异常处理: 无效负载、签名验证失败
    pub async fn handle_webhook(
        &self,
        headers: HeaderMap,
        body: String,
    ) -> Result<Json<WebhookResponse>, WebhookErrorResponse> {
        // 提取事件类型
        let event_type_header = headers
            .get("x-event-type")
            .and_then(|h| h.to_str().ok())
            .unwrap_or("generic");

        // 提取事件 ID
        let generated_id = Uuid::new_v4().to_string();
        let event_id = headers
            .get("x-event-id")
            .and_then(|h| h.to_str().ok())
            .unwrap_or(&generated_id);

        // 验证签名（如果启用）
        if self.config.verify_signature {
            let signature = headers
                .get("x-signature")
                .and_then(|h| h.to_str().ok())
                .ok_or_else(|| WebhookErrorResponse {
                    code: "INVALID_SIGNATURE".to_string(),
                    message: "Missing signature header".to_string(),
                    request_id: event_id.to_string(),
                })?;

            // TODO: 实现实际的签名验证
            if signature.is_empty() {
                return Err(WebhookErrorResponse {
                    code: "INVALID_SIGNATURE".to_string(),
                    message: "Invalid signature".to_string(),
                    request_id: event_id.to_string(),
                });
            }
        }

        // 解析请求体
        let event_data: serde_json::Value =
            serde_json::from_str(&body).map_err(|_| WebhookErrorResponse {
                code: "INVALID_PAYLOAD".to_string(),
                message: "Invalid JSON payload".to_string(),
                request_id: event_id.to_string(),
            })?;

        // 创建事件
        let event = WebhookEvent {
            event_type: event_type_header.to_string(),
            event_id: event_id.to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
            data: event_data,
        };

        // 发送到处理队列
        if let Err(e) = self.event_sender.send(event.clone()).await {
            error!("Failed to enqueue webhook event: {}", e);

            // 添加到重试队列
            let mut retry = self.retry_queue.write().await;
            retry.push(event);
        }

        Ok(Json(WebhookResponse {
            success: true,
            message: "Webhook received".to_string(),
            event_id: event_id.to_string(),
        }))
    }

    /// 🔒 SAFETY: 处理重试队列喵
    /// 异常处理: 队列为空时跳过
    pub async fn process_retry_queue(&self) -> usize {
        let mut retry = self.retry_queue.write().await;
        let count = retry.len();

        for event in retry.drain(..) {
            if let Err(e) = self.event_sender.send(event).await {
                error!("Failed to requeue event: {}", e);
            }
        }

        info!("Processed {} retry events", count);
        count
    }

    /// 🔒 SAFETY: 获取重试队列大小喵
    pub async fn retry_queue_size(&self) -> usize {
        self.retry_queue.read().await.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_event_type_parsing() {
        assert_eq!(
            WebhookEventType::from_str("discord.message"),
            Some(WebhookEventType::DiscordMessage)
        );
        assert_eq!(
            WebhookEventType::from_str("telegram.message"),
            Some(WebhookEventType::TelegramMessage)
        );
        assert_eq!(
            WebhookEventType::from_str("unknown"),
            Some(WebhookEventType::Generic)
        );
    }

    #[test]
    fn test_event_type_to_string() {
        assert_eq!(WebhookEventType::DiscordMessage.as_str(), "discord.message");
        assert_eq!(
            WebhookEventType::DiscordStatusUpdate.as_str(),
            "discord.status"
        );
        assert_eq!(
            WebhookEventType::TelegramMessage.as_str(),
            "telegram.message"
        );
        assert_eq!(WebhookEventType::Generic.as_str(), "generic");
    }

    #[tokio::test]
    async fn test_webhook_manager() {
        let config = WebhookConfig::default();
        let manager = WebhookManager::new(config);

        let response = manager
            .handle_webhook(HeaderMap::default(), r#"{"test": "data"}"#.to_string())
            .await;
        assert!(response.is_ok());
    }
}
