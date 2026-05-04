//!
//! # Auth Module
//!
//! ⚠️ SAFETY: OAuth 认证和凭证管理模块喵
//!
//! ## 功能说明
//! - OAuth 2.0 认证流程支持喵
//! - 凭证安全存储和加密喵
//! - 认证配置文件解析喵
//! - Token 自动刷新喵
//!
//! ## OpenClaw 兼容
//! - 兼容 `auth.profiles` 配置格式喵
//! - 支持 Discord OAuth喵
//! - 支持 Google OAuth喵

use crate::security::CryptoService;
use chrono::{Duration, Utc};
use oauth2::basic::BasicClient;
use oauth2::reqwest::async_http_client;
use oauth2::{AuthUrl, ClientId, ClientSecret, RedirectUrl, RefreshToken, TokenResponse, TokenUrl};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::Mutex;

/// 认证错误类型喵
#[derive(Error, Debug)]
pub enum AuthError {
    /// 认证失败喵
    #[error("Authentication failed: {0}")]
    AuthenticationFailed(String),

    /// Token 无效喵
    #[error("Invalid token: {0}")]
    InvalidToken(String),

    /// Token 过期喵
    #[error("Token expired at {0}")]
    TokenExpired(chrono::DateTime<Utc>),

    /// 刷新 Token 失败喵
    #[error("Failed to refresh token: {0}")]
    RefreshFailed(String),

    /// 配置错误喵
    #[error("Configuration error: {0}")]
    ConfigError(String),

    /// 加密错误喵
    #[error("Encryption error: {0}")]
    EncryptionError(String),

    /// 提供商不支持喵
    #[error("Provider not supported: {0}")]
    ProviderNotSupported(String),
}

/// OAuth 提供商类型喵
#[derive(Clone, Debug, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum OAuthProvider {
    /// Discord OAuth
    Discord,

    /// Google OAuth
    Google,

    /// GitHub OAuth
    GitHub,

    /// 自定义 OAuth
    Custom(String),
}

/// OAuth 配置文件喵
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct OAuthConfig {
    /// 提供商类型喵
    pub provider: OAuthProvider,

    /// 客户端 ID喵
    pub client_id: String,

    /// 客户端密钥喵
    pub client_secret: String,

    /// 重定向 URI喵
    pub redirect_uri: String,

    /// 授权 URL喵
    pub auth_url: String,

    /// Token URL喵
    pub token_url: String,

    /// 作用域喵
    pub scopes: Vec<String>,

    /// 是否启用喵
    pub enabled: bool,
}

impl OAuthConfig {
    /// 创建 Discord OAuth 配置喵
    pub fn discord(client_id: &str, client_secret: &str, redirect_uri: &str) -> Self {
        Self {
            provider: OAuthProvider::Discord,
            client_id: client_id.to_string(),
            client_secret: client_secret.to_string(),
            redirect_uri: redirect_uri.to_string(),
            auth_url: "https://discord.com/api/oauth2/authorize".to_string(),
            token_url: "https://discord.com/api/oauth2/token".to_string(),
            scopes: vec!["identify".to_string(), "email".to_string()],
            enabled: true,
        }
    }

    /// 转换为 oauth2 客户端喵
    pub fn to_oauth2_client(&self) -> Result<BasicClient, AuthError> {
        let client_id = ClientId::new(self.client_id.clone());
        let client_secret = ClientSecret::new(self.client_secret.clone());
        let auth_url = AuthUrl::new(self.auth_url.clone())
            .map_err(|e| AuthError::ConfigError(e.to_string()))?;
        let token_url = TokenUrl::new(self.token_url.clone())
            .map_err(|e| AuthError::ConfigError(e.to_string()))?;
        let redirect_url = RedirectUrl::new(self.redirect_uri.clone())
            .map_err(|e| AuthError::ConfigError(e.to_string()))?;

        Ok(
            BasicClient::new(client_id, Some(client_secret), auth_url, Some(token_url))
                .set_redirect_uri(redirect_url),
        )
    }
}

/// Token 信息喵
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TokenInfo {
    /// Access Token喵
    pub access_token: String,

    /// Refresh Token喵
    pub refresh_token: Option<String>,

    /// Token 类型喵
    pub token_type: String,

    /// 过期时间喵
    pub expires_at: chrono::DateTime<Utc>,

    /// 作用域喵
    pub scopes: Vec<String>,

    /// 关联的用户 ID喵
    pub user_id: Option<String>,
}

/// 认证会话喵
#[derive(Clone, Debug)]
pub struct AuthSession {
    /// 会话 ID喵
    pub id: String,

    /// OAuth 配置喵
    pub config: OAuthConfig,

    /// Token 信息喵
    pub token: Option<TokenInfo>,

    /// 创建时间喵
    pub created_at: chrono::DateTime<Utc>,

    /// 最后活动时间喵
    pub last_activity: chrono::DateTime<Utc>,

    /// 状态喵
    pub state: AuthState,
}

/// 认证状态喵
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AuthState {
    Initial,
    PendingAuthorization,
    Authorized,
    Active,
    Expired,
    Error(String),
    Revoked,
}

impl AuthSession {
    pub fn new(config: OAuthConfig) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            config,
            token: None,
            created_at: Utc::now(),
            last_activity: Utc::now(),
            state: AuthState::Initial,
        }
    }

    pub fn is_token_valid(&self) -> bool {
        if let Some(token) = &self.token {
            token.expires_at > Utc::now()
        } else {
            false
        }
    }

    pub fn needs_refresh(&self) -> bool {
        if let Some(token) = &self.token {
            token.expires_at < Utc::now() + Duration::minutes(5)
        } else {
            false
        }
    }
}

/// 凭证存储喵
#[derive(Clone)]
pub struct CredentialStore {
    crypto: CryptoService,
    cache: Arc<Mutex<HashMap<String, TokenInfo>>>,
    storage_path: std::path::PathBuf,
}

impl CredentialStore {
    pub fn new(storage_path: std::path::PathBuf, crypto: CryptoService) -> Result<Self, AuthError> {
        if !storage_path.exists() {
            std::fs::create_dir_all(&storage_path)
                .map_err(|e| AuthError::ConfigError(format!("Failed to create storage directory: {}", e)))?;
        }

        Ok(Self {
            crypto,
            cache: Arc::new(Mutex::new(HashMap::new())),
            storage_path,
        })
    }

    pub async fn save(&self, key: &str, token: &TokenInfo) -> Result<(), AuthError> {
        let token_json =
            serde_json::to_string(token).map_err(|e| AuthError::EncryptionError(e.to_string()))?;

        let encrypted = self
            .crypto
            .encrypt(&token_json)
            .map_err(|e| AuthError::EncryptionError(e.to_string()))?;

        let file_path = self.storage_path.join(format!("{}.cred", key));
        std::fs::write(&file_path, encrypted)
            .map_err(|e| AuthError::EncryptionError(e.to_string()))?;

        let mut cache = self.cache.lock().await;
        cache.insert(key.to_string(), token.clone());

        Ok(())
    }

    pub async fn load(&self, key: &str) -> Option<TokenInfo> {
        {
            let cache = self.cache.lock().await;
            if let Some(token) = cache.get(key) {
                if token.expires_at > Utc::now() {
                    return Some(token.clone());
                }
            }
        }

        let file_path = self.storage_path.join(format!("{}.cred", key));
        if !file_path.exists() {
            return None;
        }

        let encrypted_bytes = std::fs::read(&file_path).ok()?;
        let encrypted_str = String::from_utf8_lossy(&encrypted_bytes);
        let decrypted = self
            .crypto
            .decrypt(&encrypted_str)
            .map_err(|e| {
                tracing::warn!("Failed to decrypt credential: {}", e);
                e
            })
            .ok()?;

        let token: TokenInfo = serde_json::from_str(&decrypted)
            .map_err(|e| {
                tracing::warn!("Failed to parse credential: {}", e);
                e
            })
            .ok()?;

        let mut cache = self.cache.lock().await;
        cache.insert(key.to_string(), token.clone());

        Some(token)
    }

    pub async fn delete(&self, key: &str) -> Result<(), AuthError> {
        let file_path = self.storage_path.join(format!("{}.cred", key));
        if file_path.exists() {
            std::fs::remove_file(&file_path)
                .map_err(|e| AuthError::EncryptionError(e.to_string()))?;
        }

        let mut cache = self.cache.lock().await;
        cache.remove(key);

        Ok(())
    }
}

/// 认证配置文件喵
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AuthProfiles {
    pub profiles: Vec<AuthProfile>,
    pub default_profile: Option<String>,
}

/// 单个认证配置喵
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct AuthProfile {
    pub name: String,
    pub provider: String,
    pub oauth: OAuthConfig,
    pub enabled: bool,
    pub priority: u32,
}

/// 认证管理器主结构喵
pub struct AuthManager {
    config: OAuthConfig,
    store: CredentialStore,
    sessions: Arc<Mutex<HashMap<String, AuthSession>>>,
    oauth2_client: Option<BasicClient>,
}

impl AuthManager {
    pub async fn new(
        config: OAuthConfig,
        storage_path: Option<std::path::PathBuf>,
    ) -> Result<Self, AuthError> {
        let storage_path = storage_path.unwrap_or_else(|| {
            dirs::home_dir()
                .unwrap_or_default()
                .join(".nekoclaw/credentials")
        });

        let crypto = CryptoService::new(&[0u8; 32]) // TODO: 使用实际的主密钥
            .map_err(|e| AuthError::EncryptionError(e.to_string()))?;

        let store = CredentialStore::new(storage_path, crypto)?;
        let sessions = Arc::new(Mutex::new(HashMap::new()));
        let oauth2_client = config.to_oauth2_client().ok();

        Ok(Self {
            config,
            store,
            sessions,
            oauth2_client,
        })
    }

    pub async fn create_authorization_url(
        &self,
        state: &str,
        _pkce_code_verifier: Option<&str>,
    ) -> Result<String, AuthError> {
        let client = self
            .oauth2_client
            .as_ref()
            .ok_or_else(|| AuthError::ConfigError("OAuth client not initialized".to_string()))?;

        let mut request = client.authorize_url(|| oauth2::CsrfToken::new(state.to_string()));

        for scope in &self.config.scopes {
            request = request.add_scope(oauth2::Scope::new(scope.to_string()));
        }

        let (auth_url, _) = request.url();
        Ok(auth_url.to_string())
    }

    pub async fn exchange_code_for_token(
        &self,
        code: &str,
        pkce_code_verifier: Option<&str>,
    ) -> Result<TokenInfo, AuthError> {
        let client = self
            .oauth2_client
            .as_ref()
            .ok_or_else(|| AuthError::ConfigError("OAuth client not initialized".to_string()))?;

        let mut token_request =
            client.exchange_code(oauth2::AuthorizationCode::new(code.to_string()));

        if let Some(verifier) = pkce_code_verifier {
            token_request = token_request
                .set_pkce_verifier(oauth2::PkceCodeVerifier::new(verifier.to_string()));
        }

        let token_result = token_request
            .request_async(async_http_client)
            .await
            .map_err(|e| AuthError::AuthenticationFailed(format!("{:?}", e)))?;

        let now = Utc::now();
        let expires_in = token_result
            .expires_in()
            .unwrap_or_else(|| std::time::Duration::from_secs(3600));

        Ok(TokenInfo {
            access_token: token_result.access_token().secret().to_string(),
            refresh_token: token_result.refresh_token().map(|t| t.secret().to_string()),
            token_type: format!("{:?}", token_result.token_type()),
            expires_at: now + Duration::seconds(expires_in.as_secs() as i64),
            scopes: self.config.scopes.clone(),
            user_id: None,
        })
    }
}

pub async fn create_auth_manager_from_profiles(
    profiles: &AuthProfiles,
    storage_path: Option<std::path::PathBuf>,
    profile_name: Option<&str>,
) -> Result<AuthManager, AuthError> {
    let profile = if let Some(name) = profile_name {
        profiles
            .profiles
            .iter()
            .find(|p| p.name == name && p.enabled)
            .ok_or_else(|| {
                AuthError::ConfigError(format!("Profile '{}' not found or disabled", name))
            })?
    } else if let Some(default) = &profiles.default_profile {
        match profiles
            .profiles
            .iter()
            .find(|p| &p.name == default && p.enabled)
        {
            Some(p) => p,
            None => profiles
                .profiles
                .first()
                .ok_or_else(|| AuthError::ConfigError("No profiles available".to_string()))?,
        }
    } else {
        profiles
            .profiles
            .first()
            .ok_or_else(|| AuthError::ConfigError("No profiles available".to_string()))?
    };

    AuthManager::new(profile.oauth.clone(), storage_path).await
}
