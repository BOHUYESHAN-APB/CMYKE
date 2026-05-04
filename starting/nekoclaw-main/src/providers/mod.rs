pub mod anthropic;
/// Provider 适配器模块导出 🤖
///
/// @诺诺 的 Provider 模块统一入口喵
///
/// 功能：
/// - 导出所有 Provider 实现
/// - 统一错误处理
/// - Provider 工厂函数
///
/// 🔒 SAFETY: 模块级访问控制，防止非法访问
///
/// 模块作者: 诺诺 (Nono) ⚡
pub mod openai;
pub mod openrouter;

// 🔒 SAFETY: 重新导出公共接口喵
pub use anthropic::{
    AnthropicClient, AnthropicConfig, ClaudeRequest, ClaudeResponse, ContentBlock,
};
pub use openai::{
    ChatRequest, ChatResponse, Choice, Message, OpenAIClient, OpenAIConfig, OpenAIError, Usage,
};
pub use openrouter::{
    ModelInfo, OpenRouterClient, OpenRouterConfig, OpenRouterRequest, Pricing, ProviderPreference,
};

// 🔒 SAFETY: 统一错误类型喵
pub use openai::ProviderError;

// 🔒 SAFETY: 为了兼容性，定义类型别名
pub type ProviderManager = ProviderFactory;

/// 🔒 SAFETY: Provider 枚举喵
/// 用于在运行时选择不同的 LLM 提供商
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProviderType {
    /// OpenAI（GPT 系列）
    OpenAI,
    /// Anthropic（Claude 系列）
    Anthropic,
    /// OpenRouter（聚合提供商）
    OpenRouter,
}

impl ProviderType {
    /// 🔒 SAFETY: 从字符串解析 Provider 类型喵
    /// 支持大小写不敏感
    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "openai" | "gpt" => Some(ProviderType::OpenAI),
            "anthropic" | "claude" => Some(ProviderType::Anthropic),
            "openrouter" => Some(ProviderType::OpenRouter),
            _ => None,
        }
    }

    /// 🔒 SAFETY: 转换为字符串喵
    pub fn as_str(&self) -> &'static str {
        match self {
            ProviderType::OpenAI => "openai",
            ProviderType::Anthropic => "anthropic",
            ProviderType::OpenRouter => "openrouter",
        }
    }
}

/// 🔒 SAFETY: Provider 工厂结构体喵
/// 统一创建和管理所有 Provider 客户端
#[derive(Debug, Clone)]
pub struct ProviderFactory {
    /// OpenAI 配置
    openai_config: Option<OpenAIConfig>,
    /// Anthropic 配置
    anthropic_config: Option<AnthropicConfig>,
    /// OpenRouter 配置
    openrouter_config: Option<OpenRouterConfig>,
}

impl Default for ProviderFactory {
    /// 🔒 SAFETY: 默认工厂（无配置）喵
    fn default() -> Self {
        Self {
            openai_config: None,
            anthropic_config: None,
            openrouter_config: None,
        }
    }
}

impl ProviderFactory {
    /// 🔒 SAFETY: 创建新的工厂喵
    pub fn new() -> Self {
        Self::default()
    }

    /// 🔒 SAFETY: 设置 OpenAI 配置喵
    /// 安全边界: API Key 必须通过安全模块解密后传入
    pub fn with_openai_config(mut self, config: OpenAIConfig) -> Self {
        self.openai_config = Some(config);
        self
    }

    /// 🔒 SAFETY: 设置 Anthropic 配置喵
    pub fn with_anthropic_config(mut self, config: AnthropicConfig) -> Self {
        self.anthropic_config = Some(config);
        self
    }

    /// 🔒 SAFETY: 设置 OpenRouter 配置喵
    pub fn with_openrouter_config(mut self, config: OpenRouterConfig) -> Self {
        self.openrouter_config = Some(config);
        self
    }

    /// 🔒 SAFETY: 创建 OpenAI 客户端喵
    /// 异常处理: 如果配置不存在则返回错误
    pub fn create_openai_client(&self) -> Result<OpenAIClient, ProviderError> {
        self.openai_config
            .as_ref()
            .map(|config| OpenAIClient::new(config.clone()))
            .ok_or_else(|| ProviderError::ApiError("OpenAI configuration not found".to_string()))
    }

    /// 🔒 SAFETY: 创建 Anthropic 客户端喵
    pub fn create_anthropic_client(&self) -> Result<AnthropicClient, ProviderError> {
        self.anthropic_config
            .as_ref()
            .map(|config| AnthropicClient::new(config.clone()))
            .ok_or_else(|| ProviderError::ApiError("Anthropic configuration not found".to_string()))
    }

    /// 🔒 SAFETY: 创建 OpenRouter 客户端喵
    pub fn create_openrouter_client(&self) -> Result<OpenRouterClient, ProviderError> {
        self.openrouter_config
            .as_ref()
            .map(|config| OpenRouterClient::new(config.clone()))
            .ok_or_else(|| {
                ProviderError::ApiError("OpenRouter configuration not found".to_string())
            })
    }

    /// 🔒 SAFETY: 根据 Provider 类型创建客户端喵
    /// 异常处理: 配置不存在或类型不支持时返回错误
    pub fn create_client(
        &self,
        provider_type: ProviderType,
    ) -> Result<ProviderClient, ProviderError> {
        match provider_type {
            ProviderType::OpenAI => {
                let client = self.create_openai_client()?;
                Ok(ProviderClient::OpenAI(client))
            }
            ProviderType::Anthropic => {
                let client = self.create_anthropic_client()?;
                Ok(ProviderClient::Anthropic(client))
            }
            ProviderType::OpenRouter => {
                let client = self.create_openrouter_client()?;
                Ok(ProviderClient::OpenRouter(client))
            }
        }
    }
}

/// 🔒 SAFETY: Provider 客户端枚举喵
/// 封装所有 Provider 客户端类型
#[derive(Debug, Clone)]
pub enum ProviderClient {
    /// OpenAI 客户端
    OpenAI(OpenAIClient),
    /// Anthropic 客户端
    Anthropic(AnthropicClient),
    /// OpenRouter 客户端
    OpenRouter(OpenRouterClient),
}

/// 🔒 SAFETY: ProviderClient 统一接口喵
/// 提供跨 Provider 的统一调用方式（简化版）
impl ProviderClient {
    /// 🔒 SAFETY: 提供商类型喵
    pub fn provider_type(&self) -> ProviderType {
        match self {
            ProviderClient::OpenAI(_) => ProviderType::OpenAI,
            ProviderClient::Anthropic(_) => ProviderType::Anthropic,
            ProviderClient::OpenRouter(_) => ProviderType::OpenRouter,
        }
    }

    /// 🔒 SAFETY: 简单聊天接口（仅支持基础消息）喵
    /// 异常处理: 所有 Provider 错误统一转换为 ProviderError
    /// 注意: 不同 Provider 的 API 行为可能略有差异
    pub async fn chat_simple(&self, prompt: &str) -> Result<String, ProviderError> {
        match self {
            ProviderClient::OpenAI(client) => client.chat_simple(prompt).await,
            ProviderClient::Anthropic(client) => client.chat_simple(prompt).await,
            ProviderClient::OpenRouter(client) => {
                // 默认使用 OpenRouter 的 GPT-3.5-Turbo
                client.chat_simple("openai/gpt-3.5-turbo", prompt).await
            }
        }
    }
}

/// 🔒 SAFETY: 测试辅助函数喵
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_provider_type_parsing() {
        assert_eq!(ProviderType::from_str("openai"), Some(ProviderType::OpenAI));
        assert_eq!(ProviderType::from_str("OPENAI"), Some(ProviderType::OpenAI));
        assert_eq!(
            ProviderType::from_str("anthropic"),
            Some(ProviderType::Anthropic)
        );
        assert_eq!(
            ProviderType::from_str("openrouter"),
            Some(ProviderType::OpenRouter)
        );
        assert_eq!(ProviderType::from_str("unknown"), None);
    }

    #[test]
    fn test_provider_type_to_string() {
        assert_eq!(ProviderType::OpenAI.as_str(), "openai");
        assert_eq!(ProviderType::Anthropic.as_str(), "anthropic");
        assert_eq!(ProviderType::OpenRouter.as_str(), "openrouter");
    }

    #[test]
    fn test_factory_default() {
        let factory = ProviderFactory::new();
        assert!(factory.openai_config.is_none());
        assert!(factory.create_openai_client().is_err());
    }

    #[test]
    fn test_factory_builder() {
        let factory = ProviderFactory::new()
            .with_openai_config(OpenAIConfig::default())
            .with_anthropic_config(AnthropicConfig::default());

        assert!(factory.openai_config.is_some());
        assert!(factory.create_openai_client().is_ok());
        assert!(factory.create_anthropic_client().is_ok());
    }
}
