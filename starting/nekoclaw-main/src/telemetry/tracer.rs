//! Tracer - OpenTelemetry 风格 Span 追踪 🔍

use chrono::{DateTime, Utc};
use tracing::{debug, trace};
use uuid::Uuid;
use std::sync::Arc;
use tokio::sync::RwLock;
use std::fmt;

/// 🔒 SAFETY: Tracer 配置喵
#[derive(Debug, Clone)]
pub struct TracerConfig {
    pub sampling_rate: f64,
    pub enable_tracing: bool,
}

impl Default for TracerConfig {
    fn default() -> Self {
        Self {
            sampling_rate: 0.1,
            enable_tracing: true,
        }
    }
}

/// 🔒 SAFETY: Span 状态喵
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpanStatus {
    InProgress,
    Completed,
    Failed,
}

/// 🔒 SAFETY: Span 结构体喵
#[derive(Debug, Clone)]
pub struct Span {
    pub span_id: String,
    pub trace_id: String,
    pub name: String,
    pub start_time: DateTime<Utc>,
    pub end_time: Option<DateTime<Utc>>,
    pub status: SpanStatus,
    pub parent_span_id: Option<String>,
    pub attributes: Vec<(String, String)>,
    pub events: Vec<(DateTime<Utc>, String)>,
}

impl Span {
    pub fn finish(&mut self) {
        self.end_time = Some(Utc::now());
        self.status = SpanStatus::Completed;
    }

    pub fn finish_with_error(&mut self, error: &str) {
        self.end_time = Some(Utc::now());
        self.status = SpanStatus::Failed;
        self.events.push((Utc::now(), format!("error: {}", error)));
    }

    pub fn set_attribute(&mut self, key: String, value: String) {
        self.attributes.push((key, value));
    }

    pub fn add_event(&mut self, message: String) {
        self.events.push((Utc::now(), message));
    }

    pub fn create_child(&self, name: &str) -> Self {
        Self {
            span_id: Uuid::new_v4().to_string(),
            trace_id: self.trace_id.clone(),
            name: name.to_string(),
            start_time: Utc::now(),
            end_time: None,
            status: SpanStatus::InProgress,
            parent_span_id: Some(self.span_id.clone()),
            attributes: Vec::new(),
            events: Vec::new(),
        }
    }
}

/// 🔒 SAFETY: Tracer 结构体喵
pub struct Tracer {
    config: TracerConfig,
    active_spans: Arc<RwLock<Vec<Span>>>,
}

impl fmt::Debug for Tracer {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Tracer")
            .field("config", &self.config)
            .finish()
    }
}

impl Tracer {
    pub fn new(config: TracerConfig) -> Self {
        Self {
            config,
            active_spans: Arc::new(RwLock::new(Vec::new())),
        }
    }

    pub fn start_span(&self, name: &str) -> Option<Span> {
        if !self.config.enable_tracing {
            return None;
        }

        // 采样判断
        let mut hasher = std::collections::hash_map::DefaultHasher::new();
        use std::hash::{Hash, Hasher};
        name.hash(&mut hasher);
        let hash = hasher.finish();

        if (hash as f64 / u64::MAX as f64) > self.config.sampling_rate {
            return None;
        }

        Some(Span {
            span_id: Uuid::new_v4().to_string(),
            trace_id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            start_time: Utc::now(),
            end_time: None,
            status: SpanStatus::InProgress,
            parent_span_id: None,
            attributes: Vec::new(),
            events: Vec::new(),
        })
    }

    pub async fn finish_span(&self, mut span: Span) {
        span.finish();
        let mut spans = self.active_spans.write().await;
        spans.push(span);
        if spans.len() > 1000 {
            let to_remove = spans.len() - 1000;
            spans.drain(0..to_remove);
        }
    }

    pub async fn finish_span_with_error(&self, mut span: Span, error: &str) {
        span.finish_with_error(error);
        let mut spans = self.active_spans.write().await;
        spans.push(span);
        if spans.len() > 1000 {
            let to_remove = spans.len() - 1000;
            spans.drain(0..to_remove);
        }
    }

    pub async fn get_recent_spans(&self, limit: u32) -> Vec<Span> {
        let spans = self.active_spans.read().await;
        spans.iter().rev().take(limit as usize).cloned().collect()
    }
}

/// 🔒 SAFETY: Span Guard - 自动完成 Span 喵
#[derive(Debug)]
pub struct SpanGuard {
    span: Option<Span>,
    tracer: Option<Arc<Tracer>>,
}

impl SpanGuard {
    pub fn new(span: Span, tracer: Arc<Tracer>) -> Self {
        Self {
            span: Some(span),
            tracer: Some(tracer),
        }
    }

    pub async fn finish(&mut self) {
        if let (Some(span), Some(tracer)) = (self.span.take(), self.tracer.take()) {
            tracer.finish_span(span).await;
        }
    }

    pub async fn finish_with_error(&mut self, error: &str) {
        if let (Some(span), Some(tracer)) = (self.span.take(), self.tracer.take()) {
            tracer.finish_span_with_error(span, error).await;
        }
    }
}

impl Drop for SpanGuard {
    fn drop(&mut self) {
        if let (Some(mut span), Some(tracer)) = (self.span.take(), self.tracer.take()) {
            span.finish();
            if let Ok(handle) = tokio::runtime::Handle::try_current() {
                handle.spawn(async move {
                    let mut spans = tracer.active_spans.write().await;
                    spans.push(span);
                    if spans.len() > 1000 {
                        let to_remove = spans.len() - 1000;
                        spans.drain(0..to_remove);
                    }
                });
            }
        }
    }
}
