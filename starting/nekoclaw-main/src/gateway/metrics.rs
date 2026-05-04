//! Prometheus Metrics 端点 📊
//! 
//! @缪斯 的可观测性指标喵

use axum::{
    extract::State,
    response::{IntoResponse, Response},
    http::{StatusCode, header},
    Router,
    routing::get,
};
use std::sync::Arc;

use super::server::GatewayState;

/// 🔒 SAFETY: Prometheus 指标格式喵
pub struct PrometheusMetrics {
    pub requests_total: u64,
    pub requests_active: u64,
    pub memory_bytes: u64,
    pub uptime_seconds: u64,
}

impl PrometheusMetrics {
    pub fn new() -> Self {
        Self {
            requests_total: 0,
            requests_active: 0,
            memory_bytes: 0,
            uptime_seconds: 0,
        }
    }
    
    /// 生成 Prometheus 格式输出喵
    pub fn to_prometheus_format(&self) -> String {
        format!(
            r#"# HELP nekoclaw_requests_total Total number of requests
# TYPE nekoclaw_requests_total counter
nekoclaw_requests_total {}

# HELP nekoclaw_requests_active Number of active requests
# TYPE nekoclaw_requests_active gauge
nekoclaw_requests_active {}

# HELP nekoclaw_memory_bytes Memory usage in bytes
# TYPE nekoclaw_memory_bytes gauge
nekoclaw_memory_bytes {}

# HELP nekoclaw_uptime_seconds Service uptime in seconds
# TYPE nekoclaw_uptime_seconds gauge
nekoclaw_uptime_seconds {}
"#,
            self.requests_total,
            self.requests_active,
            self.memory_bytes,
            self.uptime_seconds
        )
    }
}

/// 🔒 SAFETY: Metrics 端点喵
pub async fn metrics() -> Response {
    // TODO: 从 Telemetry 获取实际指标
    
    let m = PrometheusMetrics::new();
    
    // 获取内存使用
    let memory_mb = get_memory_usage_mb();
    let memory_bytes = (memory_mb * 1024.0 * 1024.0) as u64;
    
    let output = format!(
        r#"# HELP nekoclaw_memory_bytes Memory usage in bytes
# TYPE nekoclaw_memory_bytes gauge
nekoclaw_memory_bytes {}

# HELP nekoclaw_info Service information
# TYPE nekoclaw_info gauge
nekoclaw_info{{version="{}"}} 1
"#,
        memory_bytes,
        env!("CARGO_PKG_VERSION")
    );
    
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "text/plain; charset=utf-8")],
        output,
    ).into_response()
}

/// 🔒 SAFETY: 获取内存使用喵
fn get_memory_usage_mb() -> f64 {
    if let Ok(status) = std::fs::read_to_string("/proc/self/status") {
        for line in status.lines() {
            if line.starts_with("VmRSS:") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    if let Ok(kb) = parts[1].parse::<u64>() {
                        return kb as f64 / 1024.0;
                    }
                }
            }
        }
    }
    0.0
}

/// 🔒 SAFETY: 创建 Metrics 路由喵
pub fn create_metrics_routes() -> Router<Arc<GatewayState>> {
    Router::new()
        .route("/metrics", get(metrics))
}
