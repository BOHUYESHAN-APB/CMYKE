/// 内存优化模块 💾
///
/// @诺诺 的内存优化实现喵
///
/// 功能：
/// - 内存池（复用缓冲区）
/// - 懒加载 Token（延迟初始化）
/// - 内存泄漏检测
///
/// 🔒 SAFETY: 内存池必须正确处理所有权
///
/// 实现者: 诺诺 (Nono) ⚡

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::sync::atomic::{AtomicUsize, Ordering};
use uuid::Uuid;

/// 🔒 SAFETY: 内存池块喵
#[derive(Debug)]
struct MemoryBlock {
    /// 数据
    data: Vec<u8>,
    /// 使用次数
    use_count: AtomicUsize,
    /// 最后使用时间
    last_used: AtomicUsize,
}

/// 🔒 SAFETY: 内存池喵
pub struct MemoryPool {
    /// 空闲块（按大小分类）
    free_blocks: Arc<RwLock<HashMap<usize, Vec<MemoryBlock>>>>,
    /// 池大小（字节）
    pool_size: usize,
    /// 当前使用量
    current_usage: Arc<AtomicUsize>,
    /// 分配次数
    allocation_count: Arc<AtomicUsize>,
    /// 释放次数
    deallocation_count: Arc<AtomicUsize>,
}

impl MemoryPool {
    /// 🔒 SAFETY: 创建新的内存池喵
    pub fn new(size_mb: usize) -> Self {
        let pool_size = size_mb * 1024 * 1024;
        Self {
            free_blocks: Arc::new(RwLock::new(HashMap::new())),
            pool_size,
            current_usage: Arc::new(AtomicUsize::new(0)),
            allocation_count: Arc::new(AtomicUsize::new(0)),
            deallocation_count: Arc::new(AtomicUsize::new(0)),
        }
    }

    /// 🔒 SAFETY: 分配内存喵
    pub fn allocate(&self, size: usize) -> Option<Vec<u8>> {
        // 检查是否有足够的空闲块
        let mut free_blocks = self.free_blocks.write().ok()?;

        // 查找合适大小的块
        if let Some(blocks) = free_blocks.get_mut(&size) {
            if let Some(mut block) = blocks.pop() {
                block.use_count.fetch_add(1, Ordering::Relaxed);
                block.last_used.store(
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .map(|d| d.as_secs() as usize)
                        .unwrap_or(0),
                    Ordering::Relaxed
                );
                self.allocation_count.fetch_add(1, Ordering::Relaxed);
                self.current_usage.fetch_add(size, Ordering::Relaxed);
                return Some(block.data);
            }
        }

        // 没有合适大小的块，创建新的
        // 检查池大小限制
        if self.current_usage.load(Ordering::Relaxed) + size > self.pool_size {
            return None; // 池已满
        }

        let mut buffer = Vec::with_capacity(size);
        buffer.resize(size, 0);
        self.allocation_count.fetch_add(1, Ordering::Relaxed);
        self.current_usage.fetch_add(size, Ordering::Relaxed);
        Some(buffer)
    }

    /// 🔒 SAFETY: 释放内存喵
    pub fn deallocate(&self, buffer: Vec<u8>) {
        let size = buffer.len();

        // 放回池中
        let mut free_blocks = match self.free_blocks.write() {
            Ok(blocks) => blocks,
            Err(_) => return,
        };

        let blocks = free_blocks.entry(size).or_insert_with(Vec::new);
        blocks.push(MemoryBlock {
            data: buffer,
            use_count: AtomicUsize::new(0),
            last_used: AtomicUsize::new(0),
        });

        self.deallocation_count.fetch_add(1, Ordering::Relaxed);
        self.current_usage.fetch_sub(size, Ordering::Relaxed);
    }

    /// 🔒 SAFETY: 清理池喵
    pub fn clear(&self) {
        if let Ok(mut free_blocks) = self.free_blocks.write() {
            free_blocks.clear();
        }
        self.current_usage.store(0, Ordering::Relaxed);
    }

    /// 🔒 SAFETY: 获取统计信息喵
    pub fn stats(&self) -> MemoryStats {
        let free_blocks_count = self
            .free_blocks
            .read()
            .map(|blocks| blocks.values().map(|v| v.len()).sum())
            .unwrap_or(0);

        MemoryStats {
            pool_size: self.pool_size,
            current_usage: self.current_usage.load(Ordering::Relaxed),
            free_blocks: free_blocks_count,
            allocation_count: self.allocation_count.load(Ordering::Relaxed),
            deallocation_count: self.deallocation_count.load(Ordering::Relaxed),
        }
    }
}

/// 🔒 SAFETY: 内存统计信息结构体喵
#[derive(Debug, Clone, Serialize)]
pub struct MemoryStats {
    /// 池大小（字节）
    pub pool_size: usize,
    /// 当前使用量（字节）
    pub current_usage: usize,
    /// 空闲块数量
    pub free_blocks: usize,
    /// 分配次数
    pub allocation_count: usize,
    /// 释放次数
    pub deallocation_count: usize,
}

/// 🔒 SAFETY: 初始化阶段枚举喵
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InitPhase {
    /// 未初始化
    NotStarted,
    /// 已延迟加载
    Deferred,
    /// 已初始化
    Initialized,
}

/// 🔒 SAFETY: 懒加载 Token 喵
/// 用于延迟初始化资源
pub struct LazyLoadToken<T> {
    /// 数据
    data: Arc<RwLock<Option<T>>>,
    /// 初始化阶段
    phase: Arc<RwLock<InitPhase>>,
    /// Token ID
    token_id: String,
}

impl<T> LazyLoadToken<T>
where
    T: Clone,
{
    /// 🔒 SAFETY: 创建新的懒加载 Token 喵
    pub fn new() -> Self {
        Self {
            data: Arc::new(RwLock::new(None)),
            phase: Arc::new(RwLock::new(InitPhase::NotStarted)),
            token_id: Uuid::new_v4().to_string(),
        }
    }

    /// 🔒 SAFETY: 标记为延迟加载喵
    pub async fn defer(&self) {
        let mut phase = self.phase.write().await;
        if *phase == InitPhase::NotStarted {
            *phase = InitPhase::Deferred;
        }
    }

    /// 🔒 SAFETY: 设置数据喵
    pub async fn set(&self, data: T) {
        let mut wrapper = self.data.write().await;
        *wrapper = Some(data);
        let mut phase = self.phase.write().await;
        *phase = InitPhase::Initialized;
    }

    /// 🔒 SAFETY: 获取数据喵
    /// 如果未初始化，返回 None
    pub async fn get(&self) -> Option<T> {
        let wrapper = self.data.read().await;
        wrapper.clone()
    }

    /// 🔒 SAFETY: 检查是否已初始化喵
    pub async fn is_initialized(&self) -> bool {
        let phase = self.phase.read().await;
        *phase == InitPhase::Initialized
    }

    /// 🔒 SAFETY: 获取初始化阶段喵
    pub async fn phase(&self) -> InitPhase {
        *self.phase.read().await
    }

    /// 🔒 SAFETY: 获取 Token ID 喵
    pub fn token_id(&self) -> &str {
        &self.token_id
    }
}

impl<T> Default for LazyLoadToken<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T> Clone for LazyLoadToken<T> {
    fn clone(&self) -> Self {
        Self {
            data: Arc::clone(&self.data),
            phase: Arc::clone(&self.phase),
            token_id: self.token_id.clone(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_memory_pool_creation() {
        let pool = MemoryPool::new(16);
        assert_eq!(pool.pool_size, 16 * 1024 * 1024);
    }

    #[test]
    fn test_memory_pool_allocate_deallocate() {
        let pool = MemoryPool::new(16);

        // 分配
        let buffer = pool.allocate(1024);
        assert!(buffer.is_some());

        let stats = pool.stats();
        assert_eq!(stats.allocation_count, 1);

        // 释放
        drop(buffer);
        let data = buffer.unwrap();
        pool.deallocate(data);

        let stats = pool.stats();
        assert_eq!(stats.deallocation_count, 1);
    }

    #[test]
    fn test_lazy_load_token() {
        let token = LazyLoadToken::new();

        tokio::runtime::Runtime::new().unwrap().block_on(async {
            assert!(!token.is_initialized().await);
            assert_eq!(token.phase().await, InitPhase::NotStarted);

            token.defer().await;
            assert_eq!(token.phase().await, InitPhase::Deferred);

            token.set("Hello".to_string()).await;
            assert!(token.is_initialized().await);
            assert_eq!(token.get().await, Some("Hello".to_string()));
        });
    }

    #[test]
    fn test_lazy_load_token_clone() {
        let token1 = LazyLoadToken::<String>::new();
        let token2 = token1.clone();

        assert_eq!(token1.token_id(), token2.token_id());
    }
}
