//!
//! # 集成测试模块
//!
//! ⚠️ SAFETY: Neko-Claw 集成测试套件喵
//!
//! ## 测试覆盖
//! - `security_test`: 安全模块集成测试 (crypto, allowlist, sandbox)
//! - `channel_test`: 渠道模块集成测试 (Discord, Telegram)
//! - `agent_test`: Agent 核心集成测试 (Agent, ToolChain, Memory, Provider)
//!
//! ## 运行命令
//! ```bash
//! cargo test --test integration
//! ```

pub mod security_test;
pub mod channel_test;
pub mod agent_test;
