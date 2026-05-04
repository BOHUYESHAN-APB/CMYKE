//! Gateway HTTP 服务器模块 🌐
//!
//! @诺诺 的 Axum HTTP 服务器实现喵

use crate::core::traits::Result as NekoResult;
use axum::{
    extract::{Request, State},
    http::{HeaderMap, StatusCode},
    middleware::{self, Next},
    response::{IntoResponse, Json, Response},
    routing::{get, post},
    Router,
};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::sync::Arc;
use tokio::net::TcpListener;
use tracing::{error, info};
use uuid::Uuid;

use super::openai::create_openai_routes;
use super::metrics::create_metrics_routes;

/// 🔒 SAFETY: Gateway 配置结构体喵
#[derive(Debug, Clone)]
pub struct GatewayConfig {
    pub bind_addr: String,
    pub port: u16,
    pub bearer_token: String,
    pub pairing_enabled: bool,
}

impl Default for GatewayConfig {
    fn default() -> Self {
        Self {
            bind_addr: "127.0.0.1".to_string(),
            port: 8080,
            bearer_token: String::new(),
            pairing_enabled: true,
        }
    }
}

/// 🔒 SAFETY: Gateway 服务器状态喵
#[derive(Debug, Clone)]
pub struct GatewayState {
    pub config: GatewayConfig,
}

/// 🔒 SAFETY: 健康检查响应喵
#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub version: String,
    pub uptime_secs: u64,
}

/// 🔒 SAFETY: API 错误响应喵
#[derive(Debug, Serialize)]
pub struct ErrorResponse {
    pub code: String,
    pub message: String,
    pub request_id: String,
}

impl IntoResponse for ErrorResponse {
    fn into_response(self) -> Response {
        let status = match self.code.as_str() {
            "UNAUTHORIZED" => StatusCode::UNAUTHORIZED,
            "FORBIDDEN" => StatusCode::FORBIDDEN,
            "NOT_FOUND" => StatusCode::NOT_FOUND,
            _ => StatusCode::INTERNAL_SERVER_ERROR,
        };
        (status, Json(self)).into_response()
    }
}

/// 🔒 SAFETY: Bearer Token 认证中间件喵
pub async fn auth_middleware(
    State(state): State<Arc<GatewayState>>,
    headers: HeaderMap,
    request: Request,
    next: Next,
) -> Result<Response, StatusCode> {
    let auth_header = headers
        .get("authorization")
        .and_then(|h| h.to_str().ok())
        .ok_or(StatusCode::UNAUTHORIZED)?;

    if !auth_header.starts_with("Bearer ") {
        return Err(StatusCode::UNAUTHORIZED);
    }

    let token = &auth_header[7..];
    if token != state.config.bearer_token {
        return Err(StatusCode::FORBIDDEN);
    }

    Ok(next.run(request).await)
}

/// 🔒 SAFETY: 健康检查端点喵
pub async fn health_check() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok".to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
        uptime_secs: 0,
    })
}

/// 🔒 SAFETY: 状态端点喵
pub async fn status(State(state): State<Arc<GatewayState>>) -> Json<serde_json::Value> {
    Json(serde_json::json!({
        "status": "running",
        "config": {
            "bind_addr": state.config.bind_addr,
            "port": state.config.port,
        },
        "version": env!("CARGO_PKG_VERSION"),
    }))
}

/// 🔒 SAFETY: 配对请求喵
#[derive(Debug, Deserialize)]
pub struct PairingRequest {
    pub code: String,
    #[serde(default)]
    pub device_name: Option<String>,
}

/// 🔒 SAFETY: 配对响应喵
#[derive(Debug, Serialize)]
pub struct PairingResponse {
    pub status: String,
    pub message: String,
    pub session_token: Option<String>,
}

/// 🔒 SAFETY: 配对端点喵
pub async fn pairing(
    Json(req): Json<PairingRequest>,
) -> Result<Json<PairingResponse>, ErrorResponse> {
    info!("Pairing request with code: {}", req.code);
    
    if req.code.len() != 6 {
        return Err(ErrorResponse {
            code: "INVALID_CODE".to_string(),
            message: "Pairing code must be 6 digits".to_string(),
            request_id: Uuid::new_v4().to_string(),
        });
    }

    Ok(Json(PairingResponse {
        status: "success".to_string(),
        message: "Pairing successful".to_string(),
        session_token: Some(Uuid::new_v4().to_string()),
    }))
}

/// 🔒 SAFETY: 创建 Gateway 路由喵
fn create_router(state: Arc<GatewayState>) -> Router {
    // 公开端点
    let public_routes = Router::new()
        .route("/health", get(health_check))
        .merge(create_metrics_routes());

    // OpenAI 兼容路由
    let openai_routes = create_openai_routes();

    // 认证路由
    let protected_routes = Router::new()
        .route("/status", get(status))
        .route("/pairing", post(pairing))
        .layer(middleware::from_fn_with_state(
            state.clone(),
            auth_middleware,
        ));

    public_routes
        .merge(openai_routes)
        .merge(protected_routes)
        .with_state(state)
}

/// 🔒 SAFETY: Gateway 服务器喵
#[derive(Debug, Clone)]
pub struct GatewayServer {
    config: GatewayConfig,
    state: Arc<GatewayState>,
}

impl GatewayServer {
    pub fn new(config: GatewayConfig) -> Self {
        let state = Arc::new(GatewayState { config: config.clone() });
        Self { config, state }
    }

    pub async fn run(self) -> NekoResult<()> {
        let addr: SocketAddr = format!("{}:{}", self.config.bind_addr, self.config.port)
            .parse()
            .map_err(|e| format!("Invalid bind address: {}", e))?;

        let router = create_router(self.state.clone());
        let listener = TcpListener::bind(&addr)
            .await
            .map_err(|e| format!("Failed to bind to {}: {}", addr, e))?;

        info!("🚀 Gateway server listening on http://{}", addr);
        axum::serve(listener, router).await?;
        Ok(())
    }

    pub fn addr(&self) -> String {
        format!("{}:{}", self.config.bind_addr, self.config.port)
    }
}
