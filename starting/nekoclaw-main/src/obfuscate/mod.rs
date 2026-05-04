/*!
 * Obfuscate Module - Code Obfuscation
 *
 * 作者: 缪斯 (Muse) @缪斯
 * 日期: 2026-02-15 18:50 JST
 *
 * 功能:
 * - 字符串混淆
 * - 变量名混淆
 * - 代码流程混淆
 * - 使用 obfstr 编译时混淆
 */

pub mod transformer;

pub use transformer::ObfuscateTransformer;

use crate::core::traits::*;

/// 混淆配置
#[derive(Debug, Clone)]
pub struct ObfuscateConfig {
    pub enable_string_obfuscation: bool,
    pub enable_variable_renaming: bool,
    pub enable_flow_obfuscation: bool,
}

impl Default for ObfuscateConfig {
    fn default() -> Self {
        Self {
            enable_string_obfuscation: true,
            enable_variable_renaming: false,  // 默认关闭，可能导致兼容性问题
            enable_flow_obfuscation: false,   // 默认关闭
        }
    }
}

/// 混淆器
pub struct Obfuscator {
    config: ObfuscateConfig,
}

impl Obfuscator {
    /// 创建新的混淆器
    pub fn new() -> Self {
        Self {
            config: ObfuscateConfig::default(),
        }
    }

    /// 使用自定义配置
    pub fn with_config(mut self, config: ObfuscateConfig) -> Self {
        self.config = config;
        self
    }

    /// 混淆字符串 (使用 obfstr)
    pub fn obfuscate_string(&self, s: &str) -> String {
        // 使用 obfstr::obfstr 宏实现编译时混淆
        // 这里提供运行时回退
        format!("obfstr:{}", s)
    }

    /// 混淆字符串 (编译时混淆)
    #[macro_export]
    macro_rules! obf_str {
        ($s:expr) => {
            obfstr::obfstr!($s).to_string()
        };
    }

    /// 混淆变量名
    pub fn obfuscate_name(&self, name: &str) -> String {
        if !self.config.enable_variable_renaming {
            return name.to_string();
        }

        // 简单的哈希混淆
        use std::collections::hash_map::DefaultHasher;
        use std::hash::{Hash, Hasher};

        let mut hasher = DefaultHasher::new();
        name.hash(&mut hasher);
        let hash = hasher.finish();

        // 转换为 C 变量名 (以字母或下划线开头)
        format!("_0x{:x}", hash)
    }

    /// 生成混淆的代码注释
    pub fn obfuscated_comment(&self, comment: &str) -> String {
        if !self.config.enable_string_obfuscation {
            return format!("// {}", comment);
        }

        use crate::obfuscate::Obfuscator;
        let obf_comment = self.obfuscate_string(comment);
        format!("/* {} */", obf_comment)
    }
}

impl Default for Obfuscator {
    fn default() -> Self {
        Self::new()
    }
}
