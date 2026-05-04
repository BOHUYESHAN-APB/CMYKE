//! OpenAI 兼容 API 端点 🤖
//! 
//! @妮娅 的 OpenAI 格式适配层喵
//! 
//! 端点:
//! - POST /v1/chat/completions (OpenAI 兼容)
//! - GET /v1/models
//! - GET /v1/tools

use axum::{
    extract::{State, Request},
    http::StatusCode,
    response::{IntoResponse, Json, Response},
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, info};

use super::server::GatewayState;

/// 🔒 SAFETY: OpenAI Chat 请求喵
#[derive(Debug, Deserialize)]
pub struct ChatCompletionRequest {
    /// 模型名称
    pub model: String,
    /// 消息列表
    pub messages: Vec<Message>,
    /// 温度 (0.0-2.0)
    #[serde(default = "default_temperature")]
    pub temperature: f32,
    /// 最大 Token 数
    #[serde(default)]
    pub max_tokens: Option<u32>,
    /// 流式输出
    #[serde(default)]
    pub stream: bool,
}

fn default_temperature() -> f32 { 0.7 }

/// 🔒 SAFETY: 消息结构喵
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct Message {
    /// 角色 (system/user/assistant)
    pub role: String,
    /// 内容
    pub content: String,
}

/// 🔒 SAFETY: Chat 响应喵
#[derive(Debug, Serialize)]
pub struct ChatCompletionResponse {
    pub id: String,
    pub object: String,
    pub created: u64,
    pub model: String,
    pub choices: Vec<Choice>,
    pub usage: Usage,
}

#[derive(Debug, Serialize)]
pub struct Choice {
    pub index: u32,
    pub message: Message,
    pub finish_reason: String,
}

#[derive(Debug, Serialize)]
pub struct Usage {
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub total_tokens: u32,
}

/// 🔒 SAFETY: Models 响应喵
#[derive(Debug, Serialize)]
pub struct ModelsResponse {
    pub object: String,
    pub data: Vec<ModelInfo>,
}

#[derive(Debug, Serialize)]
pub struct ModelInfo {
    pub id: String,
    pub object: String,
    pub owned_by: String,
}

/// 🔒 SAFETY: 工具响应喵
#[derive(Debug, Serialize)]
pub struct ToolsResponse {
    pub tools: Vec<ToolInfo>,
}

#[derive(Debug, Serialize)]
pub struct ToolInfo {
    pub name: String,
    pub description: String,
}

/// 🔒 SAFETY: Chat Completions 端点喵
pub async fn chat_completions(
    State(state): State<Arc<GatewayState>>,
    Json(req): Json<ChatCompletionRequest>,
) -> Result<Json<ChatCompletionResponse>, (StatusCode, String)> {
    info!("Chat request: model={}, messages={}", req.model, req.messages.len());
    
    // TODO: 实际调用 Agent 处理
    // 目前返回模拟响应
    
    let response = ChatCompletionResponse {
        id: format!("chatcmpl-{}", uuid::Uuid::new_v4()),
        object: "chat.completion".to_string(),
        created: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
        model: req.model.clone(),
        choices: vec![Choice {
            index: 0,
            message: Message {
                role: "assistant".to_string(),
                content: "喵~ NekoClaw API 已启动！这是模拟响应喵。".to_string(),
            },
            finish_reason: "stop".to_string(),
        }],
        usage: Usage {
            prompt_tokens: 10,
            completion_tokens: 20,
            total_tokens: 30,
        },
    };
    
    Ok(Json(response))
}

/// 🔒 SAFETY: 列出模型喵
pub async fn list_models() -> Json<ModelsResponse> {
    Json(ModelsResponse {
        object: "list".to_string(),
        data: vec![
            ModelInfo {
                id: "z-ai/glm5".to_string(),
                object: "model".to_string(),
                owned_by: "nvidia".to_string(),
            },
            ModelInfo {
                id: "deepseek-ai/deepseek-v3.2".to_string(),
                object: "model".to_string(),
                owned_by: "deepseek".to_string(),
            },
        ],
    })
}

/// 🔒 SAFETY: 列出工具喵
pub async fn list_tools() -> Json<ToolsResponse> {
    Json(ToolsResponse {
        tools: vec![
            ToolInfo {
                name: "fs_read".to_string(),
                description: "读取文件内容".to_string(),
            },
            ToolInfo {
                name: "fs_write".to_string(),
                description: "写入文件内容".to_string(),
            },
            ToolInfo {
                name: "echo".to_string(),
                description: "回显消息".to_string(),
            },
        ],
    })
}

/// 🔒 SAFETY: 创建 OpenAI 兼容路由喵
pub fn create_openai_routes() -> Router<Arc<GatewayState>> {
    Router::new()
        .route("/v1/chat/completions", post(chat_completions))
        .route("/v1/models", get(list_models))
        .route("/v1/tools", get(list_tools))
}
