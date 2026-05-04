/// Agent 模块导出 🤖
///
/// @诺诺 的 Agent 模块统一入口喵
///
/// 功能：
/// - 导出所有 Agent 实现
/// - Agent 生命周期管理
/// - 会话管理
/// - 上下文管理
///
/// 🔒 SAFETY: 模块级访问控制，防止非法访问
///
/// 模块作者: 诺诺 (Nono) ⚡

pub mod runtime;
pub mod session;
pub mod context;

// 🔒 SAFETY: 重新导出公共接口喵
pub use runtime::{Agent, AgentConfig, AgentMessage, AgentResponse, AgentStats, AgentError};
pub use session::{SessionManager, SessionManagerConfig, SessionInfo, SessionState, SessionStats};
pub use context::{ContextManager, ContextConfig, PrioritizedMessage, MessagePriority, ContextStats};
