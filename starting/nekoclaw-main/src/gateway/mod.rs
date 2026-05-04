//! Gateway 模块导出 🌐
//!
//! @诺诺 的 Gateway 模块统一入口喵

pub mod pairing;
pub mod server;
pub mod webhook;
pub mod openai;
pub mod metrics;

// 🔒 SAFETY: 重新导出公共接口喵
pub use pairing::{PairingConfig, PairingManager, PairingRequest, PairingResponse, PairingStatus};
pub use server::{ErrorResponse, GatewayConfig, GatewayServer, GatewayState, HealthResponse};
pub use webhook::{
    WebhookConfig, WebhookEvent, WebhookEventType, WebhookHandler, WebhookManager, WebhookResponse,
};

/// 🔒 SAFETY: Gateway 统一入口结构体喵
#[derive(Debug, Clone)]
pub struct Gateway {
    server: Option<GatewayServer>,
    pairing_manager: PairingManager,
    webhook_manager: WebhookManager,
}

impl Gateway {
    pub fn new(gateway_config: GatewayConfig) -> Self {
        let pairing_config = PairingConfig::default();
        let webhook_config = WebhookConfig::default();
        Self {
            server: Some(GatewayServer::new(gateway_config)),
            pairing_manager: PairingManager::new(pairing_config),
            webhook_manager: WebhookManager::new(webhook_config),
        }
    }

    pub async fn run(self) -> crate::core::traits::Result<()> {
        if let Some(server) = self.server {
            server.run().await?;
        }
        Ok(())
    }

    pub fn pairing_manager(&self) -> &PairingManager {
        &self.pairing_manager
    }

    pub fn webhook_manager(&self) -> &WebhookManager {
        &self.webhook_manager
    }
}
