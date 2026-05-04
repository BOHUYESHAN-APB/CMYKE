/// 启动优化模块 🚀
///
/// @诺诺 的启动时间优化实现喵
///
/// 功能：
/// - 延迟初始化策略
/// - 启动阶段管理
/// - 启动时间统计
///
/// 🔒 SAFETY: 延迟初始化必须在需要前完成
///
/// 实现者: 诺诺 (Nono) ⚡

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Instant;
use uuid::Uuid;

/// 🔒 SAFETY: 初始化阶段枚举喵
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
pub enum InitPhase {
    /// 未开始
    NotStarted,
    /// 配置加载
    ConfigLoading,
    /// Provider 初始化
    ProviderInit,
    /// Memory 初始化
    MemoryInit,
    /// 服务注册
    ServiceRegistration,
    /// 就绪
    Ready,
}

/// 🔒 SAFETY: 初始化任务喵
pub struct InitTask {
    /// 任务 ID
    pub task_id: String,
    /// 任务名称
    pub name: String,
    /// 任务函数
    pub task_fn: Box<dyn Fn() -> Result<(), String> + Send + Sync>,
    /// 是否延迟加载
    pub deferred: bool,
    /// 依赖的任务 ID 列表
    pub dependencies: Vec<String>,
    /// 是否已完成
    completed: Arc<AtomicBool>,
    /// 执行时间（毫秒）
    execution_time_ms: Arc<RwLock<Option<u64>>>,
}

impl InitTask {
    /// 🔒 SAFETY: 创建新的初始化任务喵
    pub fn new<F>(name: String, task_fn: F) -> Self
    where
        F: Fn() -> Result<(), String> + Send + Sync + 'static,
    {
        Self {
            task_id: Uuid::new_v4().to_string(),
            name,
            task_fn: Box::new(task_fn),
            deferred: false,
            dependencies: Vec::new(),
            completed: Arc::new(AtomicBool::new(false)),
            execution_time_ms: Arc::new(RwLock::new(None)),
        }
    }

    /// 🔒 SAFETY: 设置为延迟加载喵
    pub fn with_deferred(mut self) -> Self {
        self.deferred = true;
        self
    }

    /// 🔒 SAFETY: 添加依赖喵
    pub fn with_dependency(mut self, task_id: String) -> Self {
        self.dependencies.push(task_id);
        self
    }

    /// 🔒 SAFETY: 检查是否已完成喵
    pub fn is_completed(&self) -> bool {
        self.completed.load(Ordering::Relaxed)
    }

    /// 🔒 SAFETY: 执行任务喵
    pub fn execute(&self) -> Result<(), String> {
        let start = Instant::now();

        let result = (self.task_fn)();

        let duration = start.elapsed().as_millis() as u64;

        if let Ok(mut time) = self.execution_time_ms.write() {
            *time = Some(duration);
        }

        self.completed.store(true, Ordering::Relaxed);

        result
    }
}

/// 🔒 SAFETY: 启动统计信息结构体喵
#[derive(Debug, Clone, Serialize)]
pub struct StartupStats {
    /// 总启动时间（毫秒）
    pub total_time_ms: u64,
    /// 各阶段时间
    pub phase_times: HashMap<String, u64>,
    /// 任务数量
    pub total_tasks: usize,
    /// 已完成任务数
    pub completed_tasks: usize,
    /// 延迟加载任务数
    pub deferred_tasks: usize,
}

/// 🔒 SAFETY: 启动优化器喵
pub struct StartupOptimizer {
    /// 是否启用延迟初始化
    enable_lazy_loading: Arc<AtomicBool>,
    /// 初始化任务
    tasks: Arc<RwLock<HashMap<String, Arc<InitTask>>>>,
    /// 启动阶段
    current_phase: Arc<RwLock<InitPhase>>,
    /// 阶段开始时间
    phase_start_time: Arc<RwLock<HashMap<String, Instant>>>,
    /// 启动开始时间
    startup_start_time: Arc<RwLock<Option<Instant>>>,
}

impl StartupOptimizer {
    /// 🔒 SAFETY: 创建新的启动优化器喵
    pub fn new(enable_lazy_loading: bool) -> Self {
        Self {
            enable_lazy_loading: Arc::new(AtomicBool::new(enable_lazy_loading)),
            tasks: Arc::new(RwLock::new(HashMap::new())),
            current_phase: Arc::new(RwLock::new(InitPhase::NotStarted)),
            phase_start_time: Arc::new(RwLock::new(HashMap::new())),
            startup_start_time: Arc::new(RwLock::new(None)),
        }
    }

    /// 🔒 SAFETY: 注册初始化任务喵
    pub async fn register_task<F>(&self, task: InitTask) {
        let mut tasks = self.tasks.write().await;
        tasks.insert(task.task_id.clone(), Arc::new(task));
    }

    /// 🔒 SAFETY: 启动喵
    pub async fn start(&self) -> Result<StartupStats, String> {
        // 记录启动开始时间
        *self.startup_start_time.write().await = Some(Instant::now());

        let mut stats = StartupStats {
            total_time_ms: 0,
            phase_times: HashMap::new(),
            total_tasks: 0,
            completed_tasks: 0,
            deferred_tasks: 0,
        };

        // 执行各阶段初始化
        self.run_phase(InitPhase::ConfigLoading, &mut stats).await?;
        self.run_phase(InitPhase::ProviderInit, &mut stats).await?;
        self.run_phase(InitPhase::MemoryInit, &mut stats).await?;
        self.run_phase(InitPhase::ServiceRegistration, &mut stats).await?;

        // 设置为就绪状态
        *self.current_phase.write().await = InitPhase::Ready;

        // 计算总启动时间
        if let Some(start) = *self.startup_start_time.read().await {
            stats.total_time_ms = start.elapsed().as_millis() as u64;
        }

        Ok(stats)
    }

    /// 🔒 SAFETY: 运行指定阶段的初始化喵
    async fn run_phase(&self, phase: InitPhase, stats: &mut StartupStats) -> Result<(), String> {
        // 进入阶段
        *self.current_phase.write().await = phase;
        let phase_name = format!("{:?}", phase);
        *self.phase_start_time.write().await
            .entry(phase_name.clone())
            .or_insert_with(Instant::now);

        let tasks = {
            let tasks_read = self.tasks.read().await;
            tasks_read.values().cloned().collect::<Vec<_>>()
        };

        // 执行非延迟加载的任务
        for task in tasks {
            if task.deferred && self.enable_lazy_loading.load(Ordering::Relaxed) {
                stats.deferred_tasks += 1;
                continue;
            }

            if !task.is_completed() {
                stats.total_tasks += 1;

                // 检查依赖是否已完成
                let all_deps_completed = task
                    .dependencies
                    .iter()
                    .all(|dep_id| {
                        if let Ok(tasks_read) = self.tasks.read() {
                            tasks_read.get(dep_id).map(|t| t.is_completed()).unwrap_or(false)
                        } else {
                            false
                        }
                    });

                if !all_deps_completed {
                    continue; // 依赖未完成，跳过
                }

                // 执行任务
                if let Err(e) = task.execute() {
                    return Err(format!("Task '{}' failed: {}", task.name, e));
                }

                stats.completed_tasks += 1;
            }
        }

        // 记录阶段时间
        if let Some(start) = self.phase_start_time.read().await.get(&phase_name) {
            stats.phase_times.insert(phase_name, start.elapsed().as_millis() as u64);
        }

        Ok(())
    }

    /// 🔒 SAFETY: 手动触发延迟加载的任务喵
    pub async fn trigger_deferred(&self, task_id: &str) -> Result<(), String> {
        let tasks = self.tasks.read().await;

        if let Some(task) = tasks.get(task_id) {
            if !task.is_completed() {
                task.execute()?;
            }
            Ok(())
        } else {
            Err(format!("Task '{}' not found", task_id))
        }
    }

    /// 🔒 SAFETY: 获取当前阶段喵
    pub async fn current_phase(&self) -> InitPhase {
        *self.current_phase.read().await
    }

    /// 🔒 SAFETY: 获取任务喵
    pub async fn get_task(&self, task_id: &str) -> Option<Arc<InitTask>> {
        let tasks = self.tasks.read().await;
        tasks.get(task_id).cloned()
    }

    /// 🔒 SAFETY: 列出所有任务喵
    pub async fn list_tasks(&self) -> Vec<(String, String, bool)> {
        let tasks = self.tasks.read().await;
        tasks
            .values()
            .map(|t| (t.task_id.clone(), t.name.clone(), t.deferred))
            .collect()
    }

    /// 🔒 SAFETY: 重置喵
    pub async fn reset(&self) {
        *self.current_phase.write().await = InitPhase::NotStarted;
        *self.startup_start_time.write().await = None;
        self.phase_start_time.write().await.clear();
        self.tasks.write().await.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_init_task_creation() {
        let task = InitTask::new("Test".to_string(), || Ok(()));
        assert!(!task.is_completed());
        assert!(!task.deferred);
    }

    #[tokio::test]
    async fn test_init_task_execution() {
        let task = InitTask::new("Test".to_string(), || Ok(()));
        assert_eq!(task.execute(), Ok(()));
        assert!(task.is_completed());
    }

    #[tokio::test]
    async fn test_startup_optimizer() {
        let optimizer = StartupOptimizer::new(false);

        optimizer
            .register_task(InitTask::new("Task1".to_string(), || Ok(())))
            .await;

        let stats = optimizer.start().await;
        assert!(stats.is_ok());

        let stats = stats.unwrap();
        assert_eq!(stats.completed_tasks, 1);
    }

    #[tokio::test]
    async fn test_startup_optimizer_deferred() {
        let optimizer = StartupOptimizer::new(true);

        optimizer
            .register_task(
                InitTask::new("Task1".to_string(), || Ok(())).with_deferred()
            )
            .await;

        let stats = optimizer.start().await;
        assert!(stats.is_ok());

        let stats = stats.unwrap();
        assert_eq!(stats.completed_tasks, 0);
        assert_eq!(stats.deferred_tasks, 1);

        // 触发延迟加载
        let tasks = optimizer.list_tasks().await;
        let task_id = &tasks[0].0;
        assert!(optimizer.trigger_deferred(task_id).await.is_ok());

        let stats = optimizer.start().await.unwrap();
        assert_eq!(stats.completed_tasks, 1);
    }

    #[tokio::test]
    async fn test_startup_optimizer_dependencies() {
        let optimizer = StartupOptimizer::new(false);

        let task1_id = Uuid::new_v4().to_string();
        let task2_id = Uuid::new_v4().to_string();

        let task1 = InitTask::new("Task1".to_string(), || Ok(()));
        let task2 = InitTask::new("Task2".to_string(), || Ok(()))
            .with_dependency(task1_id.clone());

        optimizer.register_task(task1).await;
        optimizer.register_task(task2).await;

        let stats = optimizer.start().await;
        assert!(stats.is_ok());
        assert_eq!(stats.completed_tasks, 2);
    }
}
