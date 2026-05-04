/*!
 * Memory Module
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 18:20 JST
 *
 * 功能:
 * - SQLite 后端 + FTS5 全文搜索
 * - 简化向量存储 (不依赖外部库)
 * - OpenClaw IDENTITY.md 兼容解析
 */

pub mod identity_parser;
pub mod sqlite;
pub mod vector;

// 重新导出所有子模块接口
pub use identity_parser::{IdentityParser, OpenClawIdentity};
pub use sqlite::SqliteMemory;
pub use vector::SimpleVectorDB;

use crate::core::traits::*;
use std::path::PathBuf;
use std::sync::Arc;

/// Memory 工厂 - 创建不同类型的 Memory 实现
pub struct MemoryFactory;

impl MemoryFactory {
    /// 创建 SQLite Memory 实例
    pub fn create_sqlite(path: &str) -> Result<Arc<dyn Memory>> {
        let memory = SqliteMemory::new(path)?;
        Ok(Arc::new(memory))
    }

    /// 带向量搜索的 SQLite Memory
    pub fn create_sqlite_with_vector(path: &str) -> Result<Arc<dyn Memory>> {
        let memory = SqliteMemory::new_with_vector(path)?;
        Ok(Arc::new(memory))
    }
}

/// MemoryManager 类型别名，用于兼容性
pub type MemoryManager = MemoryFactory;
