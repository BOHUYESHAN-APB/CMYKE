use axum::{routing::get, Json, Router};
use serde::Serialize;
use std::net::SocketAddr;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: &'static str,
    service: &'static str,
    version: &'static str,
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        service: "cmyke-backend",
        version: env!("CARGO_PKG_VERSION"),
    })
}

fn resolve_listen_addr() -> SocketAddr {
    let host = std::env::var("CMYKE_BACKEND_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
    let port = std::env::var("CMYKE_BACKEND_PORT")
        .ok()
        .and_then(|raw| raw.parse::<u16>().ok())
        .unwrap_or(4891);
    format!("{host}:{port}")
        .parse()
        .unwrap_or_else(|_| SocketAddr::from(([127, 0, 0, 1], 4891)))
}

#[tokio::main]
async fn main() {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/v1/health", get(health));

    let addr = resolve_listen_addr();
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    tracing::info!("CMYKE Rust backend listening on http://{}", addr);
    axum::serve(listener, app).await.unwrap();
}

