/*!
 * Discord Bot Implementation
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 18:33 JST
 *
 * 功能:
 * - Discord Bot 核心实现
 * - 事件处理 (消息、反应、连接)
 * - 集成 Provider 和 Memory 系统
 */

use crate::core::traits::*;
use async_trait::async_trait;
use futures::{Stream, StreamExt};
use std::pin::Pin;
use std::sync::Arc;
use tokio::sync::mpsc;

/// Discord Bot 配置
#[derive(Debug, Clone)]
pub struct DiscordConfig {
    pub token: String,
    pub allowed_users: Vec<String>,
    pub allowed_channels: Option<Vec<String>>,
}

impl Default for DiscordConfig {
    fn default() -> Self {
        Self {
            token: String::new(),
            allowed_users: vec![],
            allowed_channels: None,
        }
    }
}

/// Discord Bot
pub struct DiscordBot {
    config: DiscordConfig,
    provider: Option<Arc<dyn Provider>>,
    memory: Option<Arc<dyn Memory>>,
    event_tx: mpsc::UnboundedSender<DiscordEvent>,
}

impl DiscordBot {
    /// 创建新的 Discord Bot
    pub fn new(config: DiscordConfig) -> Self {
        let (event_tx, event_rx) = mpsc::unbounded_channel();

        // 启动事件监听器
        tokio::spawn(Self::event_listener(event_rx));

        Self {
            config,
            provider: None,
            memory: None,
            event_tx,
        }
    }

    /// 设置 AI Provider
    pub fn with_provider(mut self, provider: Arc<dyn Provider>) -> Self {
        self.provider = Some(provider);
        self
    }

    /// 设置 Memory 系统
    pub fn with_memory(mut self, memory: Arc<dyn Memory>) -> Self {
        self.memory = Some(memory);
        self
    }

    /// 启动 Bot
    pub async fn start(&self) -> Result<()> {
        // TODO: 实现 Discord 连接逻辑
        println!("🐾 Discord Bot starting...");
        Ok(())
    }

    /// 发送消息到 Discord 频道
    pub async fn send_message(&self, channel_id: &str, content: &str) -> Result<()> {
        // TODO: 实现 Discord HTTP API 调用
        println!("📤 Sending to {}: {}", channel_id, content);
        Ok(())
    }

    /// 处理接收到的消息
    async fn handle_message(
        &self,
        author_id: String,
        channel_id: String,
        content: String,
    ) -> Result<ChannelEvent> {
        // 检查用户授权
        if !self.config.allowed_users.contains(&author_id) {
            println!("⚠️  Unauthorized user: {}", author_id);
            // 发送错误响应
            self.send_message(&channel_id, "🚫 Unauthorized access")
                .await?;
            return Err("Unauthorized user".into());
        }

        // 发送事件流
        let event = ChannelEvent {
            source: "discord".to_string(),
            sender_id: author_id.clone(),
            message: content.clone(),
            metadata: Some(serde_json::json!({
                "channel_id": channel_id,
                "timestamp": chrono::Utc::now().to_rfc3339(),
            })),
        };

        // 发送到事件队列
        self.event_tx
            .send(DiscordEvent::Message(event.clone()))
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error + Send + Sync>)?;

        Ok(event)
    }

    /// 事件监听器 (后台任务)
    async fn event_listener(mut event_rx: mpsc::UnboundedReceiver<DiscordEvent>) {
        while let Some(event) = event_rx.recv().await {
            match event {
                DiscordEvent::Message(channel_event) => {
                    println!("📨 Received message: {}", channel_event.message);
                }
                DiscordEvent::Typing(user_id, channel_id) => {
                    println!("⌨️  User {} is typing in channel {}", user_id, channel_id);
                }
                DiscordEvent::Reaction(user_id, channel_id, emoji) => {
                    println!(
                        "😀 User {} reacted with {} in channel {}",
                        user_id, emoji, channel_id
                    );
                }
            }
        }
    }
}

#[async_trait::async_trait]
impl Channel for DiscordBot {
    async fn send(&self, content: &str, target: Option<&str>) -> Result<()> {
        let channel_id = target.ok_or("Target channel ID required")?;
        self.send_message(channel_id, content).await
    }

    async fn receive(&self) -> Pin<Box<dyn Stream<Item = Result<ChannelEvent>> + Send>> {
        let (tx, rx) = mpsc::unbounded_channel::<ChannelEvent>();

        // 发送一个空事件
        tx.send(ChannelEvent {
            source: "discord".to_string(),
            sender_id: "system".to_string(),
            message: "Mock event".to_string(),
            metadata: None,
        })
        .ok();

        let stream =
            tokio_stream::wrappers::UnboundedReceiverStream::new(rx).map(|event| Ok(event));

        Box::pin(stream)
    }

    fn name(&self) -> &str {
        "discord"
    }

    fn channel_type(&self) -> &str {
        "discord"
    }
}

/// Discord 内部事件 (用于事件队列)
#[derive(Debug, Clone)]
pub enum DiscordEvent {
    Message(ChannelEvent),
    Typing(String, String),           // user_id, channel_id
    Reaction(String, String, String), // user_id, channel_id, emoji
}
