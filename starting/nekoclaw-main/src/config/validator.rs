//! # Configuration Validator
//!
//! 🛡️ 安全的配置验证模块喵
//!
//! ## 功能
//! - JSON/YAML 格式验证
//! - 字段必填项检查
//! - 类型检查 (string, number, boolean, array, object)
//! - 数值范围验证
//! - 字符串长度验证
//! - 正则表达式格式验证 (Email, URL, Token 等)
//! - 字段依赖验证
//!
//! 🔒 SAFETY: 核心配置验证，防止非法配置导致崩溃喵
//!
//! 作者: 缪斯 (Muse) @缪斯

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use thiserror::Error;
use regex::Regex;

/// 🔒 SAFETY: 配置验证错误类型喵
#[derive(Debug, Error, Serialize, Deserialize, Clone)]
pub enum ValidationError {
    #[error("Missing required field: {0}")]
    MissingRequired(String),

    #[error("Type mismatch for field {0}: expected {1}, found {2}")]
    TypeMismatch(String, String, String),

    #[error("Value out of range for field {0}: {1}")]
    OutOfRange(String, String),

    #[error("Invalid format for field {0}: {1}")]
    InvalidFormat(String, String),

    #[error("Dependency check failed: field {0} requires {1}")]
    DependencyMissing(String, String),

    #[error("Multiple validation errors: {0:?}")]
    Multiple(Vec<String>),
}

/// 🔒 SAFETY: 验证规则定义喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationRule {
    /// 字段路径 (e.g., "models.providers.openai.apiKey")
    pub field_name: String,
    /// 是否必填
    pub required: bool,
    /// 期望类型
    pub expected_type: Option<String>,
    /// 最小值（数字）
    pub min: Option<f64>,
    /// 最大值（数字）
    pub max: Option<f64>,
    /// 最小长度（字符串/数组）
    pub min_length: Option<usize>,
    /// 最大长度（字符串/数组）
    pub max_length: Option<usize>,
    /// 允许的值（枚举）
    pub allowed_values: Option<Vec<String>>,
    /// 正则表达式格式验证
    pub regex_pattern: Option<String>,
    /// 依赖的字段
    pub dependencies: Vec<String>,
}

impl ValidationRule {
    /// 🔒 SAFETY: 创建新的验证规则喵
    pub fn new(field_name: impl Into<String>) -> Self {
        Self {
            field_name: field_name.into(),
            required: false,
            expected_type: None,
            min: None,
            max: None,
            min_length: None,
            max_length: None,
            allowed_values: None,
            regex_pattern: None,
            dependencies: Vec::new(),
        }
    }

    /// 🔒 SAFETY: 设置为必填喵
    pub fn required(mut self) -> Self {
        self.required = true;
        self
    }

    /// 🔒 SAFETY: 设置期望类型喵
    pub fn with_type(mut self, type_name: impl Into<String>) -> Self {
        self.expected_type = Some(type_name.into());
        self
    }

    /// 🔒 SAFETY: 设置数值范围喵
    pub fn with_range(mut self, min: f64, max: f64) -> Self {
        self.min = Some(min);
        self.max = Some(max);
        self
    }

    /// 🔒 SAFETY: 设置长度范围喵
    pub fn with_length_range(mut self, min_len: usize, max_len: usize) -> Self {
        self.min_length = Some(min_len);
        self.max_length = Some(max_len);
        self
    }

    /// 🔒 SAFETY: 设置允许的值喵
    pub fn with_allowed_values(mut self, values: Vec<String>) -> Self {
        self.allowed_values = Some(values);
        self
    }

    /// 🔒 SAFETY: 设置正则表达式喵
    pub fn with_pattern(mut self, pattern: impl Into<String>) -> Self {
        self.regex_pattern = Some(pattern.into());
        self
    }

    /// 🔒 SAFETY: 添加依赖喵
    pub fn with_dependency(mut self, dependency: impl Into<String>) -> Self {
        self.dependencies.push(dependency.into());
        self
    }
}

/// 🔒 SAFETY: 配置验证结果喵
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    pub passed: bool,
    pub errors: Vec<String>,
    pub warnings: Vec<String>,
}

impl ValidationResult {
    /// 🔒 SAFETY: 创建成功的验证结果喵
    pub fn success() -> Self {
        Self {
            passed: true,
            errors: Vec::new(),
            warnings: Vec::new(),
        }
    }

    /// 🔒 SAFETY: 创建失败的验证结果喵
    pub fn failure(error: ValidationError) -> Self {
        Self {
            passed: false,
            errors: vec![error.to_string()],
            warnings: Vec::new(),
        }
    }

    /// 🔒 SAFETY: 添加警告喵
    pub fn with_warning(mut self, warning: String) -> Self {
        self.warnings.push(warning);
        self
    }
}

/// 🔒 SAFETY: 配置验证器喵
pub struct ConfigValidator {
    /// 验证规则集合
    rules: HashMap<String, ValidationRule>,
}

impl ConfigValidator {
    /// 🔒 SAFETY: 创建新的配置验证器喵
    pub fn new() -> Self {
        Self {
            rules: HashMap::new(),
        }
    }

    /// 🔒 SAFETY: 添加验证规则喵
    pub fn add_rule(&mut self, rule: ValidationRule) {
        self.rules.insert(rule.field_name.clone(), rule);
    }

    /// 🔒 SAFETY: 验证配置喵
    pub fn validate(&self, config: &serde_json::Value) -> Result<(), ValidationError> {
        let mut errors = Vec::new();

        for rule in self.rules.values() {
            // 获取字段值 (支持嵌套路径喵)
            let mut current = config;
            let parts: Vec<&str> = rule.field_name.split('.').collect();
            let mut found = true;

            for part in parts {
                if let Some(next) = current.get(part) {
                    current = next;
                } else {
                    found = false;
                    break;
                }
            }

            if !found {
                if rule.required {
                    errors.push(ValidationError::MissingRequired(rule.field_name.clone()).to_string());
                }
                continue;
            }

            // 类型检查
            if let Some(expected) = &rule.expected_type {
                let actual = match current {
                    serde_json::Value::Null => "null",
                    serde_json::Value::Bool(_) => "boolean",
                    serde_json::Value::Number(_) => "number",
                    serde_json::Value::String(_) => "string",
                    serde_json::Value::Array(_) => "array",
                    serde_json::Value::Object(_) => "object",
                };

                if actual != expected {
                    errors.push(ValidationError::TypeMismatch(rule.field_name.clone(), expected.clone(), actual.to_string()).to_string());
                }
            }

            // 数值范围检查
            if let Some(val) = current.as_f64() {
                if let Some(min) = rule.min {
                    if val < min {
                        errors.push(ValidationError::OutOfRange(rule.field_name.clone(), format!("value {} < min {}", val, min)).to_string());
                    }
                }
                if let Some(max) = rule.max {
                    if val > max {
                        errors.push(ValidationError::OutOfRange(rule.field_name.clone(), format!("value {} > max {}", val, max)).to_string());
                    }
                }
            }

            // 长度检查
            if let Some(s) = current.as_str() {
                let len = s.len();
                if let Some(min) = rule.min_length {
                    if len < min {
                        errors.push(ValidationError::InvalidFormat(rule.field_name.clone(), format!("length {} < min {}", len, min)).to_string());
                    }
                }
                if let Some(max) = rule.max_length {
                    if len > max {
                        errors.push(ValidationError::InvalidFormat(rule.field_name.clone(), format!("length {} > max {}", len, max)).to_string());
                    }
                }

                // 正则表达式检查
                if let Some(pattern) = &rule.regex_pattern {
                    match Regex::new(pattern) {
                        Ok(re) => {
                            if !re.is_match(s) {
                                errors.push(ValidationError::InvalidFormat(rule.field_name.clone(), format!("value does not match pattern {}", pattern)).to_string());
                            }
                        }
                        Err(e) => {
                            errors.push(ValidationError::InvalidFormat(rule.field_name.clone(), format!("invalid regex pattern: {}", e)).to_string());
                        }
                    }
                }
            }

            // 允许值检查
            if let Some(allowed) = &rule.allowed_values {
                if let Some(s) = current.as_str() {
                    if !allowed.contains(&s.to_string()) {
                        errors.push(ValidationError::InvalidFormat(rule.field_name.clone(), format!("value {} not in allowed list {:?}", s, allowed)).to_string());
                    }
                }
            }

            // 依赖项检查
            for dep in &rule.dependencies {
                let mut dep_found = true;
                let mut dep_current = config;
                for part in dep.split('.') {
                    if let Some(next) = dep_current.get(part) {
                        dep_current = next;
                    } else {
                        dep_found = false;
                        break;
                    }
                }
                if !dep_found {
                    errors.push(ValidationError::DependencyMissing(rule.field_name.clone(), dep.clone()).to_string());
                }
            }
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(ValidationError::Multiple(errors))
        }
    }

    /// 🔒 SAFETY: 验证 YAML 配置喵
    pub fn validate_yaml(&self, yaml_str: &str) -> Result<(), ValidationError> {
        let config: serde_json::Value = serde_yaml::from_str::<serde_json::Value>(yaml_str)
            .map_err(|e| ValidationError::InvalidFormat("root".to_string(), e.to_string()))?;
        self.validate(&config)
    }

    /// 🔒 SAFETY: 验证 JSON 配置喵
    pub fn validate_json(&self, json_str: &str) -> Result<(), ValidationError> {
        let config: serde_json::Value = serde_json::from_str::<serde_json::Value>(json_str)
            .map_err(|e| ValidationError::InvalidFormat("root".to_string(), e.to_string()))?;
        self.validate(&config)
    }
}

impl Default for ConfigValidator {
    fn default() -> Self {
        Self::new()
    }
}

/// 🔒 SAFETY: 配置迁移验证器喵
/// 专门用于验证 OpenClaw 到 Neko-Claw 的配置迁移
pub struct MigrationValidator {
    /// 验证器
    validator: ConfigValidator,
}

impl MigrationValidator {
    /// 🔒 SAFETY: 创建新的迁移验证器喵
    pub fn new() -> Self {
        let mut validator = ConfigValidator::new();

        // Provider 配置验证
        validator.add_rule(
            ValidationRule::new("models.providers.nvidia.apiKey")
                .required()
                .with_type("string")
                .with_length_range(1, 1000),
        );

        // Discord Token 验证
        validator.add_rule(
            ValidationRule::new("channels.discord.accounts.main_bot.token")
                .required()
                .with_type("string")
                .with_pattern(r"^[A-Za-z0-9._-]{24,}\.[A-Za-z0-9._-]{6,}\.[A-Za-z0-9._-]{27,}$"),
        );

        // Agent 模型验证
        validator.add_rule(
            ValidationRule::new("agents.defaults.model.primary")
                .required()
                .with_type("string"),
        );

        // 内存验证
        validator.add_rule(
            ValidationRule::new("memory.enabled")
                .with_type("boolean"),
        );

        // 性能配置验证
        validator.add_rule(
            ValidationRule::new("performance.maxContextTokens")
                .with_type("number")
                .with_range(1000.0, 128000.0),
        );

        Self { validator }
    }

    /// 🔒 SAFETY: 验证 OpenClaw 配置喵
    pub fn validate_openclaw_config(&self, config: &serde_json::Value) -> Result<ValidationResult, ValidationError> {
        self.validator.validate(config)?;
        Ok(ValidationResult::success())
    }

    /// 🔒 SAFETY: 验证迁移后的 Neko-Claw 配置喵
    pub fn validate_nekoclaw_config(&self, config: &serde_json::Value) -> Result<ValidationResult, ValidationError> {
        self.validator.validate(config)?;
        Ok(ValidationResult::success())
    }
}

impl Default for MigrationValidator {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validation_rule_creation() {
        let rule = ValidationRule::new("test_field")
            .required()
            .with_type("string")
            .with_length_range(1, 100);

        assert_eq!(rule.field_name, "test_field");
        assert!(rule.required);
        assert_eq!(rule.expected_type, Some("string".to_string()));
    }

    #[test]
    fn test_config_validator_required_field() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(
            ValidationRule::new("required_field")
                .required()
        );

        let config = serde_json::json!({});
        let result = validator.validate(&config);

        assert!(result.is_err());
    }

    #[test]
    fn test_config_validator_type_mismatch() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(
            ValidationRule::new("age")
                .with_type("number")
        );

        let config = serde_json::json!({ "age": "not a number" });
        let result = validator.validate(&config);

        assert!(result.is_err());
    }

    #[test]
    fn test_config_validator_success() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(
            ValidationRule::new("name")
                .required()
                .with_type("string")
                .with_length_range(1, 50),
        );

        let config = serde_json::json!({ "name": "Test User" });
        let result = validator.validate(&config);

        assert!(result.is_ok());
    }

    #[test]
    fn test_validation_result() {
        let success = ValidationResult::success();
        assert!(success.passed);
        assert!(success.errors.is_empty());

        let error = ValidationError::MissingRequired("field".to_string());
        let failure = ValidationResult::failure(error).with_warning("This is a warning".to_string());
        assert!(!failure.passed);
        assert_eq!(failure.warnings.len(), 1);
    }
}
