//! 📂 Skills Loader - 从目录加载技能喵

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::path::Path;

/// 📖 Skill 定义 - 从 SKILL.md 解析
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Skill {
    /// 技能名称
    pub name: String,
    /// 技能描述
    pub description: String,
    /// 技能目录路径
    pub path: PathBuf,
    /// 执行命令（可选）
    pub command: Option<String>,
    /// 参数说明（可选）
    pub parameters: Vec<SkillParameter>,
}

/// 📝 Skill 参数定义
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillParameter {
    pub name: String,
    pub description: String,
    pub required: bool,
    pub default: Option<String>,
}

/// ⚙️ Skills 配置
#[derive(Debug, Clone)]
pub struct SkillsConfig {
    pub skills_dir: PathBuf,
}

impl Default for SkillsConfig {
    fn default() -> Self {
        Self {
            skills_dir: PathBuf::from("skills"),
        }
    }
}

/// 🎒 Skills 加载器
pub struct SkillLoader {
    config: SkillsConfig,
    skills: Vec<Skill>,
}

impl SkillLoader {
    pub fn new(config: SkillsConfig) -> Self {
        Self {
            config,
            skills: Vec::new(),
        }
    }
    
    /// 加载所有技能
    pub fn load(&mut self) -> Result<()> {
        self.skills = load_skills(&self.config.skills_dir)?;
        log::info!("✅ 加载了 {} 个技能喵", self.skills.len());
        Ok(())
    }
    
    /// 获取技能数量
    pub fn count(&self) -> usize {
        self.skills.len()
    }
    
    /// 生成 AI 可读的技能描述片段
    pub fn generate_prompt_fragment(&self) -> String {
        if self.skills.is_empty() {
            return String::new();
        }
        
        let mut prompt = String::from("\n## 🔧 可用技能 (Skills)\n\n");
        prompt.push_str("你可以使用以下技能来完成任务喵：\n\n");
        
        for skill in &self.skills {
            prompt.push_str(&format!("### {}\n", skill.name));
            prompt.push_str(&format!("{}\n", skill.description));
            
            if let Some(cmd) = &skill.command {
                prompt.push_str(&format!("\n**执行**: `{}`\n", cmd));
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
        
        prompt.push_str("调用 @shell 执行技能脚本喵！\n");
        prompt
    }
}

/// 从目录加载所有技能
pub fn load_skills(skills_dir: &Path) -> Result<Vec<Skill>> {
    let mut skills = Vec::new();
    
    // 检查目录是否存在
    if !skills_dir.exists() {
        log::warn!("Skills 目录不存在喵: {:?}", skills_dir);
        return Ok(skills);
    }
    
    // 遍历子目录
    for entry in fs::read_dir(skills_dir)? {
        let entry = entry?;
        let path = entry.path();
        
        // 只处理目录
        if !path.is_dir() {
            continue;
        }
        
        // 查找 SKILL.md 文件
        let skill_file = path.join("SKILL.md");
        if skill_file.exists() {
            match parse_skill_md(&skill_file, &path) {
                Ok(skill) => {
                    log::info!("✅ 加载技能: {} from {:?}", skill.name, path);
                    skills.push(skill);
                }
                Err(e) => {
                    log::error!("❌ 解析技能失败 {:?}: {}", skill_file, e);
                }
            }
        }
    }
    
    Ok(skills)
}

/// 解析 SKILL.md 文件
fn parse_skill_md(file_path: &Path, skill_dir: &Path) -> Result<Skill> {
    let content = fs::read_to_string(file_path)
        .context("读取 SKILL.md 失败喵")?;
    
    // 解析 Markdown 内容
    let (name, description, command, parameters) = parse_markdown(&content)?;
    
    Ok(Skill {
        name,
        description,
        path: skill_dir.to_path_buf(),
        command,
        parameters,
    })
}

/// 解析 Markdown 内容
fn parse_markdown(content: &str) -> Result<(String, String, Option<String>, Vec<SkillParameter>)> {
    let lines: Vec<&str> = content.lines().collect();
    
    let mut name = String::new();
    let mut description = String::new();
    let mut command = None;
    let mut parameters = Vec::new();
    
    let mut section = "header";
    
    for line in &lines {
        let line = line.trim();
        
        // 标题
        if line.starts_with("# ") {
            name = line[2..].to_string();
            section = "description";
            continue;
        }
        
        // 二级标题 - 切换 section
        if line.starts_with("## ") {
            section = &line[3..];
            continue;
        }
        
        // 根据当前 section 处理
        match section {
            "description" => {
                if !line.is_empty() && !line.starts_with('#') {
                    if !description.is_empty() {
                        description.push('\n');
                    }
                    description.push_str(line);
                }
            }
            "执行" | "Execute" | "Execution" => {
                // 解析命令，格式: `command` 或直接写命令
                if line.starts_with('`') && line.ends_with('`') {
                    command = Some(line[1..line.len()-1].to_string());
                } else if !line.is_empty() && !line.starts_with('#') {
                    command = Some(line.to_string());
                }
            }
            "参数" | "Parameters" | "Params" => {
                // 解析参数，格式: - `name` (必填/可选): 说明 [默认: value]
                if line.starts_with("- `") {
                    if let Some(param) = parse_parameter_line(line) {
                        parameters.push(param);
                    }
                }
            }
            _ => {}
        }
    }
    
    // 如果没有名称，使用目录名
    if name.is_empty() {
        name = "未命名技能".to_string();
    }
    
    Ok((name, description, command, parameters))
}

/// 解析参数行
fn parse_parameter_line(line: &str) -> Option<SkillParameter> {
    // 移除开头的 "- "
    let line = line.strip_prefix("- ")?;
    
    // 提取参数名 (在 ` ` 之间)
    let name_end = line.find("` ")?;
    let name = line[1..name_end].to_string();
    
    // 提取必填/可选
    let rest = &line[name_end + 2..];
    let required = rest.contains("必填") || rest.contains("required");
    
    // 提取描述
    let desc_start = rest.find(": ")?;
    let mut description = rest[desc_start + 2..].to_string();
    
    // 提取默认值
    let default = if let Some(start) = description.find("[默认: ") {
        let rest = &description[start + 5..];
        if let Some(end) = rest.find(']') {
            let default_val = rest[..end].to_string();
            description = description[..start].trim().to_string();
            Some(default_val)
        } else {
            None
        }
    } else if let Some(start) = description.find("[default: ") {
        let rest = &description[start + 10..];
        if let Some(end) = rest.find(']') {
            let default_val = rest[..end].to_string();
            description = description[..start].trim().to_string();
            Some(default_val)
        } else {
            None
        }
    } else {
        None
    };
    
    Some(SkillParameter {
        name,
        description,
        required,
        default,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_parse_markdown() {
        let content = r#"# 天气查询

查询指定城市的天气信息喵！

## 执行
`python scripts/weather.py`

## 参数
- `city` (必填): 城市名称
- `unit` (可选): 温度单位 [默认: celsius]
"#;
        
        let (name, desc, cmd, params) = parse_markdown(content).unwrap();
        
        assert_eq!(name, "天气查询");
        assert!(desc.contains("查询指定城市"));
        assert_eq!(cmd, Some("python scripts/weather.py".to_string()));
        assert_eq!(params.len(), 2);
        assert_eq!(params[0].name, "city");
        assert!(params[0].required);
        assert_eq!(params[1].name, "unit");
        assert!(!params[1].required);
        assert_eq!(params[1].default, Some("celsius".to_string()));
    }
}
