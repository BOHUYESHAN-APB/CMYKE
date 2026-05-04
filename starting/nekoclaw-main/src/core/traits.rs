/*!
 * Core Traits - 可插拔的抽象层
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 17:08 JST
 */

use chrono::{DateTime, Utc};
use futures::Stream;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::error::Error;
use std::pin::Pin;

pub type Result<T> = std::result::Result<T, Box<dyn Error + Send + Sync>>;
pub type StdResult<T, E> = std::result::Result<T, E>;

// ============================================================================
// Message Types
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub role: String, // "user", "assistant", "system"
    pub content: String,
}

impl Message {
    pub fn user(content: String) -> Self {
        Self {
            role: "user".to_string(),
            content,
        }
    }
    pub fn assistant(content: String) -> Self {
        Self {
            role: "assistant".to_string(),
            content,
        }
    }
    pub fn system(content: String) -> Self {
        Self {
            role: "system".to_string(),
            content,
        }
    }
}

// ============================================================================
// Provider Trait (AI Model Adapter)
// ============================================================================

#[async_trait::async_trait]
pub trait Provider: Send + Sync {
    async fn chat(&self, messages: &[Message]) -> Result<String>;
    async fn stream(
        &self,
        messages: &[Message],
    ) -> Pin<Box<dyn Stream<Item = Result<String>> + Send>>;
    fn name(&self) -> &str;
    fn supports_streaming(&self) -> bool;
}

// ============================================================================
// Channel Trait (Messaging Platform Adapter)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelEvent {
    pub source: String,    // "discord", "telegram", etc.
    pub sender_id: String, // 用户/频道 ID
    pub message: String,
    pub metadata: Option<Value>,
}

#[async_trait::async_trait]
pub trait Channel: Send + Sync {
    async fn send(&self, content: &str, target: Option<&str>) -> Result<()>;
    async fn receive(&self) -> Pin<Box<dyn Stream<Item = Result<ChannelEvent>> + Send>>;
    fn name(&self) -> &str;
    fn channel_type(&self) -> &str;
}

// ============================================================================
// Memory Trait (Memory System)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryItem {
    pub id: String,
    pub content: String,
    pub embedding: Option<Vec<f32>>,
    pub metadata: Option<Value>,
    pub created_at: DateTime<Utc>,
}

#[async_trait::async_trait]
pub trait Memory: Send + Sync {
    async fn recall(&self, query: &str, top_k: usize) -> Result<Vec<MemoryItem>>;
    async fn save(&self, item: MemoryItem) -> Result<String>; // 返回 ID
    async fn forget(&self, id: &str) -> Result<()>;
    async fn search(&self, query: &str) -> Result<Vec<MemoryItem>>;
}

// ============================================================================
// Tool Trait (Capability Extension)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolInput {
    pub name: String,
    pub args: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ToolOutput {
    pub success: bool,
    pub result: Value,
    pub error: Option<String>,
}

#[async_trait::async_trait]
pub trait Tool: Send + Sync {
    fn name(&self) -> &str;
    fn description(&self) -> &str;
    async fn execute(&self, args: Value) -> Result<ToolOutput>;
    fn is_dangerous(&self) -> bool; // 用于沙箱检查
}

// ============================================================================
// Identity Trait (Persona Engine)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Identity {
    pub name: String,
    pub personality: Personality,
    pub speech_patterns: SpeechPatterns,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Personality {
    pub tone: String,
    pub emoji: String,
    pub catchphrases: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpeechPatterns {
    pub prefix: Vec<String>,
    pub suffix: Vec<String>,
    pub prohibited: Vec<String>,
}

pub trait IdentityEngine: Send + Sync {
    fn load(&mut self, path: &std::path::Path) -> Result<Identity>;
    fn inject(&self, response: &str) -> String;
}

// ============================================================================
// Config Structure (aligned with Mika's config.json)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderConfig {
    pub base_url: String,
    pub api_key: String,
    #[serde(default = "default_timeout")]
    pub timeout: u64,
    #[serde(default = "default_max_retries")]
    pub max_retries: u8,
}

fn default_timeout() -> u64 { 60 }
fn default_max_retries() -> u8 { 3 }

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ProvidersConfig {
    #[serde(default)]
    pub nvidia: Option<ProviderConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscordConfig {
    pub enabled: bool,
    pub token: String,
    pub allowed_users: Vec<String>,
    pub require_mention: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    #[serde(default)]
    pub version: String,

    #[serde(default)]
    pub api_key: Option<String>,

    #[serde(default = "default_provider")]
    pub default_provider: String,

    #[serde(default = "default_model")]
    pub default_model: String,

    #[serde(default = "default_temperature")]
    pub default_temperature: f64,

    pub workspace: std::path::PathBuf,

    // NVIDIA 配置喵
    #[serde(default)]
    pub providers: Option<ProvidersConfig>,

    // Discord 配置喵
    #[serde(rename = "discord")]
    pub discord_config: Option<DiscordConfig>,

    // Gateway 配置喵
    pub gateway_port: Option<u16>,
    pub gateway_bind: Option<String>,
}

fn default_provider() -> String {
    "openai".to_string()
}
fn default_model() -> String {
    "gpt-4".to_string()
}
fn default_temperature() -> f64 {
    0.7
}
