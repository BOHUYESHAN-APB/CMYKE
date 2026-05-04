use rand::Rng;
/// Gateway 配对机制模块 🔐
///
/// @诺诺 的设备配对实现喵
///
/// 功能：
/// - 临时配对码生成
/// - 配对码验证
/// - 设备配对状态管理
/// - 会话 Token 生成
///
/// 🔒 SAFETY: 配对码有有效期，过期自动失效
///
/// 实现者: 诺诺 (Nono) ⚡
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;
use tracing::{error, info, warn};
use uuid::Uuid;

/// 🔒 SAFETY: 配对码配置结构体喵
#[derive(Debug, Clone)]
pub struct PairingConfig {
    /// 配对码长度
    pub code_length: usize,
    /// 配对码有效期（秒）
    pub code_ttl: u64,
    /// 数字字符集
    pub digits: Vec<char>,
    /// 会话 Token 有效期（秒）
    pub session_ttl: u64,
}

impl Default for PairingConfig {
    fn default() -> Self {
        Self {
            code_length: 6,
            code_ttl: 300, // 5 分钟
            digits: vec!['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'],
            session_ttl: 86400, // 24 小时
        }
    }
}

/// 🔒 SAFETY: 配对状态结构体喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum PairingStatus {
    /// 等待配对
    Pending,
    /// 配对成功
    Paired {
        session_token: String,
        device_name: String,
    },
    /// 配对失败
    Failed,
    /// 已过期
    Expired,
}

/// 🔒 SAFETY: 配对信息结构体喵
#[derive(Debug, Clone)]
struct PairingInfo {
    /// 配对码
    code: String,
    /// 创建时间
    created_at: Instant,
    /// 配对状态
    status: PairingStatus,
    /// 设备名称
    device_name: Option<String>,
}

/// 🔒 SAFETY: 配对请求结构体喵
#[derive(Debug, Deserialize)]
pub struct PairingRequest {
    /// 配对码
    code: String,
    /// 设备名称（可选）
    device_name: Option<String>,
}

/// 🔒 SAFETY: 配对响应结构体喵
#[derive(Debug, Serialize)]
pub struct PairingResponse {
    /// 是否成功
    success: bool,
    /// 消息
    message: String,
    /// 会话 Token（配对成功时）
    session_token: Option<String>,
}

/// 🔒 SAFETY: 配对管理器结构体喵
#[derive(Debug, Clone)]
pub struct PairingManager {
    /// 配置
    config: PairingConfig,
    /// 活跃配对码（code -> PairingInfo）
    active_pairings: Arc<RwLock<HashMap<String, PairingInfo>>>,
}

impl PairingManager {
    /// 🔒 SAFETY: 创建新的配对管理器喵
    pub fn new(config: PairingConfig) -> Self {
        Self {
            config,
            active_pairings: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    /// 🔒 SAFETY: 生成配对码喵
    /// 异常处理: 随机数生成失败时返回错误
    pub fn generate_code(&self) -> String {
        let mut code = String::with_capacity(self.config.code_length);
        let mut rng = rand::thread_rng();

        for _ in 0..self.config.code_length {
            let idx = rng.gen_range(0..self.config.digits.len());
            code.push(self.config.digits[idx]);
        }

        code
    }

    /// 🔒 SAFETY: 创建新的配对码喵
    /// 异常处理: 重复码冲突时重新生成
    pub async fn create_pairing(&self) -> Result<String, String> {
        let mut attempt = 0;
        let max_attempts = 10;

        while attempt < max_attempts {
            let code = self.generate_code();
            let mut pairings = self.active_pairings.write().await;

            // 检查是否重复
            if !pairings.contains_key(&code) {
                pairings.insert(
                    code.clone(),
                    PairingInfo {
                        code: code.clone(),
                        created_at: Instant::now(),
                        status: PairingStatus::Pending,
                        device_name: None,
                    },
                );

                info!("Created pairing code: {}", code);
                return Ok(code);
            }

            attempt += 1;
        }

        Err("Failed to generate unique code after multiple attempts".to_string())
    }

    /// 🔒 SAFETY: 验证配对码喵
    /// 异常处理: 无效码、过期码、已配对
    pub async fn verify_pairing(
        &self,
        code: &str,
        device_name: Option<String>,
    ) -> Result<String, String> {
        let mut pairings = self.active_pairings.write().await;

        // 检查配对码是否存在
        let pairing = pairings
            .get(code)
            .ok_or_else(|| "Invalid pairing code".to_string())?;

        // 检查是否已过期
        if pairing.created_at.elapsed() > Duration::from_secs(self.config.code_ttl) {
            if let Some(mut info) = pairings.remove(code) {
                info.status = PairingStatus::Expired;
                pairings.insert(code.to_string(), info);
            }
            return Err("Pairing code has expired".to_string());
        }

        // 检查是否已配对
        match &pairing.status {
            PairingStatus::Paired { .. } => {
                return Err("This code has already been paired".to_string());
            }
            PairingStatus::Expired => {
                return Err("Pairing code has expired".to_string());
            }
            PairingStatus::Failed => {
                return Err("Pairing failed".to_string());
            }
            PairingStatus::Pending => {
                // 配对成功
                let session_token = Uuid::new_v4().to_string();
                let device_name_clone = device_name
                    .as_ref()
                    .cloned()
                    .unwrap_or_else(|| "unknown".to_string());

                let updated_info = PairingInfo {
                    code: code.to_string(),
                    created_at: pairing.created_at,
                    status: PairingStatus::Paired {
                        session_token: session_token.clone(),
                        device_name: device_name_clone.clone(),
                    },
                    device_name,
                };

                pairings.insert(code.to_string(), updated_info);

                info!("Pairing successful for code: {}", code);
                Ok(session_token)
            }
        }
    }

    /// 🔒 SAFETY: 获取配对状态喵
    /// 异常处理: 配对码不存在时返回 None
    pub async fn get_pairing_status(&self, code: &str) -> Option<PairingStatus> {
        let pairings = self.active_pairings.read().await;

        let pairing = pairings.get(code)?;
        Some(pairing.status.clone())
    }

    /// 🔒 SAFETY: 清理过期配对喵
    /// 定期调用以释放内存
    pub async fn cleanup_expired(&self) -> usize {
        let mut pairings = self.active_pairings.write().await;
        let ttl = Duration::from_secs(self.config.code_ttl);

        let initial_count = pairings.len();
        let mut expired_count = 0;

        pairings.retain(|code, pairing| {
            if pairing.created_at.elapsed() > ttl {
                info!("Cleaning up expired pairing: {}", code);
                expired_count += 1;
                false
            } else {
                true
            }
        });

        info!("Cleaned up {} expired pairings", expired_count);
        expired_count
    }

    /// 🔒 SAFETY: 获取活跃配对数量喵
    pub async fn active_count(&self) -> usize {
        self.active_pairings.read().await.len()
    }

    /// 🔒 SAFETY: 撤销指定配对喵
    /// 异常处理: 配对码不存在时静默返回
    pub async fn revoke_pairing(&self, code: &str) {
        let mut pairings = self.active_pairings.write().await;

        if let Some(mut pairing) = pairings.remove(code) {
            pairing.status = PairingStatus::Failed;
            info!("Revoked pairing: {}", code);
        }
    }

    /// 🔒 SAFETY: 验证会话 Token喵
    /// 异常处理: 无效 Token、过期 Token
    pub async fn verify_session_token(&self, token: &str) -> Result<String, String> {
        let pairings = self.active_pairings.read().await;

        for (code, pairing) in pairings.iter() {
            if let PairingStatus::Paired {
                session_token,
                device_name,
            } = &pairing.status
            {
                if session_token == token {
                    // 检查会话是否过期
                    if pairing.created_at.elapsed() > Duration::from_secs(self.config.session_ttl) {
                        return Err("Session token has expired".to_string());
                    }
                    return Ok(device_name.to_string());
                }
            }
        }

        Err("Invalid session token".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio;

    #[tokio::test]
    async fn test_code_generation() {
        let config = PairingConfig::default();
        let manager = PairingManager::new(config);

        let code = manager.generate_code();
        assert_eq!(code.len(), 6);
        assert!(code.chars().all(|c| c.is_ascii_digit()));
    }

    #[tokio::test]
    async fn test_create_pairing() {
        let config = PairingConfig::default();
        let manager = PairingManager::new(config);

        let code = manager.create_pairing().await.unwrap();
        assert_eq!(code.len(), 6);
        assert_eq!(manager.active_count().await, 1);
    }

    #[tokio::test]
    async fn test_verify_pairing() {
        let config = PairingConfig::default();
        let manager = PairingManager::new(config);

        let code = manager.create_pairing().await.unwrap();
        let session_token = manager
            .verify_pairing(&code, Some("Test Device".to_string()))
            .await
            .unwrap();

        assert!(!session_token.is_empty());
        assert_eq!(manager.active_count().await, 1);
    }

    #[tokio::test]
    async fn test_invalid_pairing() {
        let config = PairingConfig::default();
        let manager = PairingManager::new(config);

        let result = manager.verify_pairing("000000", None).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_cleanup_expired() {
        let mut config = PairingConfig::default();
        config.code_ttl = 0; // 立即过期
        let manager = PairingManager::new(config);

        manager.create_pairing().await.unwrap();
        let count = manager.cleanup_expired().await;

        assert_eq!(count, 1);
        assert_eq!(manager.active_count().await, 0);
    }
}
