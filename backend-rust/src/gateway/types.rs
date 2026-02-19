use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InboundMessage {
    pub id: String,
    pub channel: String,
    pub source: MessageSource,
    pub user: MessageUser,
    pub chat: MessageChat,
    pub content: MessageContent,
    pub reply_to: Option<String>,
    pub timestamp: String,
    pub trace_id: Option<String>,
    pub raw: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OutboundMessage {
    pub id: String,
    pub channel: String,
    pub chat_id: String,
    pub text: Option<String>,
    pub media: Vec<MediaRef>,
    pub reply_to: Option<String>,
    pub mentions: Vec<String>,
    pub trace_id: Option<String>,
    pub allow_stream: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageSource {
    pub kind: String,
    pub id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageUser {
    pub id: String,
    pub display: String,
    pub avatar_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageChat {
    pub id: String,
    pub r#type: String,
    pub title: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageContent {
    pub text: Option<String>,
    pub media: Vec<MediaRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MediaRef {
    pub id: String,
    pub kind: String,
    pub mime: String,
    pub url: Option<String>,
    pub path: Option<String>,
    pub size_bytes: Option<u64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u64>,
    pub sha256: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionMap {
    pub map_id: String,
    pub channel: String,
    pub chat_id: String,
    pub user_id: String,
    pub session_id: String,
    pub pairing_id: Option<String>,
    pub status: String,
    pub routing: SessionRouting,
    pub created_at: String,
    pub last_seen_at: Option<String>,
    pub expires_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionRouting {
    pub agent_id: String,
    pub workspace_id: String,
    pub policy: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairingOffer {
    pub pairing_id: String,
    pub mode: PairingMode,
    pub status: PairingStatus,
    pub short_code: Option<String>,
    pub token: String,
    pub expires_at: String,
    pub gateway: GatewayIdentity,
    pub client: Option<ClientIdentity>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GatewayIdentity {
    pub id: String,
    pub name: String,
    pub url: Option<String>,
    pub ip: Option<String>,
    pub port: Option<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientIdentity {
    pub device_id: String,
    pub device_name: String,
    pub app_version: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PairingMode {
    Lan,
    Wan,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PairingStatus {
    Offered,
    Accepted,
    Active,
    Expired,
    Revoked,
}
