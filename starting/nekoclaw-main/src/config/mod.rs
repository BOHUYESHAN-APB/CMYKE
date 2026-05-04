/*!
 * Configuration Module (Phase 6 - Extended)
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 19:40 JST
 *
 * 功能:
 * - 完全兼容 OpenClaw openclaw.json 格式
 * - Discord 多账户支持
 * - Provider 模型列表支持
 * - Agent 完整配置迁移
 * - IDENTITY.md / SOUL.md / AGENTS.md 加载
 */

use crate::core::traits::*;
use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use std::collections::HashMap;

/// OpenClaw 主配置 (完全兼容 openclaw.json)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenClawConfig {
    pub config: ConfigRoot,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConfigRoot {
    pub version: String,
    pub gateway: GatewayConfig,
    pub agents: AgentsConfig,
    pub models: ModelsConfig,
    pub channels: ChannelsConfig,
    pub features: Option<FeaturesConfig>,
}

/// Gateway 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GatewayConfig {
    pub host: Option<String>,
    pub port: Option<u16>,
    pub enabled: Option<bool>,
}

/// Features 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeaturesConfig {
    pub channels: Option<ChannelFeatures>,
    pub auth: Option<AuthFeatures>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelFeatures {
    pub discord: Option<bool>,
    pub telegram: Option<bool>,
    pub signal: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthFeatures {
    pub profiles_enabled: Option<bool>,
}

/// Agents 配置 (扩展)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentsConfig {
    pub default: Option<String>,
    pub agent: Option<HashMap<String, AgentProfile>>,
    pub defaults: Option<AgentDefaults>,  // OpenClaw 兼容
}

/// Agent 默认配置 (OpenClaw 格式)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentDefaults {
    pub model: Option<AgentModelConfig>,
    pub memory: Option<AgentMemoryConfig>,
    pub tools: Option<AgentToolsConfig>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentModelConfig {
    pub primary: Option<String>,
    pub fallback: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentMemoryConfig {
    pub enabled: Option<bool>,
    pub max_items: Option<usize>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentToolsConfig {
    pub enabled: Option<bool>,
}

/// Agent 完整配置 (Phase 6 扩展)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentProfile {
    /// Agent 标识符
    pub id: Option<String>,
    /// Agent 名称
    pub name: Option<String>,
    /// 模型配置
    pub model: Option<String>,
    /// 内存配置
    pub memory: Option<MemoryConfig>,
    /// 工具列表
    pub tools: Option<Vec<String>>,
    /// 提示词模板
    pub prompts: Option<AgentPrompts>,
    /// 能力配置
    pub capabilities: Option<AgentCapabilities>,
    /// 限制配置
    pub limits: Option<AgentLimits>,
}

/// Agent Prompts
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentPrompts {
    pub system: Option<String>,
    pub user: Option<String>,
    pub prefix: Option<String>,
    pub suffix: Option<String>,
}

/// Agent Capabilities
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentCapabilities {
    pub tools: Option<Vec<String>>,
    pub memory: Option<bool>,
    pub channels: Option<Vec<String>>,
}

/// Agent Limits
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentLimits {
    pub max_session_hours: Option<f64>,
    pub max_requests_per_hour: Option<usize>,
    pub max_token_limit: Option<usize>,
}

/// Memory 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MemoryConfig {
    pub kind: Option<String>,  // "sqlite", "vector"
    pub path: Option<String>,
    pub sqlite: Option<SQLiteConfig>,
    pub vector: Option<VectorConfig>,
}

/// SQLite 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SQLiteConfig {
    pub path: Option<String>,
    pub ftss_enabled: Option<bool>,
}

/// Vector 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VectorConfig {
    pub enabled: Option<bool>,
    pub dimensions: Option<usize>,
}

/// Models 配置 (扩展 - 支持模型列表)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelsConfig {
    pub default: Option<String>,
    pub providers: ProvidersConfig,
}

/// Providers 配置 (扩展)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProvidersConfig {
    pub anthropic: Option<ProviderConfig>,
    pub openai: Option<ProviderConfig>,
    pub openrouter: Option<ProviderConfig>,
    pub azure: Option<ProviderConfig>,
    pub gemini: Option<ProviderConfig>,
    pub nvidia: Option<ProviderConfig>,  // OpenClaw 使用
    pub fred: Option<FredConfig>,
}

/// Provider 配置 (扩展 - 支持模型列表)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderConfig {
    pub enabled: Option<bool>,
    pub apiKey: Option<String>,
    pub baseUrl: Option<String>,
    pub model: Option<String>,
    /// 模型列表 (OpenClaw 格式)
    pub models: Option<Vec<ProviderModel>>,
    pub auth: Option<ProviderAuth>,
}

/// Provider Model (模型列表项)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderModel {
    pub id: Option<String>,
    pub name: Option<String>,
    pub description: Option<String>,
    pub context_length: Option<usize>,
    pub pricing: Option<ModelPricing>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelPricing {
    pub input_price: Option<f64>,
    pub output_price: Option<f64>,
    pub currency: Option<String>,
}

/// Provider Auth (OAuth 等认证)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProviderAuth {
    pub kind: Option<String>,  // "bearer", "oauth2"
    pub profiles: Option<HashMap<String, AuthProfile>>,
}

/// Auth Profile
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthProfile {
    pub enabled: Option<bool>,
    pub client_id: Option<String>,
    pub redirect_uri: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FredConfig {
    pub apiKey: Option<String>,
}

/// Channels 配置 (扩展 - 支持多账户)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChannelsConfig {
    pub discord: Option<DiscordChannelConfig>,
    pub telegram: Option<TelegramChannelConfig>,
    pub signal: Option<SignalChannelConfig>,
}

/// Discord Channel 配置 (多账户支持)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscordChannelConfig {
    pub enabled: Option<bool>,
    /// 多账户配置
    pub accounts: Option<HashMap<String, DiscordAccountConfig>>,
}

/// Discord Account 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscordAccountConfig {
    /// Bot Token
    pub token: Option<String>,
    /// 允许的频道列表
    pub allowed_channels: Option<Vec<String>>,
    /// 允许的用户列表
    pub allowed_users: Option<Vec<String>>,
    /// 前缀
    pub prefix: Option<String>,
}

/// Telegram Channel 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TelegramChannelConfig {
    pub enabled: Option<bool>,
    pub token: Option<String>,
    pub allowed_users: Option<Vec<String>>,
}

/// Signal Channel 配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalChannelConfig {
    pub enabled: Option<bool>,
    pub data_dir: Option<String>,
}

/// 配置加载器 (Phase 6 扩展)
pub struct ConfigLoader {
    workspace: PathBuf,
    config: Option<OpenClawConfig>,
}

impl ConfigLoader {
    /// 创建新的配置加载器
    pub fn new(workspace: &str) -> Self {
        Self {
            workspace: PathBuf::from(workspace),
            config: None,
        }
    }

    /// 从 openclaw.json 加载配置
    pub fn load_openclaw_json(&mut self) -> Result<OpenClawConfig> {
        let config_path = self.workspace.join("openclaw.json");

        let config_content = std::fs::read_to_string(&config_path)
            .map_err(|e| format!("Failed to read openclaw.json: {}", e))?;

        let config: OpenClawConfig = serde_json::from_str(&config_content)
            .map_err(|e| format!("Failed to parse openclaw.json: {}", e))?;

        self.config = Some(config.clone());
        Ok(config)
    }

    /// 获取默认模型配置
    pub fn get_default_model(&self) -> Option<String> {
        self.config.as_ref()
            .and_then(|c| c.config.models.default.clone())
    }

    /// 获取 Provider 配置
    pub fn get_provider_config(&self, provider: &str) -> Option<ProviderConfig> {
        self.config.as_ref()
            .and_then(|c| {
                match provider {
                    "anthropic" => c.config.models.providers.anthropic.clone(),
                    "openai" => c.config.models.providers.openai.clone(),
                    "openrouter" => c.config.models.providers.openrouter.clone(),
                    "azure" => c.config.models.providers.azure.clone(),
                    "gemini" => c.config.models.providers.gemini.clone(),
                    "nvidia" => c.config.models.providers.nvidia.clone(),
                    _ => None,
                }
            })
    }

    /// 获取 Provider 模型列表 (Phase 6 新增)
    pub fn get_provider_models(&self, provider: &str) -> Option<Vec<ProviderModel>> {
        self.get_provider_config(provider)
            .and_then(|p| p.models)
    }

    /// 获取 Memory 配置
    pub fn get_memory_config(&self, agent: Option<&str>) -> Option<MemoryConfig> {
        self.config.as_ref()
            .and_then(|c| {
                if let Some(agent_name) = agent {
                    c.config.agents.agent.as_ref()
                        .and_then(|a: &HashMap<String, AgentProfile>| a.get(agent_name))
                        .and_then(|p| p.memory.clone())
                } else {
                    // 从 defaults 获取
                    c.config.agents.defaults.as_ref()
                        .map(|_| {
                            MemoryConfig {
                                kind: Some("sqlite".to_string()),
                                path: None,
                                sqlite: None,
                                vector: None,
                            }
                        })
                }
            })
    }

    /// 获取 Agent 完整配置 (Phase 6 新增)
    pub fn get_agent_config(&self, agent_name: &str) -> Option<AgentProfile> {
        self.config.as_ref()
            .and_then(|c| c.config.agents.agent.as_ref())
            .and_then(|a: &HashMap<String, AgentProfile>| a.get(agent_name).cloned())
    }

    /// 获取 Channel 配置
    pub fn get_channel_config(&self, channel: &str) -> Option<ChannelConfig> {
        self.config.as_ref()
            .and_then(|c| {
                match channel {
                    "discord" => c.config.channels.discord.as_ref().map(|d| ChannelConfig::Discord(d.clone())),
                    "telegram" => c.config.channels.telegram.as_ref().map(|t| ChannelConfig::Telegram(t.clone())),
                    "signal" => c.config.channels.signal.as_ref().map(|s| ChannelConfig::Signal(s.clone())),
                    _ => None,
                }
            })
    }

    /// 获取 Discord 账户配置 (Phase 6 新增)
    pub fn get_discord_account(&self, account_name: &str) -> Option<DiscordAccountConfig> {
        self.config.as_ref()
            .and_then(|c| c.config.channels.discord.as_ref())
            .and_then(|d| d.accounts.as_ref())
            .and_then(|a: &HashMap<String, DiscordAccountConfig>| a.get(account_name).cloned())
    }

    /// 获取所有 Discord 账户 (Phase 6 新增)
    pub fn get_discord_accounts(&self) -> HashMap<String, DiscordAccountConfig> {
        self.config.as_ref()
            .and_then(|c| c.config.channels.discord.as_ref())
            .and_then(|d| d.accounts.clone())
            .unwrap_or_default()
    }

    /// 获取 FRED API Key
    pub fn get_fred_api_key(&self) -> Option<String> {
        self.config.as_ref()
            .and_then(|c| c.config.models.providers.fred.as_ref())
            .and_then(|f| f.apiKey.clone())
    }

    /// 获取 Features 配置 (Phase 6 新增)
    pub fn get_features(&self) -> Option<FeaturesConfig> {
        self.config.as_ref()
            .and_then(|c| c.config.features.clone())
    }

    /// 检查功能是否启用 (Phase 6 新增)
    pub fn is_feature_enabled(&self, feature: &str) -> bool {
        match feature {
            "discord" => self.get_features()
                .and_then(|f| f.channels)
                .and_then(|c| c.discord)
                .unwrap_or(true),
            "telegram" => self.get_features()
                .and_then(|f| f.channels)
                .and_then(|c| c.telegram)
                .unwrap_or(false),
            "oauth" => self.get_features()
                .and_then(|f| f.auth)
                .and_then(|a| a.profiles_enabled)
                .unwrap_or(false),
            _ => false,
        }
    }
}

/// Channel 配置枚举
#[derive(Debug, Clone)]
pub enum ChannelConfig {
    Discord(DiscordChannelConfig),
    Telegram(TelegramChannelConfig),
    Signal(SignalChannelConfig),
}

/// IDENTITY.md / SOUL.md / AGENTS.md 加载器
pub struct IdentityLoader {
    workspace: PathBuf,
}

impl IdentityLoader {
    /// 创建新的 Identity 加载器
    pub fn new(workspace: &str) -> Self {
        Self {
            workspace: PathBuf::from(workspace),
        }
    }

    /// 加载 IDENTITY.md
    pub fn load_identity(&self) -> Result<String> {
        let path = self.workspace.join("IDENTITY.md");
        let content = std::fs::read_to_string(&path)
            .map_err(|e| format!("Failed to read IDENTITY.md: {}", e))?;
        Ok(content)
    }

    /// 加载 SOUL.md
    pub fn load_soul(&self) -> Result<String> {
        let path = self.workspace.join("SOUL.md");
        let content = std::fs::read_to_string(&path)
            .map_err(|e| format!("Failed to read SOUL.md: {}", e))?;
        Ok(content)
    }

    /// 加载 AGENTS.md
    pub fn load_agents(&self) -> Result<String> {
        let path = self.workspace.join("AGENTS.md");
        let content = std::fs::read_to_string(&path)
            .map_err(|e| format!("Failed to read AGENTS.md: {}", e))?;
        Ok(content)
    }

    /// 解析 AGENTS.md 提取 Discord ID 映射
    pub fn parse_agent_discord_ids(&self) -> Result<HashMap<String, String>> {
        let content = self.load_agents()?;
        let mut map = HashMap::new();

        for line in content.lines() {
            if line.contains("|") && line.contains("Discord ID") {
                continue;  // 跳过表头
            }

            if line.contains("|") {
                let parts: Vec<&str> = line.split('|').collect();
                if parts.len() >= 4 {
                    let agent = parts[1].trim().to_string();
                    let discord_id = parts[2].trim().to_string();
                    if !agent.is_empty() && !discord_id.is_empty() {
                        map.insert(agent, discord_id);
                    }
                }
            }
        }

        Ok(map)
    }
}

pub mod validator;

// 🔒 SAFETY: 重新导出公共接口喵
pub use validator::{
    ConfigValidator, ValidationRule, ValidationError,
    ValidationResult, MigrationValidator
};

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_loader_creation() {
        let loader = ConfigLoader::new("/tmp");
        assert_eq!(loader.workspace, PathBuf::from("/tmp"));
    }

    #[test]
    fn test_config_loader_discord_accounts() {
        let loader = ConfigLoader::new("/tmp");
        let accounts = loader.get_discord_accounts();
        assert_eq!(accounts.len(), 0, "新加载器应该没有账户");
    }

    #[test]
    fn test_feature_check() {
        let loader = ConfigLoader::new("/tmp");
        // 默认情况下，discord 应该是启用的
        assert!(loader.is_feature_enabled("discord"), "Discord 功能默认应该启用");
    }
}
