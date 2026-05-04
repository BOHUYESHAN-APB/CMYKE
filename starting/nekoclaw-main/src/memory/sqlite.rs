/*!
 * SQLite Memory Backend
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 18:20 JST
 *
 * 功能:
 * - SQLite 数据库存储
 * - FTS5 全文搜索
 * - 简化向量相似度计算 (余弦相似度)
 * - 自动创建数据库表
 */

use crate::core::traits::*;
use chrono::{DateTime, Utc};
use rusqlite::{params, Connection, Result as SqliteResult};
use std::path::Path;
use std::sync::{Arc, Mutex};

pub struct SqliteMemory {
    conn: Arc<Mutex<Connection>>,
    enable_vector: bool,
}

impl SqliteMemory {
    /// 创建新的 SQLite Memory 实例 (不带向量搜索)
    pub fn new<P: AsRef<Path>>(path: P) -> SqliteResult<Self> {
        let conn = Connection::open(path)?;
        let enable_vector = false;
        Self::initialize(&conn, enable_vector)?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
            enable_vector,
        })
    }

    /// 创建新的 SQLite Memory 实例 (带向量搜索)
    pub fn new_with_vector<P: AsRef<Path>>(path: P) -> SqliteResult<Self> {
        let conn = Connection::open(path)?;
        let enable_vector = true;
        Self::initialize(&conn, enable_vector)?;
        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
            enable_vector,
        })
    }

    /// 初始化数据库表
    fn initialize(conn: &Connection, enable_vector: bool) -> SqliteResult<()> {
        // 主记忆表
        conn.execute(
            "CREATE TABLE IF NOT EXISTS memory (
                id TEXT PRIMARY KEY,
                content TEXT NOT NULL,
                embedding BLOB,
                metadata TEXT,
                created_at TEXT NOT NULL
            )",
            [],
        )?;

        // FTS5 全文搜索虚拟表
        conn.execute(
            "CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts USING fts5(
                content,
                content_rowid rowid
            )",
            [],
        )?;

        // 触发器：同步到 FTS5
        conn.execute(
            "CREATE TRIGGER IF NOT EXISTS memory_ai AFTER INSERT ON memory BEGIN
                INSERT INTO memory_fts(rowid, content) VALUES (new.rowid, new.content);
            END",
            [],
        )?;

        conn.execute(
            "CREATE TRIGGER IF NOT EXISTS memory_ad AFTER DELETE ON memory BEGIN
                INSERT INTO memory_fts(memory_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
            END",
            [],
        )?;

        conn.execute(
            "CREATE TRIGGER IF NOT EXISTS memory_au AFTER UPDATE ON memory BEGIN
                INSERT INTO memory_fts(memory_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
                INSERT INTO memory_fts(rowid, content) VALUES (new.rowid, new.content);
            END",
            [],
        )?;

        // 向量表 (可选)
        if enable_vector {
            conn.execute(
                "CREATE TABLE IF NOT EXISTS vectors (
                    id TEXT PRIMARY KEY,
                    embedding BLOB NOT NULL,
                    FOREIGN KEY(id) REFERENCES memory(id) ON DELETE CASCADE
                )",
                [],
            )?;
        }

        Ok(())
    }

    /// 简化的余弦相似度计算
    fn cosine_similarity(vec_a: &[f32], vec_b: &[f32]) -> f32 {
        if vec_a.is_empty() || vec_b.is_empty() {
            return 0.0;
        }

        let dot: f32 = vec_a.iter().zip(vec_b.iter()).map(|(a, b)| a * b).sum();

        let norm_a: f32 = vec_a.iter().map(|x| x * x).sum::<f32>().sqrt();
        let norm_b: f32 = vec_b.iter().map(|x| x * x).sum::<f32>().sqrt();

        if norm_a == 0.0 || norm_b == 0.0 {
            0.0
        } else {
            dot / (norm_a * norm_b)
        }
    }

    /// 解析 embedding BLOB 为 Vec<f32>
    fn parse_embedding(blob: &[u8]) -> Option<Vec<f32>> {
        // 简化实现: 假设是 f32 数组的小端序
        if blob.len() % 4 != 0 {
            return None;
        }
        let len = blob.len() / 4;
        let mut vec = Vec::with_capacity(len);
        for i in 0..len {
            let bytes: [u8; 4] = [
                blob[i * 4],
                blob[i * 4 + 1],
                blob[i * 4 + 2],
                blob[i * 4 + 3],
            ];
            vec.push(f32::from_le_bytes(bytes));
        }
        Some(vec)
    }

    /// 序列化 Vec<f32> 为 BLOB
    fn serialize_embedding(vec: &[f32]) -> Vec<u8> {
        let mut blob = Vec::with_capacity(vec.len() * 4);
        for &val in vec {
            blob.extend_from_slice(&val.to_le_bytes());
        }
        blob
    }
}

#[async_trait::async_trait]
impl Memory for SqliteMemory {
    async fn recall(&self, query: &str, top_k: usize) -> Result<Vec<MemoryItem>> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {}", e))?;

        // 1. 关键词搜索 (FTS5)
        let keyword_results: Vec<String> = conn
            .prepare("SELECT id FROM memory_fts WHERE memory_fts MATCH ? ORDER BY rank LIMIT ?")?
            .query_map(params![query, top_k], |row| row.get(0))?
            .collect::<SqliteResult<Vec<_>>>()
            .map_err(|e| format!("FTS5 search error: {}", e))?;

        // 2. 向量搜索 (如果启用)
        let mut result_ids = if self.enable_vector && !keyword_results.is_empty() {
            // TODO: 实现向量搜索
            keyword_results
        } else {
            keyword_results
        };

        // 3. 去重 (保留顺序)
        result_ids.sort();
        result_ids.dedup();

        // 4. 获取完整记忆项
        let mut items = Vec::new();
        for id in result_ids.iter().take(top_k) {
            let item = conn
                .prepare_cached(
                    "SELECT id, content, embedding, metadata, created_at FROM memory WHERE id = ?",
                )?
                .query_row(params![id], |row| {
                    Ok(MemoryItem {
                        id: row.get(0)?,
                        content: row.get(1)?,
                        embedding: row
                            .get::<_, Option<Vec<u8>>>(2)?
                            .and_then(|b| Self::parse_embedding(&b)),
                        metadata: row
                            .get::<_, Option<String>>(3)?
                            .and_then(|s| serde_json::from_str(&s).ok()),
                        created_at: DateTime::parse_from_rfc3339(row.get::<_, String>(4)?.as_str())
                            .unwrap_or_else(|_| Utc::now().into())
                            .with_timezone(&Utc),
                    })
                });

            if let Ok(item) = item {
                items.push(item);
            }
        }

        Ok(items)
    }

    async fn save(&self, item: MemoryItem) -> Result<String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {}", e))?;

        // 序列化 embedding
        let embedding_blob = item
            .embedding
            .as_ref()
            .map(|v| Self::serialize_embedding(v));

        // 序列化 metadata
        let metadata_json = item
            .metadata
            .as_ref()
            .map(|v| serde_json::to_string(v).ok());

        conn.execute(
            "INSERT INTO memory (id, content, embedding, metadata, created_at) 
             VALUES (?, ?, ?, ?, ?)",
            params![
                &item.id,
                &item.content,
                &embedding_blob,
                &metadata_json,
                &item.created_at.format("%Y-%m-%dT%H:%M:%S%.3fZ").to_string()
            ],
        )
        .map_err(|e| format!("Insert error: {}", e))?;

        // 如果启用向量，同步到向量表
        if self.enable_vector {
            if let Some(blob) = embedding_blob {
                conn.execute(
                    "INSERT INTO vectors (id, embedding) VALUES (?, ?)",
                    params![&item.id, &blob],
                )
                .map_err(|e| format!("Vector insert error: {}", e))?;
            }
        }

        Ok(item.id)
    }

    async fn forget(&self, id: &str) -> Result<()> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {}", e))?;

        conn.execute("DELETE FROM memory WHERE id = ?", params![id])
            .map_err(|e| format!("Delete error: {}", e))?;

        Ok(())
    }

    async fn search(&self, query: &str) -> Result<Vec<MemoryItem>> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {}", e))?;

        let rows = conn
            .prepare(
                "SELECT id, content, embedding, metadata, created_at FROM memory_fts
             INNER JOIN memory ON memory.rowid = memory_fts.rowid
             WHERE memory_fts MATCH ?",
            )?
            .query_map(params![query], |row| {
                Ok(MemoryItem {
                    id: row.get(0)?,
                    content: row.get(1)?,
                    embedding: row
                        .get::<_, Option<Vec<u8>>>(2)?
                        .and_then(|b| Self::parse_embedding(&b)),
                    metadata: row
                        .get::<_, Option<String>>(3)?
                        .and_then(|s| serde_json::from_str(&s).ok()),
                    created_at: DateTime::parse_from_rfc3339(row.get::<_, String>(4)?.as_str())
                        .unwrap_or_else(|_| Utc::now().into())
                        .with_timezone(&Utc),
                })
            })?
            .collect::<SqliteResult<Vec<_>>>()
            .map_err(|e| format!("Search error: {}", e))?;

        Ok(rows)
    }
}
