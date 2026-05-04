//!
//! # Agent 核心集成测试
//!
//! ⚠️ SAFETY: 测试 Agent 核心模块的集成喵
//!
//! ## 测试范围
//! - Agent 注册/注销喵
//! - Agent 消息传递喵
//! - 会话管理喵
//! - 工具调用集成喵
//!
//! ## 运行命令
//! ```bash
//! cargo test --test integration agent_test -- --nocapture
//! ```

use crate::core::traits::{Agent, Channel, Memory, Tool, Provider, ChannelEvent, Result as CoreResult};
use crate::core::config::Config;
use crate::tools::{ToolChain, ShellTool, BrainTool};
use crate::memory::MemoryManager;
use crate::providers::OpenAIProvider;
use crate::channels::discord::DiscordChannel;
use async_trait::async_trait;
use std::sync::Arc;
use tokio::sync::Mutex;
use std::time::Duration;

/// 测试 Agent 特征实现喵
#[tokio::test]
async fn test_agent_trait() {
    // 创建测试配置喵
    let config = Config::default();
    
    // 创建 Mock Agent 实现喵
    struct TestAgent {
        id: String,
        name: String,
        state: Arc<Mutex<AgentState>>,
    }
    
    struct AgentState {
        messages: Vec<String>,
        tools_called: Vec<String>,
    }
    
    #[async_trait]
    impl Agent for TestAgent {
        fn id(&self) -> &str {
            &self.id
        }
        
        fn name(&self) -> &str {
            &self.name
        }
        
        async fn think(&mut self, input: &str) -> CoreResult<String> {
            let mut state = self.state.lock().await;
            state.messages.push(format!("think: {}", input));
            Ok(format!("Processed: {}", input))
        }
        
        async fn act(&mut self, action: &str) -> CoreResult<String> {
            let mut state = self.state.lock().await;
            state.tools_called.push(action.to_string());
            Ok(format!("Acted: {}", action))
        }
        
        fn channel(&self) -> Option<&dyn Channel> {
            None
        }
        
        fn memory(&self) -> Option<&dyn Memory> {
            None
        }
    }
    
    // 创建 Agent 实例喵
    let agent = TestAgent {
        id: "test_agent_001".to_string(),
        name: "TestAgent".to_string(),
        state: Arc::new(Mutex::new(AgentState {
            messages: Vec::new(),
            tools_called: Vec::new(),
        })),
    };
    
    // 测试 Agent 基本属性喵
    assert_eq!(agent.id(), "test_agent_001");
    assert_eq!(agent.name(), "TestAgent");
    
    // 测试 think 方法喵
    let result = agent.think("test input").await;
    assert!(result.is_ok());
}

/// 测试工具链集成喵
#[tokio::test]
async fn test_tool_chain_integration() {
    // 创建工具链喵
    let mut tool_chain = ToolChain::new();
    
    // 添加 Shell 工具喵
    let shell_tool = ShellTool::new();
    tool_chain.add_tool("shell", Box::new(shell_tool));
    
    // 添加 Brain 工具喵
    let brain_tool = BrainTool::new();
    tool_chain.add_tool("brain", Box::new(brain_tool));
    
    // 检查工具是否注册喵
    assert!(tool_chain.has_tool("shell"));
    assert!(tool_chain.has_tool("brain"));
    assert!(!tool_chain.has_tool("nonexistent"));
    
    // 测试工具调用喵
    let result = tool_chain.call("shell", "echo", &["test"]).await;
    assert!(result.is_ok());
}

/// 测试内存管理器集成喵
#[tokio::test]
async fn test_memory_manager_integration() {
    // 创建内存管理器喵
    let manager = MemoryManager::new(":memory:").await.unwrap();
    
    // 测试存储和检索喵
    let key = "test_key".to_string();
    let value = "test_value".to_string();
    
    manager.store(&key, &value).await.unwrap();
    let retrieved = manager.retrieve(&key).await.unwrap();
    
    assert_eq!(value, retrieved);
    
    // 测试删除喵
    manager.delete(&key).await.unwrap();
    let result = manager.retrieve(&key).await.unwrap();
    assert!(result.is_empty());
}

/// 测试 OpenAI Provider 集成喵
#[tokio::test]
async fn test_openai_provider_integration() {
    // 创建 Provider 配置喵
    let config = crate::providers::ProviderConfig {
        name: "openai".to_string(),
        api_key: "test_key".to_string(),
        model: "gpt-4".to_string(),
        max_tokens: Some(1000),
        temperature: Some(0.7),
    };
    
    // 创建 Provider喵
    let provider = OpenAIProvider::new(config);
    
    // 测试基本属性喵
    assert_eq!(provider.name(), "openai");
    assert_eq!(provider.model(), "gpt-4");
}

/// 测试 Discord Channel 集成喵
#[tokio::test]
async fn test_discord_channel_integration() {
    // 创建 Channel 配置喵
    let config = crate::channels::discord::DiscordConfig::default();
    
    // 创建 Channel喵
    let channel = DiscordChannel::new("test_token".to_string(), config).unwrap();
    
    // 测试基本属性喵
    assert_eq!(channel.name(), "discord");
    assert_eq!(channel.channel_type(), "discord");
}

/// 测试配置加载喵
#[tokio::test]
async fn test_config_loading() {
    // 测试默认配置喵
    let config = Config::default();
    
    assert!(!config.app_name.is_empty());
    assert!(config.data_dir.is_some());
    assert!(config.log_level.is_some());
}

/// 测试 Agent 会话状态管理喵
#[tokio::test]
async fn test_agent_session_state() {
    use crate::core::traits::SessionState;
    
    // 创建会话状态喵
    let state = SessionState::new("test_session_001".to_string());
    
    // 检查会话 ID喵
    assert_eq!(state.session_id(), "test_session_001");
    
    // 检查状态喵
    assert_eq!(state.status(), crate::core::traits::SessionStatus::Active);
    
    // 测试状态转换喵
    state.pause();
    assert_eq!(state.status(), crate::core::traits::SessionStatus::Paused);
    
    state.resume();
    assert_eq!(state.status(), crate::core::traits::SessionStatus::Active);
    
    state.end();
    assert_eq!(state.status(), crate::core::traits::SessionStatus::Ended);
}

/// 测试消息事件处理喵
#[tokio::test]
async fn test_message_event_handling() {
    use crate::core::traits::{MessageEvent, EventType};
    
    // 创建消息事件喵
    let event = MessageEvent::new(
        "msg_001".to_string(),
        "test_agent".to_string(),
        "Hello".to_string(),
        EventType::UserInput,
        chrono::Utc::now(),
    );
    
    // 检查事件属性喵
    assert_eq!(event.id(), "msg_001");
    assert_eq!(event.agent_id(), "test_agent");
    assert_eq!(event.content(), "Hello");
    assert_eq!(event.event_type(), EventType::UserInput);
}

/// 测试 Provider 错误处理喵
#[tokio::test]
async fn test_provider_error_handling() {
    use crate::providers::ProviderError;
    
    // 测试 API Key 错误喵
    let error = ProviderError::AuthenticationError("Invalid API key".to_string());
    assert!(error.to_string().contains("Invalid API key"));
    
    // 测试速率限制错误喵
    let error = ProviderError::RateLimitError(60);
    assert!(error.to_string().contains("60"));
    
    // 测试超时错误喵
    let error = ProviderError::TimeoutError(Duration::from_secs(30));
    assert!(error.to_string().contains("30"));
}

/// 测试 Channel 错误处理喵
#[tokio::test]
async fn test_channel_error_handling() {
    use crate::channels::ChannelError;
    
    // 测试连接错误喵
    let error = ChannelError::ConnectionError("Failed to connect".to_string());
    assert!(error.to_string().contains("Failed to connect"));
    
    // 测试认证错误喵
    let error = ChannelError::AuthenticationError("Invalid token".to_string());
    assert!(error.to_string().contains("Invalid token"));
    
    // 测试消息发送错误喵
    let error = ChannelError::SendError("Message too long".to_string());
    assert!(error.to_string().contains("Message too long"));
}

/// 测试工具链错误处理喵
#[tokio::test]
async fn test_tool_chain_error_handling() {
    use crate::tools::ToolError;
    
    // 测试工具不存在错误喵
    let error = ToolError::ToolNotFound("nonexistent".to_string());
    assert!(error.to_string().contains("nonexistent"));
    
    // 测试工具调用错误喵
    let error = ToolError::ToolExecutionError("Execution failed".to_string());
    assert!(error.to_string().contains("Execution failed"));
    
    // 测试参数错误喵
    let error = ToolError::InvalidArguments("Invalid args".to_string());
    assert!(error.to_string().contains("Invalid args"));
}

/// 测试内存管理器搜索功能喵
#[tokio::test]
async fn test_memory_search_functionality() {
    let manager = MemoryManager::new(":memory:").await.unwrap();
    
    // 存储多个条目喵
    manager.store("key1", "value1").await.unwrap();
    manager.store("key2", "value2").await.unwrap();
    manager.store("key3", "value3").await.unwrap();
    
    // 搜索喵
    let results = manager.search("key").await.unwrap();
    assert_eq!(results.len(), 3);
    
    // 精确搜索喵
    let results = manager.search("key1").await.unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0], "value1");
}
