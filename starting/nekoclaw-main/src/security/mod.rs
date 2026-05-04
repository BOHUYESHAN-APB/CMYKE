//!
//! # Security Module
//!
//! ⚠️ SAFETY: 核心安全模块，包含加密、白名单、沙箱等功能喵
//!
//! ## 模块结构
//! - `crypto`: AES-256-GCM 加密服务 - API Key 和敏感配置保护喵
//! - `allowlist`: 命令和路径白名单检查 - 访问控制喵
//! - `sandbox`: 命令沙箱执行环境 - 安全命令执行喵
//!
//! ## 安全原则
//! 1. **零信任**: 所有输入都不可信喵
//! 2. **最小权限**: 只授予完成任务所需的最小权限喵
//! 3. **纵深防御**: 多层安全检查喵
//!
//! ## 使用说明
//! 所有安全相关的功能都通过此模块暴露喵

pub mod allowlist;
pub mod crypto;
pub mod sandbox;

pub use allowlist::{AllowlistConfig, AllowlistError, AllowlistService};
pub use crypto::{generate_key, CryptoError, CryptoService};
pub use sandbox::{SandboxConfig, SandboxError, SandboxResult, SandboxService};
