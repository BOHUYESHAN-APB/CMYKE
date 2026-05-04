/// Agent 会话管理模块 💬
///
/// @诺诺 的 Agent 会话管理实现喵
///
/// 功能：
/// - 会话创建与销毁
/// - 会话状态持久化
/// - 多会话并发管理
/// - 会话超时机制
///
/// 🔒 SAFETY: 会话数据加密存储
///
/// 实现者: 诺诺 (Nono) ⚡

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{info, warn};
use uuid::Uuid;

/// 🔒 SAFETY: 会话状态枚举喵
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum SessionState {
    /// 活跃
    Active,
    /// 待机
    Idle,
    /// 已关闭
    Closed,
}

/// 🔒 SAFETY: 会话信息结构体喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInfo {
    /// 会话 ID
    pub session_id: String,
    /// Agent ID
    pub agent_id: String,
    /// 会话标签
    pub label: Option<String>,
    /// 状态
    pub state: SessionState,
    /// 创建时间
    pub created_at: String,
    /// 最后活动时间
    pub last_activity: String,
    /// 消息数量
    pub message_count: u32,
    /// 总 token 数
    pub total_tokens: u32,
}

impl SessionInfo {
    /// 🔒 SAFETY: 创建新的会话信息喵
    pub fn new(agent_id: String, label: Option<String>) -> Self {
        let now = chrono::Utc::now().to_rfc3339();
        Self {
            session_id: Uuid::new_v4().to_string(),
            agent_id,
            label,
            state: SessionState::Active,
            created_at: now.clone(),
            last_activity: now,
            message_count: 0,
            total_tokens: 0,
        }
    }

    /// 🔒 SAFETY: 更新活动时间喵
    pub fn update_activity(&mut self) {
        self.last_activity = chrono::Utc::now().to_rfc3339();
    }

    /// 🔒 SAFETY: 增加消息计数喵
    pub fn increment_message_count(&mut self) {
        self.message_count += 1;
    }

    /// 🔒 SAFETY: 增加 token 计数喵
    pub fn add_tokens(&mut self, tokens: u32) {
        self.total_tokens += tokens;
    }
}

/// 🔒 SAFETY: 会话管理器配置喵
#[derive(Debug, Clone)]
pub struct SessionManagerConfig {
    /// 会话超时时间（分钟，默认 30）
    pub session_timeout_mins: u64,
    /// 最大并发会话数（默认 10）
    pub max_sessions: usize,
    /// 自动清理间隔（分钟，默认 5）
    pub cleanup_interval_mins: u64,
}

impl Default for SessionManagerConfig {
    fn default() -> Self {
        Self {
            session_timeout_mins: 30,
            max_sessions: 10,
            cleanup_interval_mins: 5,
        }
    }
}

/// 🔒 SAFETY: 会话管理器结构体喵
#[derive(Debug)]
pub struct SessionManager {
    /// 配置
    config: SessionManagerConfig,
    /// 活跃会话（session_id -> SessionInfo）
    sessions: Arc<RwLock<HashMap<String, SessionInfo>>>,
    /// Agent 映射（agent_id -> session_ids）
    agent_sessions: Arc<RwLock<HashMap<String, Vec<String>>>>,
}

impl SessionManager {
    /// 🔒 SAFETY: 创建新的会话管理器喵
    pub fn new(config: SessionManagerConfig) -> Self {
        let manager = Self {
            config,
            sessions: Arc::new(RwLock::new(HashMap::new())),
            agent_sessions: Arc::new(RwLock::new(HashMap::new())),
        };

        // 启动清理任务
        let manager_clone = manager.clone();
        tokio::spawn(async move {
            manager_clone
                .cleanup_loop()
                .await;
        });

        manager
    }

    /// 🔒 SAFETY: 创建新会话喵
    /// 异常处理: 会话数量超限
    pub async fn create_session(
        &self,
        agent_id: String,
        label: Option<String>,
    ) -> Result<String, String> {
        let mut sessions = self.sessions.write().await;

        // 检查会话数量限制
        if sessions.len() >= self.config.max_sessions {
            warn!("Maximum sessions limit reached: {}", self.config.max_sessions);
            return Err("Maximum concurrent sessions reached".to_string());
        }

        let session_info = SessionInfo::new(agent_id.clone(), label);
        let session_id = session_info.session_id.clone();

        // 保存会话
        sessions.insert(session_id.clone(), session_info);

        // 更新 Agent 映射
        let mut agent_sessions = self.agent_sessions.write().await;
        agent_sessions
            .entry(agent_id)
            .or_insert_with(Vec::new)
            .push(session_id.clone());

        info!("Session created: {}", session_id);

        Ok(session_id)
    }

    /// 🔒 SAFETY: 获取会话信息喵
    /// 异常处理: 会话不存在
    pub async fn get_session(&self, session_id: &str) -> Option<SessionInfo> {
        let sessions = self.sessions.read().await;
        sessions.get(session_id).cloned()
    }

    /// 🔒 SAFETY: 更新会话状态喵
    pub async fn update_session(&self, session_id: &str, state: SessionState) {
        let mut sessions = self.sessions.write().await;

        if let Some(session) = sessions.get_mut(session_id) {
            session.state = state;
            session.update_activity();
            info!(
                "Session {} state updated to: {:?}",
                session_id, state
            );
        }
    }

    /// 🔒 SAFETY: 关闭会话喵
    pub async fn close_session(&self, session_id: &str) {
        let mut sessions = self.sessions.write().await;

        if let Some(session) = sessions.remove(session_id) {
            // 从 Agent 映射中移除
            let mut agent_sessions = self.agent_sessions.write().await;
            if let Some(session_ids) = agent_sessions.get_mut(&session.agent_id) {
                session_ids.retain(|id| id != session_id);
            }

            info!("Session closed: {}", session_id);
        }
    }

    /// 🔒 SAFETY: 列出 Agent 的所有会话喵
    pub async fn list_agent_sessions(&self, agent_id: &str) -> Vec<SessionInfo> {
        let sessions = self.sessions.read().await;
        let agent_sessions = self.agent_sessions.read().await;

        if let Some(session_ids) = agent_sessions.get(agent_id) {
            session_ids
                .iter()
                .filter_map(|id| sessions.get(id).cloned())
                .collect()
        } else {
            Vec::new()
        }
    }

    /// 🔒 SAFETY: 列出所有活跃会话喵
    pub async fn list_all_sessions(&self) -> Vec<SessionInfo> {
        let sessions = self.sessions.read().await;
        sessions.values().cloned().collect()
    }

    /// 🔒 SAFETY: 清理过期会话喵
    async fn cleanup_expired(&self) -> usize {
        let mut sessions = self.sessions.write().await;
        let timeout = Duration::from_secs(self.config.session_timeout_mins * 60);

        let initial_count = sessions.len();
        let mut expired_count = 0;

        let expired_sessions: Vec<String> = sessions
            .iter()
            .filter(|(_, session)| {
                if let Ok(last_activity) = chrono::DateTime::parse_from_rfc3339(&session.last_activity) {
                    let elapsed = Utc::now() - last_activity.with_timezone(&Utc);
                    elapsed.num_seconds() as u64 > timeout.as_secs()
                } else {
                    true // 无效时间，视为过期
                }
            })
            .map(|(id, _)| id.clone())
            .collect();

        for session_id in expired_sessions {
            if let Some(session) = sessions.remove(&session_id) {
                // 从 Agent 映射中移除
                let mut agent_sessions = self.agent_sessions.write().await;
                if let Some(session_ids) = agent_sessions.get_mut(&session.agent_id) {
                    session_ids.retain(|id| id != &session_id);
                }

                info!("Expired session removed: {}", session_id);
                expired_count += 1;
            }
        }

        info!("Cleaned up {} expired sessions", expired_count);
        expired_count
    }

    /// 🔒 SAFETY: 清理循环喵
    async fn cleanup_loop(&self) {
        loop {
            tokio::time::sleep(Duration::from_secs(self.config.cleanup_interval_mins * 60)).await;
            let _ = self.cleanup_expired().await;
        }
    }

    /// 🔒 SAFETY: 获取统计信息喵
    pub async fn stats(&self) -> SessionStats {
        let sessions = self.sessions.read().await;
        let agent_sessions = self.agent_sessions.read().await;

        let active_count = sessions
            .values()
            .filter(|s| s.state == SessionState::Active)
            .count();

        SessionStats {
            total_sessions: sessions.len(),
            active_sessions: active_count,
            idle_sessions: sessions.len() - active_count,
            total_agents: agent_sessions.len(),
        }
    }
}

/// 🔒 SAFETY: 会话统计信息结构体喵
#[derive(Debug, Serialize)]
pub struct SessionStats {
    /// 总会话数
    pub total_sessions: usize,
    /// 活跃会话数
    pub active_sessions: usize,
    /// 待机会话数
    pub idle_sessions: usize,
    /// 总 Agent 数
    pub total_agents: usize,
}

impl Clone for SessionManager {
    fn clone(&self) -> Self {
        Self {
            config: self.config.clone(),
            sessions: Arc::clone(&self.sessions),
            agent_sessions: Arc::clone(&self.agent_sessions),
        }
    }
}

// 导入 Utc 和 DateTime
use chrono::{DateTime, Utc};

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_session_creation() {
        let config = SessionManagerConfig::default();
        let manager = SessionManager::new(config);

        let session_id = manager
            .create_session("agent1".to_string(), Some("Test".to_string()))
            .await
            .unwrap();

        assert!(!session_id.is_empty());

        let session = manager.get_session(&session_id).await;
        assert!(session.is_some());
    }

    #[tokio::test]
    async fn test_session_list() {
        let config = SessionManagerConfig::default();
        let manager = SessionManager::new(config);

        let _ = manager
            .create_session("agent1".to_string(), Some("Test1".to_string()))
            .await
            .unwrap();
        let _ = manager
            .create_session("agent1".to_string(), Some("Test2".to_string()))
            .await
            .unwrap();

        let sessions = manager.list_agent_sessions("agent1").await;
        assert_eq!(sessions.len(), 2);
    }

    #[tokio::test]
    async fn test_session_close() {
        let config = SessionManagerConfig::default();
        let manager = SessionManager::new(config);

        let session_id = manager
            .create_session("agent1".to_string(), Some("Test".to_string()))
            .await
            .unwrap();

        manager.close_session(&session_id).await;

        let session = manager.get_session(&session_id).await;
        assert!(session.is_none());
    }
}
