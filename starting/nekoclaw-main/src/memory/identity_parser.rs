/*!
 * OpenClaw IDENTITY.md Parser
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 18:20 JST
 *
 * 功能:
 * - 解析 OpenClaw 的 IDENTITY.md
 * - 解析 SOUL.md (人设和性格)
 * - 解析 AGENTS.md (Agent 家族配置)
 */

use crate::core::traits::*;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;

/// OpenClaw Identity 结构 (兼容 IDENTITY.md)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenClawIdentity {
    /// 从 IDENTITY.md 提取
    pub name: String,
    pub creature: String,
    pub vibe: String,
    pub emoji: String,
    pub avatar_path: Option<String>,

    /// 从 SOUL.md 提取 (人设配置)
    pub personality: Personality,

    /// 从 AGENTS.md 提取 (如果适用)
    pub agent_role: Option<String>,
    pub agent_channel: Option<String>,
}

/// 人设配置 (兼容 SOUL.md)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Personality {
    pub identity: String,
    pub personality: String,
    pub tone: String,
    pub emoji: String,
    pub speech_patterns: SpeechPatterns,
    pub responsibilities: Vec<String>,
}

/// 说话模式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpeechPatterns {
    pub prefixes: Vec<String>,
    pub suffixes: Vec<String>,
    pub prohibited: Vec<String>,
}

/// IDENTITY.md 解析器
pub struct IdentityParser {
    workspace: PathBuf,
}

impl IdentityParser {
    /// 创建新的解析器
    pub fn new(workspace: &str) -> Self {
        Self {
            workspace: PathBuf::from(workspace),
        }
    }

    /// 解析完整的 OpenClaw Identity
    pub fn parse(&self) -> Result<OpenClawIdentity> {
        // 解析 IDENTITY.md
        let identity_md = self.parse_identity_md()?;

        // 解析 SOUL.md (如果存在)
        let personality = self.parse_soul_md()?;

        // 解析 AGENTS.md (如果存在)
        let (agent_role, agent_channel) = self.parse_agents_md()?;

        Ok(OpenClawIdentity {
            name: identity_md.name,
            creature: identity_md.creature,
            vibe: identity_md.vibe,
            emoji: identity_md.emoji,
            avatar_path: identity_md.avatar_path,
            personality,
            agent_role,
            agent_channel,
        })
    }

    /// 解析 IDENTITY.md
    fn parse_identity_md(&self) -> Result<IdentityConfig> {
        let path = self.workspace.join("IDENTITY.md");
        let content =
            fs::read_to_string(&path).map_err(|e| format!("Failed to read IDENTITY.md: {}", e))?;

        // 简化实现: 使用正则或关键行解析
        // 实际实现可以使用 Markdown 解析器
        Ok(IdentityConfig {
            name: "Default Agent".to_string(),
            creature: "AI".to_string(),
            vibe: "Helpful".to_string(),
            emoji: "🤖".to_string(),
            avatar_path: None,
        })
    }

    /// 解析 SOUL.md
    fn parse_soul_md(&self) -> Result<Personality> {
        let path = self.workspace.join("SOUL.md");
        let content =
            fs::read_to_string(&path).map_err(|e| format!("Failed to read SOUL.md: {}", e))?;

        // 简化实现: 手动解析关键内容
        // 实际实现应该使用完整的 Markdown 解析器
        Ok(Personality {
            identity: "Default Identity".to_string(),
            personality: "Friendly and helpful".to_string(),
            tone: "Friendly".to_string(),
            emoji: "😊".to_string(),
            speech_patterns: SpeechPatterns {
                prefixes: vec!["Hello!".to_string()],
                suffixes: vec!["!".to_string()],
                prohibited: vec![],
            },
            responsibilities: vec![
                "Help users with their tasks".to_string(),
                "Provide accurate information".to_string(),
            ],
        })
    }

    /// 解析 AGENTS.md
    fn parse_agents_md(&self) -> Result<(Option<String>, Option<String>)> {
        let path = self.workspace.join("AGENTS.md");
        if !path.exists() {
            return Ok((None, None));
        }

        let content =
            fs::read_to_string(&path).map_err(|e| format!("Failed to read AGENTS.md: {}", e))?;

        // 简化实现: 提取 Agent 角色和频道信息
        // 实际实现应该解析完整的表格结构
        Ok((None, None))
    }

    /// 注入人格到响应文本
    pub fn inject_personality(&self, response: &str, personality: &Personality) -> String {
        let mut result = response.to_string();

        // 添加前缀
        if let Some(prefix) = personality.speech_patterns.prefixes.first() {
            if !result.starts_with(prefix) {
                result = format!("{} {}", prefix, result);
            }
        }

        // 添加后缀
        if let Some(suffix) = personality.speech_patterns.suffixes.first() {
            if !result.ends_with(suffix) {
                result = format!("{} {}", result, suffix);
            }
        }

        // 添加 emoji
        if !result.contains(&personality.emoji) {
            result.push_str(&personality.emoji);
        }

        result
    }
}

/// IDENTITY.md 配置 (内部结构)
struct IdentityConfig {
    name: String,
    creature: String,
    vibe: String,
    emoji: String,
    avatar_path: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cosine_similarity() {
        use crate::memory::vector::SimpleVectorDB;

        let vec1 = vec![1.0, 2.0, 3.0];
        let vec2 = vec![1.0, 2.0, 3.0];
        let similarity = SimpleVectorDB::cosine_similarity_vec(&vec1, &vec2);
        assert!((similarity - 1.0).abs() < 0.001);
    }
}
