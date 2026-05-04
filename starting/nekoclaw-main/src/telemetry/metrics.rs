//! Metrics 收集器 📈
//! 
//! @缪斯 的指标收集与存储实现喵

use rusqlite::{Connection, params, Result as SqliteResult};
use chrono::{DateTime, Utc};
use tracing::{debug, info};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};

/// 🔒 SAFETY: Metrics 配置喵
#[derive(Debug, Clone)]
pub struct MetricsConfig {
    pub db_path: String,
    pub monitor_interval_sec: u64,
}

/// 🔒 SAFETY: Agent 运行指标喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentMetrics {
    pub request_id: String,
    pub start_time: DateTime<Utc>,
    pub end_time: Option<DateTime<Utc>>,
    pub input_tokens: Option<u32>,
    pub output_tokens: Option<u32>,
    pub total_tokens: Option<u32>,
    pub model: String,
    pub status: String,
    pub error: Option<String>,
}

/// 🔒 SAFETY: 工具调用指标喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolMetrics {
    pub request_id: String,
    pub tool_name: String,
    pub call_time: DateTime<Utc>,
    pub duration_ms: u64,
    pub status: String,
    pub error: Option<String>,
}

/// 🔒 SAFETY: 系统指标喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SystemMetrics {
    pub sample_time: DateTime<Utc>,
    pub memory_mb: f64,
    pub cpu_usage: Option<f64>,
}

/// 🔒 SAFETY: Metrics 收集器喵
pub struct MetricsCollector {
    conn: Arc<Mutex<Connection>>,
}

// 🔒 SAFETY: 我们使用 Mutex 保护了非 Send 的 Connection，确保线程安全
unsafe impl Send for MetricsCollector {}
unsafe impl Sync for MetricsCollector {}

impl MetricsCollector {
    /// 🔒 SAFETY: 创建新的 Metrics Collector 喵
    pub async fn new(config: MetricsConfig) -> Result<Self, String> {
        info!("📊 初始化 Metrics Collector 喵...");
        
        let conn = Connection::open(&config.db_path)
            .map_err(|e| format!("打开数据库失败: {}", e))?;
        
        let collector = Self {
            conn: Arc::new(Mutex::new(conn)),
        };
        
        collector.init_tables()?;
        info!("✅ Metrics Collector 初始化完成喵！");
        Ok(collector)
    }
    
    fn init_tables(&self) -> Result<(), String> {
        let conn = self.conn.lock().unwrap();
        
        conn.execute_batch("
            CREATE TABLE IF NOT EXISTS agent_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                request_id TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT,
                input_tokens INTEGER,
                output_tokens INTEGER,
                total_tokens INTEGER,
                model TEXT NOT NULL,
                status TEXT NOT NULL,
                error TEXT
            );
            CREATE TABLE IF NOT EXISTS tool_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                request_id TEXT NOT NULL,
                tool_name TEXT NOT NULL,
                call_time TEXT NOT NULL,
                duration_ms INTEGER NOT NULL,
                status TEXT NOT NULL,
                error TEXT
            );
            CREATE TABLE IF NOT EXISTS system_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sample_time TEXT NOT NULL,
                memory_mb REAL NOT NULL,
                cpu_usage REAL
            );
        ").map_err(|e| format!("创建表失败: {}", e))?;
        
        Ok(())
    }
    
    pub fn record_agent_metrics(&self, metrics: &AgentMetrics) -> Result<(), String> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO agent_metrics (request_id, start_time, end_time, input_tokens, output_tokens, total_tokens, model, status, error) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                &metrics.request_id,
                metrics.start_time.to_rfc3339(),
                metrics.end_time.map(|t| t.to_rfc3339()),
                metrics.input_tokens,
                metrics.output_tokens,
                metrics.total_tokens,
                &metrics.model,
                &metrics.status,
                &metrics.error,
            ],
        ).map_err(|e| format!("插入失败: {}", e))?;
        Ok(())
    }
    
    pub fn record_tool_metrics(&self, metrics: &ToolMetrics) -> Result<(), String> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO tool_metrics (request_id, tool_name, call_time, duration_ms, status, error) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                &metrics.request_id,
                &metrics.tool_name,
                metrics.call_time.to_rfc3339(),
                metrics.duration_ms as i64,
                &metrics.status,
                &metrics.error,
            ],
        ).map_err(|e| format!("插入失败: {}", e))?;
        Ok(())
    }
    
    pub fn sample_system_metrics(&self) -> Result<(), String> {
        let memory_mb = get_memory_usage_mb();
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT INTO system_metrics (sample_time, memory_mb, cpu_usage) VALUES (?1, ?2, ?3)",
            params![Utc::now().to_rfc3339(), memory_mb, None::<f64>],
        ).map_err(|e| format!("插入失败: {}", e))?;
        debug!("📊 采样: 内存 {:.2}MB", memory_mb);
        Ok(())
    }
    
    pub fn get_recent_agent_metrics(&self, limit: u32) -> Result<Vec<AgentMetrics>, String> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT request_id, start_time, end_time, input_tokens, output_tokens, total_tokens, model, status, error FROM agent_metrics ORDER BY start_time DESC LIMIT ?1"
        ).map_err(|e| format!("查询失败: {}", e))?;
        
        let rows = stmt.query_map(params![limit], |row| {
            Ok(AgentMetrics {
                request_id: row.get(0)?,
                start_time: parse_time(&row.get::<_, String>(1)?),
                end_time: row.get::<_, Option<String>>(2)?.map(|s| parse_time(&s)),
                input_tokens: row.get(3)?,
                output_tokens: row.get(4)?,
                total_tokens: row.get(5)?,
                model: row.get(6)?,
                status: row.get(7)?,
                error: row.get(8)?,
            })
        }).map_err(|e| format!("解析失败: {}", e))?;
        
        rows.collect::<Result<Vec<_>, _>>().map_err(|e| format!("收集失败: {}", e))
    }
    
    pub fn get_recent_tool_metrics(&self, limit: u32) -> Result<Vec<ToolMetrics>, String> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT request_id, tool_name, call_time, duration_ms, status, error FROM tool_metrics ORDER BY call_time DESC LIMIT ?1"
        ).map_err(|e| format!("查询失败: {}", e))?;
        
        let rows = stmt.query_map(params![limit], |row| {
            Ok(ToolMetrics {
                request_id: row.get(0)?,
                tool_name: row.get(1)?,
                call_time: parse_time(&row.get::<_, String>(2)?),
                duration_ms: row.get::<_, i64>(3)? as u64,
                status: row.get(4)?,
                error: row.get(5)?,
            })
        }).map_err(|e| format!("解析失败: {}", e))?;
        
        rows.collect::<Result<Vec<_>, _>>().map_err(|e| format!("收集失败: {}", e))
    }
    
    pub fn get_recent_system_metrics(&self, limit: u32) -> Result<Vec<SystemMetrics>, String> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT sample_time, memory_mb, cpu_usage FROM system_metrics ORDER BY sample_time DESC LIMIT ?1"
        ).map_err(|e| format!("查询失败: {}", e))?;
        
        let rows = stmt.query_map(params![limit], |row| {
            Ok(SystemMetrics {
                sample_time: parse_time(&row.get::<_, String>(0)?),
                memory_mb: row.get(1)?,
                cpu_usage: row.get(2)?,
            })
        }).map_err(|e| format!("解析失败: {}", e))?;
        
        rows.collect::<Result<Vec<_>, _>>().map_err(|e| format!("收集失败: {}", e))
    }
    
    pub fn get_tool_statistics(&self) -> Result<Vec<(String, i64, f64)>, String> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT tool_name, COUNT(*) as call_count, AVG(duration_ms) as avg_duration FROM tool_metrics GROUP BY tool_name ORDER BY call_count DESC"
        ).map_err(|e| format!("查询失败: {}", e))?;
        
        let rows = stmt.query_map([], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?, row.get::<_, f64>(2)?))
        }).map_err(|e| format!("解析失败: {}", e))?;
        
        rows.collect::<Result<Vec<_>, _>>().map_err(|e| format!("收集失败: {}", e))
    }
}

fn parse_time(s: &str) -> DateTime<Utc> {
    DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&Utc)
}

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
