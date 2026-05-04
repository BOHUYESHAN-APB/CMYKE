/// Telemetry 模块 📊
///
/// @缪斯 的可观测性深度监控系统喵
///
/// 功能：
/// - 收集 Agent 运行指标（Token 消耗、工具耗时、内存使用）
/// - SQLite 本地存储（零外部依赖）
/// - OpenTelemetry 风格的 Span 追踪
/// - 轻量 HTML Dashboard 可视化
///
/// 配置：
/// - 10% Tracing 采样率（平衡性能与监控密度）
/// - 5 秒内存监控间隔
/// - 自动指标聚合与存储
///
/// 🔒 SAFETY: 所有 I/O 操作都经过错误处理，崩溃不影响主流程
///
/// 模块作者: 缪斯 (Muse) 💜

mod metrics;
mod tracer;
mod dashboard;

pub use metrics::{
    MetricsCollector, MetricsConfig, AgentMetrics, ToolMetrics, SystemMetrics,
};
pub use tracer::{Tracer, Span, TracerConfig};
pub use dashboard::DashboardGenerator;

use tracing::{info, error, debug};
use std::sync::Arc;
use tokio::sync::RwLock;

/// 🔒 SAFETY: 可观测性配置喵
#[derive(Debug, Clone)]
pub struct TelemetryConfig {
    /// 是否启用 metrics 收集
    pub enable_metrics: bool,
    /// 是否启用 tracing
    pub enable_tracing: bool,
    /// Tracing 采样率（0.0~1.0），默认 0.1 (10%)
    pub trace_sampling: f64,
    /// 内存监控间隔（秒），默认 5
    pub monitor_interval_sec: u64,
    /// SQLite 数据库路径
    pub db_path: String,
}

impl Default for TelemetryConfig {
    fn default() -> Self {
        Self {
            enable_metrics: true,
            enable_tracing: true,
            trace_sampling: 0.1,
            monitor_interval_sec: 5,
            db_path: "metrics.db".to_string(),
        }
    }
}

/// 🔒 SAFETY: Telemetry 主结构体喵
pub struct Telemetry {
    config: TelemetryConfig,
    metrics: Arc<RwLock<MetricsCollector>>,
    tracer: Arc<Tracer>,
}

impl Telemetry {
    /// 🔒 SAFETY: 创建新的 Telemetry 实例喵
    pub async fn new(config: TelemetryConfig) -> Result<Self, String> {
        info!("📊 初始化 Telemetry 系统喵...");

        // 初始化 Metrics Collector
        let metrics = MetricsCollector::new(
            MetricsConfig {
                db_path: config.db_path.clone(),
                monitor_interval_sec: config.monitor_interval_sec,
            }
        ).await
            .map_err(|e| format!("初始化的 Metrics Collector 失败: {}", e))?;

        let metrics = Arc::new(RwLock::new(metrics));

        // 初始化 Tracer
        let tracer = Tracer::new(TracerConfig {
            sampling_rate: config.trace_sampling,
            enable_tracing: config.enable_tracing,
        });

        let tracer = Arc::new(tracer);

        info!("✅ Telemetry 系统初始化完成喵！");

        Ok(Self {
            config,
            metrics,
            tracer,
        })
    }

    /// 🔒 SAFETY: 启动后台监控任务喵
    pub async fn start_monitoring(&self) -> Result<(), String> {
        debug!("📊 启动后台监控任务喵...");

        let metrics = self.metrics.clone();

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(
                tokio::time::Duration::from_secs(5)
            );

            loop {
                interval.tick().await;

                // 🔒 SAFETY: 现在是同步方法了喵
                let result = {
                    let metrics_guard = metrics.write().await;
                    metrics_guard.sample_system_metrics()
                };

                if let Err(e) = result {
                    error!("采样系统指标失败: {}", e);
                }
            }
        });

        debug!("✅ 后台监控任务已启动喵！");

        Ok(())
    }

    /// 🔒 SAFETY: 获取 Metrics Collector 喵
    pub fn metrics(&self) -> Arc<RwLock<MetricsCollector>> {
        self.metrics.clone()
    }

    /// 🔒 SAFETY: 获取 Tracer 喵
    pub fn tracer(&self) -> Arc<Tracer> {
        self.tracer.clone()
    }

    /// 🔒 SAFETY: 开始一个新的 Span 喵
    pub fn start_span(&self, name: &str) -> Option<Span> {
        if !self.config.enable_tracing {
            return None;
        }

        self.tracer.start_span(name)
    }

    /// 🔒 SAFETY: 获取 Dashboard 生成器喵
    pub async fn get_dashboard(&self) -> Result<String, String> {
        let metrics = self.metrics.read().await;
        let generator = DashboardGenerator::new();

        generator
            .generate_html(&metrics)
            .map_err(|e| format!("生成 Dashboard 失败: {}", e))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_telemetry_init() {
        let config = TelemetryConfig {
            db_path: ":memory:".to_string(),
            ..Default::default()
        };

        let telemetry = Telemetry::new(config).await;
        assert!(telemetry.is_ok(), "Telemetry 初始化应该成功");
    }
}
