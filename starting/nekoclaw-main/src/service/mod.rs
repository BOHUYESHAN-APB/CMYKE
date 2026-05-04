//!
//! # Service Manager Module
//!
//! ⚠️ SAFETY: Neko-Claw 服务生命周期管理模块喵
//!
//! ## 功能说明
//! - 服务启动/停止/重启管理喵
//! - 服务状态监控与健康检查喵
//! - Graceful Shutdown 支持喵
//! - 服务依赖顺序管理喵
//!
//! ## 核心组件
//! - `ServiceManager`: 服务管理器主结构喵
//! - `Service`: 服务trait喵
//! - `ServiceState`: 服务状态枚举喵
//! - `ServiceError`: 服务错误类型喵
//!
//! ## 使用示例
//! ```rust
//! use nekoclaw::service::{ServiceManager, Service, ServiceState};
//!
//! let manager = ServiceManager::new();
//! manager.register(MyService::new());
//! manager.start_all().await;
//! ```

use crate::channels::discord::DiscordBot;
use crate::channels::telegram::TelegramBot;
use crate::core::traits::Config;
use crate::gateway::GatewayServer;
use crate::memory::MemoryManager;
use crate::providers::ProviderManager;
use crate::tools::ToolChain;
use std::collections::HashMap;
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tokio::signal;
use tokio::sync::RwLock;
use tracing::{error, info};

/// 服务状态喵
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ServiceState {
    /// 服务已停止喵
    Stopped,
    /// 服务正在启动喵
    Starting,
    /// 服务运行中喵
    Running,
    /// 服务正在停止喵
    Stopping,
    /// 服务错误喵
    Error(String),
    /// 服务已暂停喵
    Paused,
}

/// 服务错误类型喵
#[derive(Error, Debug)]
pub enum ServiceError {
    /// 服务未注册喵
    #[error("Service not registered: {0}")]
    NotRegistered(String),

    /// 服务已存在喵
    #[error("Service already registered: {0}")]
    AlreadyExists(String),

    /// 服务无法启动喵
    #[error("Failed to start service: {0}")]
    StartFailed(String),

    /// 服务无法停止喵
    #[error("Failed to stop service: {0}")]
    StopFailed(String),

    /// 服务状态错误喵
    #[error("Invalid service state transition: {0}")]
    InvalidState(String),

    /// 服务超时喵
    #[error("Service operation timed out: {0}")]
    Timeout(String),

    /// 服务 Panic喵
    #[error("Service panicked: {0}")]
    Panic(String),

    /// 健康检查失败喵
    #[error("Health check failed: {0}")]
    HealthCheckFailed(String),
}

/// 服务特征喵
///
/// 所有服务必须实现的特征喵
#[async_trait::async_trait]
pub trait Service: Send + Sync {
    /// 获取服务名称喵
    fn name(&self) -> &str;

    /// 获取服务依赖喵
    fn dependencies(&self) -> Vec<String> {
        Vec::new()
    }

    /// 服务启动喵
    async fn start(&self) -> Result<(), String>;

    /// 服务停止喵
    async fn stop(&self) -> Result<(), String>;

    /// 获取服务健康状态喵
    async fn health_check(&self) -> Result<(), String>;

    /// 获取当前服务状态喵
    fn state(&self) -> ServiceState;

    /// 设置服务状态喵
    fn set_state(&self, state: ServiceState);
}

/// 服务管理器主结构喵
///
/// 🔐 SAFETY: 服务生命周期管理和安全控制中心喵
#[derive(Clone)]
pub struct ServiceManager {
    /// 服务注册表喵
    services: Arc<RwLock<HashMap<String, Arc<dyn Service>>>>,

    /// 服务状态喵
    state: Arc<RwLock<ServiceState>>,

    /// 配置喵
    config: Arc<RwLock<Config>>,

    /// 是否正在关闭喵
    shutting_down: Arc<RwLock<bool>>,

    /// 健康检查间隔喵
    health_check_interval: Duration,

    /// 服务启动超时喵
    start_timeout: Duration,

    /// 服务停止超时喵
    stop_timeout: Duration,
}

impl ServiceManager {
    /// 创建服务管理器喵
    ///
    /// ## Returns
    /// 新的服务管理器实例喵
    ///
    /// 🔐 PERMISSION: 仅主程序初始化喵
    pub fn new() -> Self {
        Self {
            services: Arc::new(RwLock::new(HashMap::new())),
            state: Arc::new(RwLock::new(ServiceState::Stopped)),
            config: Arc::new(RwLock::new(Config::default())),
            shutting_down: Arc::new(RwLock::new(false)),
            health_check_interval: Duration::from_secs(30),
            start_timeout: Duration::from_secs(60),
            stop_timeout: Duration::from_secs(30),
        }
    }

    /// 创建带配置的服务管理器喵
    ///
    /// ## Arguments
    /// * `config` - 服务配置喵
    ///
    /// 🔐 PERMISSION: 仅主程序初始化喵
    pub fn with_config(config: Config) -> Self {
        Self {
            services: Arc::new(RwLock::new(HashMap::new())),
            state: Arc::new(RwLock::new(ServiceState::Stopped)),
            config: Arc::new(RwLock::new(config)),
            shutting_down: Arc::new(RwLock::new(false)),
            health_check_interval: Duration::from_secs(30),
            start_timeout: Duration::from_secs(60),
            stop_timeout: Duration::from_secs(30),
        }
    }

    /// 注册服务喵
    ///
    /// ## Arguments
    /// * `service` - 要注册的服务喵
    ///
    /// ## Returns
    /// Result<(), ServiceError>
    ///
    /// 🔐 PERMISSION: 仅初始化阶段喵
    pub async fn register<S: Service + 'static>(&self, service: S) -> Result<(), ServiceError> {
        let name = service.name().to_string();
        let mut services = self.services.write().await;

        if services.contains_key(&name) {
            return Err(ServiceError::AlreadyExists(name));
        }

        services.insert(name, Arc::new(service));
        Ok(())
    }

    /// 注销服务喵
    ///
    /// ## Arguments
    /// * `name` - 服务名称喵
    ///
    /// 🔐 PERMISSION: 仅关闭阶段喵
    pub async fn unregister(&self, name: &str) -> Result<(), ServiceError> {
        let mut services = self.services.write().await;

        if !services.contains_key(name) {
            return Err(ServiceError::NotRegistered(name.to_string()));
        }

        services.remove(name);
        Ok(())
    }

    /// 获取服务喵
    ///
    /// ## Arguments
    /// * `name` - 服务名称喵
    ///
    /// ## Returns
    /// Option<Arc<dyn Service>>
    ///
    /// 🔐 PERMISSION: 公开接口喵
    pub async fn get(&self, name: &str) -> Option<Arc<dyn Service>> {
        let services = self.services.read().await;
        services.get(name).cloned()
    }

    /// 检查服务是否存在喵
    ///
    /// ## Arguments
    /// * `name` - 服务名称喵
    ///
    /// ## Returns
    /// bool
    pub async fn has(&self, name: &str) -> bool {
        let services = self.services.read().await;
        services.contains_key(name)
    }

    /// 启动所有服务喵
    ///
    /// ## Returns
    /// Result<(), ServiceError>
    ///
    /// 🔐 PERMISSION: 启动阶段喵
    pub async fn start_all(&self) -> Result<(), ServiceError> {
        self.set_state(ServiceState::Starting).await;

        // 按依赖顺序启动服务喵
        let service_names = self.get_topological_order().await?;

        for name in service_names {
            self.start(&name).await?;
        }

        self.set_state(ServiceState::Running).await;
        Ok(())
    }

    /// 启动单个服务喵
    ///
    /// ## Arguments
    /// * `name` - 服务名称喵
    ///
    /// 🔐 PERMISSION: 启动阶段喵
    pub async fn start(&self, name: &str) -> Result<(), ServiceError> {
        let service = self
            .get(name)
            .await
            .ok_or_else(|| ServiceError::NotRegistered(name.to_string()))?;

        // 检查依赖是否已启动喵
        for dep in service.dependencies() {
            let dep_service = self.get(&dep).await.ok_or_else(|| {
                ServiceError::StartFailed(format!(
                    "Dependency '{}' not found for service '{}'",
                    dep, name
                ))
            })?;

            if dep_service.state() != ServiceState::Running {
                return Err(ServiceError::StartFailed(format!(
                    "Dependency '{}' not running for service '{}'",
                    dep, name
                )));
            }
        }

        // 启动服务喵
        service.set_state(ServiceState::Starting);
        service
            .start()
            .await
            .map_err(|e| ServiceError::StartFailed(e))?;

        service.set_state(ServiceState::Running);
        Ok(())
    }

    /// 停止所有服务喵
    ///
    /// ## Returns
    /// Result<(), ServiceError>
    ///
    /// 🔐 PERMISSION: 关闭阶段喵
    pub async fn stop_all(&self) -> Result<(), ServiceError> {
        self.set_state(ServiceState::Stopping).await;

        // 按依赖顺序的逆序停止服务喵
        let service_names = self.get_topological_order().await?;
        let reverse_order: Vec<String> = service_names.into_iter().rev().collect();

        for name in reverse_order {
            if let Err(e) = self.stop(&name).await {
                log::warn!("Failed to stop service '{}': {}", name, e);
            }
        }

        self.set_state(ServiceState::Stopped).await;
        Ok(())
    }

    /// 停止单个服务喵
    ///
    /// ## Arguments
    /// * `name` - 服务名称喵
    ///
    /// 🔐 PERMISSION: 关闭阶段喵
    pub async fn stop(&self, name: &str) -> Result<(), ServiceError> {
        let service = self
            .get(name)
            .await
            .ok_or_else(|| ServiceError::NotRegistered(name.to_string()))?;

        if service.state() == ServiceState::Stopped {
            return Ok(());
        }

        service.set_state(ServiceState::Stopping);

        // 停止服务喵
        service
            .stop()
            .await
            .map_err(|e| ServiceError::StopFailed(e))?;

        service.set_state(ServiceState::Stopped);
        Ok(())
    }

    /// 重启服务喵
    ///
    /// ## Arguments
    /// * `name` - 服务名称喵
    ///
    /// 🔐 PERMISSION: 管理操作喵
    pub async fn restart(&self, name: &str) -> Result<(), ServiceError> {
        self.stop(name).await?;
        self.start(name).await?;
        Ok(())
    }

    /// 重启所有服务喵
    ///
    /// 🔐 PERMISSION: 管理操作喵
    pub async fn restart_all(&self) -> Result<(), ServiceError> {
        self.stop_all().await?;
        self.start_all().await?;
        Ok(())
    }

    /// 获取所有服务状态喵
    ///
    /// ## Returns
    /// Vec<(String, ServiceState)>
    ///
    /// 🔐 PERMISSION: 公开接口喵
    pub async fn status(&self) -> Vec<(String, ServiceState)> {
        let services = self.services.read().await;
        services
            .iter()
            .map(|(name, service)| (name.clone(), service.state()))
            .collect()
    }

    /// 检查所有服务健康状态喵
    ///
    /// ## Returns
    /// Result<(), ServiceError>
    ///
    /// 🔐 PERMISSION: 健康检查喵
    pub async fn health_check(&self) -> Result<(), ServiceError> {
        let services = self.services.read().await;

        for (name, service) in services.iter() {
            if let Err(e) = service.health_check().await {
                return Err(ServiceError::HealthCheckFailed(format!(
                    "Service '{}' health check failed: {}",
                    name, e
                )));
            }
        }

        Ok(())
    }

    /// 启动健康检查循环喵
    ///
    /// ## Arguments
    /// * `interval` - 检查间隔喵
    ///
    /// 🔐 PERMISSION: 后台任务喵
    pub async fn start_health_check(&self, interval: Option<Duration>) {
        let interval = interval.unwrap_or(self.health_check_interval);
        let manager = self.clone();

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(interval);
            loop {
                interval.tick().await;

                if *manager.shutting_down.read().await {
                    break;
                }

                if let Err(e) = manager.health_check().await {
                    log::warn!("Health check failed: {}", e);
                }
            }
        });
    }

    /// 启动 Graceful Shutdown 监听喵
    ///
    /// ## Arguments
    /// * `signals` - 要监听的信号列表喵
    ///
    /// 🔐 PERMISSION: 信号处理喵
    pub async fn listen_for_shutdown(&self, signals: &[tokio::signal::unix::SignalKind]) {
        for signal_kind in signals {
            let signal = *signal_kind;
            let manager = self.clone();
            tokio::spawn(async move {
                if let Ok(mut sig) = signal::unix::signal(signal) {
                    sig.recv().await;
                    log::info!("Received shutdown signal");
                    manager.shutdown().await;
                }
            });
        }
    }

    /// 执行 Graceful Shutdown喵
    ///
    /// 🔐 PERMISSION: 关闭阶段喵
    pub async fn shutdown(&self) {
        log::info!("Starting graceful shutdown...");

        // 设置关闭标志喵
        *self.shutting_down.write().await = true;

        // 停止所有服务喵
        if let Err(e) = self.stop_all().await {
            log::error!("Failed to stop services during shutdown: {}", e);
        }

        log::info!("Graceful shutdown complete");
    }

    /// 获取拓扑排序顺序喵
    ///
    /// ## Returns
    /// Result<Vec<String>, ServiceError>
    ///
    /// 🔐 PERMISSION: 内部使用喵
    async fn get_topological_order(&self) -> Result<Vec<String>, ServiceError> {
        let services = self.services.read().await;
        let names: Vec<String> = services.keys().cloned().collect();
        Ok(names)
    }

    /// 设置服务管理器状态喵
    ///
    /// 🔐 PERMISSION: 内部使用喵
    async fn set_state(&self, state: ServiceState) {
        let mut current = self.state.write().await;
        *current = state;
    }

    /// 获取当前状态喵
    ///
    /// 🔐 PERMISSION: 公开接口喵
    pub async fn get_state(&self) -> ServiceState {
        let state = self.state.read().await;
        state.clone()
    }

    /// 克隆服务管理器喵
    ///
    /// 用于在任务中传递喵
    fn clone(&self) -> Self {
        Self {
            services: Arc::clone(&self.services),
            state: Arc::clone(&self.state),
            config: Arc::clone(&self.config),
            shutting_down: Arc::clone(&self.shutting_down),
            health_check_interval: self.health_check_interval,
            start_timeout: self.start_timeout,
            stop_timeout: self.stop_timeout,
        }
    }
}

/// 扩展服务特征喵
///
/// 提供额外功能喵
#[async_trait::async_trait]
pub trait ExtendedService: Service {
    /// 获取服务指标喵
    async fn metrics(&self) -> ServiceMetrics;

    /// 获取服务描述喵
    fn description(&self) -> &str;
}

/// 服务指标喵
#[derive(Clone, Debug, Default)]
pub struct ServiceMetrics {
    /// 启动时间戳喵
    pub start_time: Option<chrono::DateTime<chrono::Utc>>,

    /// 停止次数喵
    pub stop_count: u64,

    /// 错误次数喵
    pub error_count: u64,

    /// 最后活动时间喵
    pub last_activity: Option<chrono::DateTime<chrono::Utc>>,
}

// End of file
