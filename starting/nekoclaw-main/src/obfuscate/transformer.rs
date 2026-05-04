/*!
 * Obfuscate Transformer - Code Transformation
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 18:55 JST
 *
 * 功能:
 * - 字符串混淆转换
 * - AST 转换 (简化版本)
 * - 代码生成
 */

use crate::obfuscate::{Obfuscator, ObfuscateConfig};
use std::collections::HashMap;

/// 混淆转换结果
#[derive(Debug, Clone)]
pub struct TransformerResult {
    pub original_code: String,
    pub obfuscated_code: String,
    pub transformation_log: TransformationLog,
}

/// 转换日志
#[derive(Debug, Clone)]
pub struct TransformationLog {
    pub strings_obfuscated: usize,
    pub variables_renamed: usize,
    pub comments_obfuscated: usize,
}

impl Default for TransformationLog {
    fn default() -> Self {
        Self {
            strings_obfuscated: 0,
            variables_renamed: 0,
            comments_obfuscated: 0,
        }
    }
}

/// 代码混淆转换器
pub struct ObfuscateTransformer {
    obfuscator: Obfuscator,
    variable_map: HashMap<String, String>,
}

impl ObfuscateTransformer {
    /// 创建新的混淆转换器
    pub fn new() -> Self {
        Self {
            obfuscator: Obfuscator::new(),
            variable_map: HashMap::new(),
        }
    }

    /// 使用自定义配置
    pub fn with_config(config: ObfuscateConfig) -> Self {
        Self {
            obfuscator: Obfuscator::new().with_config(config),
            variable_map: HashMap::new(),
        }
    }

    /// 转换代码
    pub fn transform(&mut self, code: &str) -> Result<TransformerResult> {
        let mut log = TransformationLog::default();
        let mut result = String::new();

        // 简化的代码转换：逐行处理
        for line in code.lines() {
            let transformed_line = self.transform_line(line, &mut log);
            result.push_str(&transformed_line);
            result.push('\n');
        }

        Ok(TransformerResult {
            original_code: code.to_string(),
            obfuscated_code: result,
            transformation_log: log,
        })
    }

    /// 转换单行代码
    fn transform_line(&mut self, line: &str, log: &mut TransformationLog) -> String {
        let mut result = line.to_string();

        // 1. 混淆字符串
        if self.obfuscator.config.enable_string_obfuscation {
            result = self.transform_strings(&result, log);
        }

        // 2. 混淆变量名
        if self.obfuscator.config.enable_variable_renaming {
            result = self.transform_variables(&result, log);
        }

        // 3. 混淆注释
        if self.obfuscator.config.enable_string_obfuscation {
            result = self.transform_comments(&result, log);
        }

        result
    }

    /// 混淆字符串
    fn transform_strings(&self, code: &str, log: &mut TransformationLog) -> String {
        use regex::Regex;

        // 匹配双引号字符串
        // 🔒 SAFETY: 使用 expect 替代 unwrap，并提供说明喵
        let re = Regex::new(r#""([^"]*)""#).expect("Static regex compilation failed");
        let result = re.replace_all(code, |caps: &regex::Captures| {
            if let Some(cap) = caps.get(1) {
                let original = cap.as_str();
                let obfuscated = self.obfuscator.obfuscate_string(original);
                log.strings_obfuscated += 1;
                format!("\"{}\"", obfuscated)
            } else {
                caps.get(0).map_or("", |m| m.as_str()).to_string()
            }
        });

        result.to_string()
    }

    /// 混淆变量名
    fn transform_variables(&mut self, code: &str, log: &mut TransformationLog) -> String {
        use regex::Regex;

        // 查找变量声明 (let, const, fn 参数)
        // 简化实现：仅匹配 let x = 和 fn name(
        // 🔒 SAFETY: 使用 expect 替代 unwrap 喵
        let re = Regex::new(r"(let|mut)\s+(\w+)\s*=").expect("Static regex compilation failed");
        let result = re.replace_all(code, |caps: &regex::Captures| {
            let keyword = caps.get(1).map_or("", |m| m.as_str());
            let name = caps.get(2).map_or("", |m| m.as_str());

            // 跳过保留字
            if self.is_reserved_word(name) || name.is_empty() {
                return format!("{} {} =", keyword, name);
            }

            // 查找或生成混淆名称
            let obfuscated_name = self.get_or_create_obfuscated_name(name);
            log.variables_renamed += 1;
            format!("{} {} =", keyword, obfuscated_name)
        });

        result.to_string()
    }

    /// 混淆注释
    fn transform_comments(&self, code: &str, log: &mut TransformationLog) -> String {
        // 简化实现：不混淆注释，保留代码可读性
        code.to_string()
    }

    /// 获取或创建混淆名称
    fn get_or_create_obfuscated_name(&mut self, original: &str) -> String {
        if let Some(obfuscated) = self.variable_map.get(original) {
            return obfuscated.clone();
        }

        let obfuscated = self.obfuscator.obfuscate_name(original);
        self.variable_map.insert(original.to_string(), obfuscated.clone());
        obfuscated
    }

    /// 检查是否为保留字
    fn is_reserved_word(&self, word: &str) -> bool {
        let reserved = [
            "self", "Self", "super", "crate",
            "fn", "let", "mut", "const", "static",
            "pub", "struct", "enum", "impl", "use",
            "mod", "trait", "type", "where",
            "for", "while", "loop", "if", "else",
            "match", "return", "break", "continue",
            "true", "false", "None", "Some", "Ok", "Err",
        ];

        reserved.contains(&word)
    }

    /// 生成混淆报告
    pub fn generate_report(&self, result: &TransformerResult) -> String {
        format!(
            "📊 Obfuscation Report\n\
             📝 Original Code: {} lines\n\
             🔒 Obfuscated Code: {} lines\n\
             🔧 Strings Obfuscated: {}\n\
             🔤 Variables Renamed: {}\n\
             💬 Comments Obfuscated: {}",
            result.original_code.lines().count(),
            result.obfuscated_code.lines().count(),
            result.transformation_log.strings_obfuscated,
            result.transformation_log.variables_renamed,
            result.transformation_log.comments_obfuscated,
        )
    }
}

impl Default for ObfuscateTransformer {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// 测试
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_obfuscate_string() {
        let obf = Obfuscator::new();
        let result = obf.obfuscate_string("hello world");
        assert_eq!(result, "obfstr:hello world");
    }

    #[test]
    fn test_obfuscate_name() {
        let obf = Obfuscator::new().with_config(ObfuscateConfig {
            enable_variable_renaming: true,
            ..Default::default()
        });

        let result = obf.obfuscate_name("my_variable");
        assert!(result.starts_with("_0x"));
    }

    #[test]
    fn test_transform_code() {
        let mut transformer = ObfuscateTransformer::new();
        let code = r#"
            let message = "hello world";
            println!("{}", message);
        "#;

        let result = transformer.transform(code).unwrap();
        assert!(result.obfuscated_code.contains("obfstr:"));
    }
}
