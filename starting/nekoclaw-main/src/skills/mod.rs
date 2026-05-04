//! 🔧 Skills System - 动态技能加载喵
//! 
//! Skills 是 NekoClaw 的插件系统，通过 SKILL.md 文件定义技能
//! AI 读取技能描述后，通过工具调用执行脚本

pub mod loader;

// 重新导出主要类型
pub use loader::{Skill, SkillLoader, SkillsConfig, SkillParameter, load_skills};

use anyhow::Result;
use std::path::PathBuf;

/// 🎒 Skills 管理器
pub struct SkillsManager {
    skills: Vec<Skill>,
    skills_dir: PathBuf,
}

impl SkillsManager {
    /// 创建新的 Skills 管理器
    pub fn new(skills_dir: PathBuf) -> Self {
        Self {
            skills: Vec::new(),
            skills_dir,
        }
    }
    
    /// 加载所有技能
    pub fn load_all(&mut self) -> Result<()> {
        self.skills = loader::load_skills(&self.skills_dir)?;
        log::info!("✅ 加载了 {} 个技能喵", self.skills.len());
        Ok(())
    }
    
    /// 获取所有技能
    pub fn get_skills(&self) -> &[Skill] {
        &self.skills
    }
    
    /// 生成 AI 可读的技能描述（注入 system prompt）
    pub fn generate_skills_prompt(&self) -> String {
        if self.skills.is_empty() {
            return String::new();
        }
        
        let mut prompt = String::from("\n## 🔧 可用技能 (Skills)\n\n");
        prompt.push_str("你可以使用以下技能来完成任务喵：\n\n");
        
        for skill in &self.skills {
            prompt.push_str(&format!("### {}\n", skill.name));
            prompt.push_str(&format!("{}\n", skill.description));
            
            if let Some(cmd) = &skill.command {
                prompt.push_str(&format!("\n**执行命令**: `{}`\n", cmd));
            }
            
            if !skill.parameters.is_empty() {
                prompt.push_str("\n**参数**:\n");
                for param in &skill.parameters {
                    let required = if param.required { "必填" } else { "可选" };
                    prompt.push_str(&format!("- `{}` ({}): {}", param.name, required, param.description));
                    if let Some(default) = &param.default {
                        prompt.push_str(&format!(" [默认: {}]", default));
                    }
                    prompt.push('\n');
                }
            }
            prompt.push('\n');
        }
        
        prompt.push_str("使用技能时，调用 @shell 执行对应脚本喵！\n");
        prompt
    }
}
