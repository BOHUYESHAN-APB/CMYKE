/// 性能优化模块 ⚡
///
/// @诺诺 的性能优化实现喵
///
/// 功能：
/// - Token 压缩算法
/// - 内存优化（内存池、懒加载）
/// - 启动时间优化（延迟初始化）
///
/// 🔒 SAFETY: 所有优化必须保持功能正确性
///
/// 实现者: 诺诺 (Nono) ⚡

pub mod compress;
pub mod memory;
pub mod startup;

// 🔒 SAFETY: 重新导出公共接口喵
pub use compress::{ContextCompressor, MessageRanker, CompressionStrategy, CompressionStats};
pub use memory::{MemoryPool, LazyLoadToken, MemoryStats};
pub use startup::{StartupOptimizer, InitPhase, StartupStats};

/// 🔒 SAFETY: 性能优化配置喵
#[derive(Debug, Clone)]
pub struct PerformanceConfig {
    /// 是否启用 Token 压缩
    pub enable_compression: bool,
    /// 压缩阈值（token 数，超过自动压缩）
    pub compression_threshold: u32,
    /// 是否启用内存池
    pub enable_memory_pool: bool,
    /// 内存池大小（MB）
    pub memory_pool_size_mb: usize,
    /// 是否启用延迟初始化
    pub enable_lazy_loading: bool,
}

impl Default for PerformanceConfig {
    fn default() -> Self {
        Self {
            enable_compression: true,
            compression_threshold: 6000,
            enable_memory_pool: true,
            memory_pool_size_mb: 16,
            enable_lazy_loading: true,
        }
    }
}

/// 🔒 SAFETY: 性能优化器主结构体喵
/// 统一管理所有优化策略
#[derive(Debug)]
pub struct PerformanceOptimizer {
    /// 配置
    config: PerformanceConfig,
    /// 上下文压缩器
    compressor: Option<ContextCompressor>,
    /// 内存池
    memory_pool: Option<MemoryPool>,
    /// 启动优化器
    startup_optimizer: StartupOptimizer,
}

impl PerformanceOptimizer {
    /// 🔒 SAFETY: 创建新的性能优化器喵
    pub fn new(config: PerformanceConfig) -> Self {
        let compressor = if config.enable_compression {
            Some(ContextCompressor::new(CompressionStrategy::PriorityBased, config.compression_threshold))
        } else {
            None
        };

        let memory_pool = if config.enable_memory_pool {
            Some(MemoryPool::new(config.memory_pool_size_mb))
        } else {
            None
        };

        let startup_optimizer = StartupOptimizer::new(config.enable_lazy_loading);

        Self {
            config,
            compressor,
            memory_pool,
            startup_optimizer,
        }
    }

    /// 🔒 SAFETY: 执行压缩喵
    pub fn compress(&self, context: &mut Vec<crate::agent::AgentMessage>) -> Result<CompressionStats, String> {
        if let Some(ref compressor) = self.compressor {
            compressor.compress(context)
        } else {
            Err("Compression not enabled".to_string())
        }
    }

    /// 🔒 SAFETY: 分配内存喵
    pub fn allocate(&self, size: usize) -> Option<Vec<u8>> {
        if let Some(ref pool) = self.memory_pool {
            pool.allocate(size)
        } else {
            let mut buffer = Vec::with_capacity(size);
            buffer.resize(size, 0);
            Some(buffer)
        }
    }

    /// 🔒 SAFETY: 释放内存喵
    pub fn deallocate(&self, buffer: Vec<u8>) {
        if let Some(ref pool) = self.memory_pool {
            pool.deallocate(buffer);
        }
        // 如果没有内存池，buffer 会被自动 drop
    }

    /// 🔒 SAFETY: 获取启动优化器喵
    pub fn startup_optimizer(&self) -> &StartupOptimizer {
        &self.startup_optimizer
    }

    /// 🔒 SAFETY: 获取内存统计喵
    pub fn memory_stats(&self) -> Option<MemoryStats> {
        self.memory_pool.as_ref().map(|pool| pool.stats())
    }

    /// 🔒 SAFETY: 获取总体性能统计喵
    pub fn overall_stats(&self) -> PerformanceStats {
        let compression_stats = self.compressor.as_ref().and_then(|c| c.last_stats().clone());
        let memory_stats = self.memory_stats();

        PerformanceStats {
            compression: compression_stats,
            memory: memory_stats,
        }
    }
}

/// 🔒 SAFETY: 总体性能统计信息结构体喵
#[derive(Debug, Serialize)]
pub struct PerformanceStats {
    /// 压缩统计
    pub compression: Option<CompressionStats>,
    /// 内存统计
    pub memory: Option<MemoryStats>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_performance_config_default() {
        let config = PerformanceConfig::default();
        assert!(config.enable_compression);
        assert_eq!(config.compression_threshold, 6000);
        assert!(config.enable_memory_pool);
        assert_eq!(config.memory_pool_size_mb, 16);
        assert!(config.enable_lazy_loading);
    }

    #[test]
    fn test_performance_optimizer_creation() {
        let config = PerformanceConfig::default();
        let optimizer = PerformanceOptimizer::new(config);
        assert!(optimizer.compressor.is_some());
        assert!(optimizer.memory_pool.is_some());
    }
}
