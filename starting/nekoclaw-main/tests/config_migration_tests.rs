/// 配置迁移测试 🧪
///
/// @诺诺 的配置迁移测试实现喵
///
/// 测试内容：
/// - OpenClaw → Neko-Claw 配置转换
/// - 必填项验证
/// - 类型验证
/// - 迁移完整性检查
///
/// 🔒 SAFETY: 所有测试必须在迁移前通过
///
/// 实现者: 诺诺 (Nono) ⚡

#[cfg(test)]
mod config_migration_tests {
    use super::super::validator::{
        ConfigValidator, MigrationValidator, ValidationError, ValidationResult, ValidationRule,
    };
    use serde_json::json;

    /// 🔒 SAFETY: 测试必填项检查喵
    #[test]
    fn test_required_field_validation() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(ValidationRule::new("required_field".to_string()).required());

        // 缺少必填项应该失败
        let config = json!({});
        let result = validator.validate(&config);
        assert!(result.is_err());

        // 存在必填项应该通过
        let config = json!({ "required_field": "value" });
        let result = validator.validate(&config);
        assert!(result.is_ok());
    }

    /// 🔒 SAFETY: 测试类型验证喵
    #[test]
    fn test_type_validation() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(ValidationRule::new("age".to_string()).with_type("number".to_string()));

        // 类型正确应该通过
        let config = json!({ "age": 25 });
        assert!(validator.validate(&config).is_ok());

        // 类型错误应该失败
        let config = json!({ "age": "25" });
        let result = validator.validate(&config);
        assert!(result.is_err());
    }

    /// 🔒 SAFETY: 测试数值范围验证喵
    #[test]
    fn test_range_validation() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(ValidationRule::new("percentage".to_string()).with_range(0.0, 100.0));

        // 在范围内应该通过
        let config = json!({ "percentage": 50.0 });
        assert!(validator.validate(&config).is_ok());

        // 超出范围应该失败
        let config = json!({ "percentage": 150.0 });
        let result = validator.validate(&config);
        assert!(result.is_err());

        // 低于范围应该失败
        let config = json!({ "percentage": -10.0 });
        let result = validator.validate(&config);
        assert!(result.is_err());
    }

    /// 🔒 SAFETY: 测试长度验证喵
    #[test]
    fn test_length_validation() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(ValidationRule::new("username".to_string()).with_length_range(3, 20));

        // 长度正确应该通过
        let config = json!({ "username": "alice" });
        assert!(validator.validate(&config).is_ok());

        // 太短应该失败
        let config = json!({ "username": "ab" });
        let result = validator.validate(&config);
        assert!(result.is_err());

        // 太长应该失败
        let config = json!({ "username": "a".repeat(21) });
        let result = validator.validate(&config);
        assert!(result.is_err());
    }

    /// 🔒 SAFETY: 测试允许值验证喵
    #[test]
    fn test_allowed_values_validation() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(
            ValidationRule::new("status".to_string()).with_allowed_values(vec![
                "active".to_string(),
                "inactive".to_string(),
                "pending".to_string(),
            ]),
        );

        // 允许的值应该通过
        let config = json!({ "status": "active" });
        assert!(validator.validate(&config).is_ok());

        // 不允许的值应该失败
        let config = json!({ "status": "deleted" });
        let result = validator.validate(&config);
        assert!(result.is_err());
    }

    /// 🔒 SAFETY: 测试依赖项验证喵
    #[test]
    fn test_dependency_validation() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(
            ValidationRule::new("password".to_string())
                .required()
                .with_dependency("username".to_string()),
        );

        // 缺少依赖项应该失败
        let config = json!({ "password": "secret" });
        let result = validator.validate(&config);
        assert!(result.is_err());

        // 存在依赖项应该通过
        let config = json!({
            "username": "alice",
            "password": "secret"
        });
        assert!(validator.validate(&config).is_ok());
    }

    /// 🔒 SAFETY: 测试正则表达式验证喵
    #[test]
    fn test_regex_validation() {
        let mut validator = ConfigValidator::new();
        validator.add_rule(
            ValidationRule::new("email".to_string())
                .with_pattern(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$".to_string()),
        );

        // 有效邮箱应该通过
        let config = json!({ "email": "test@example.com" });
        assert!(validator.validate(&config).is_ok());

        // 无效邮箱应该失败
        let config = json!({ "email": "invalid-email" });
        let result = validator.validate(&config);
        assert!(result.is_err());
    }

    /// 🔒 SAFETY: 测试多个错误喵
    #[test]
    fn test_multiple_errors() {
        let mut validator = ConfigValidator::new();
        validator.add_rules(vec![
            ValidationRule::new("field1".to_string()).required(),
            ValidationRule::new("field2".to_string()).required(),
        ]);

        let config = json!({});
        let result = validator.validate(&config);

        assert!(result.is_err());
        match result {
            Err(ValidationError::Multiple(errors)) => {
                assert_eq!(errors.len(), 2);
            }
            _ => panic!("Expected Multiple errors"),
        }
    }

    /// 🔒 SAFETY: 测试迁移验证器 - Provider 配置喵
    #[test]
    fn test_migration_provider_config() {
        let validator = MigrationValidator::new();

        let valid_config = json!({
            "models": {
                "providers": {
                    "nvidia": {
                        "apiKey": "test-api-key-123456"
                    }
                }
            }
        });

        let result = validator.validate_openclaw_config(&valid_config);
        assert!(result.is_ok());
    }

    /// 🔒 SAFETY: 测试迁移验证器 - Discord 配置喵
    #[test]
    fn test_migration_discord_config() {
        let validator = MigrationValidator::new();

        let invalid_config = json!({
            "channels": {
                "discord": {
                    "accounts": {
                        "main_bot": {
                            "token": "invalid-token"
                        }
                    }
                }
            }
        });

        let result = validator.validate_openclaw_config(&invalid_config);
        assert!(result.is_err());
    }

    /// 🔒 SAFETY: 测试迁移验证器 - Agent 配置喵
    #[test]
    fn test_migration_agent_config() {
        let validator = MigrationValidator::new();

        let valid_config = json!({
            "agents": {
                "defaults": {
                    "model": {
                        "primary": "nvidia/z-ai/glm4.7"
                    }
                }
            }
        });

        let result = validator.validate_openclaw_config(&valid_config);
        assert!(result.is_ok());
    }

    /// 🔒 SAFETY: 测试完整 OpenClaw 配置验证喵
    #[test]
    fn test_full_openclaw_config_validation() {
        let validator = MigrationValidator::new();

        let complete_config = json!({
            "version": "1.0.0",
            "gateway": {
                "host": "localhost",
                "port": 8080
            },
            "models": {
                "providers": {
                    "nvidia": {
                        "apiKey": "test-api-key-123456"
                    }
                }
            },
            "channels": {
                "discord": {
                    "accounts": {
                        "main_bot": {
                            "token": "DISCORD_BOT_TOKEN_PLACEHOLDER"
                        }
                    }
                }
            },
            "agents": {
                "defaults": {
                    "model": {
                        "primary": "nvidia/z-ai/glm4.7"
                    }
                }
            },
            "memory": {
                "enabled": true
            },
            "performance": {
                "maxContextTokens": 8192
            }
        });

        let result = validator.validate_openclaw_config(&complete_config);
        assert!(result.is_ok());
    }

    /// 🔒 SAFETY: 测试验证结果结构体喵
    #[test]
    fn test_validation_result() {
        let success = ValidationResult::success();
        assert!(success.passed);
        assert!(success.errors.is_empty());

        let error = ValidationError::MissingRequired("field".to_string());
        let failure = ValidationResult::failure(error).with_warning("Test warning".to_string());
        assert!(!failure.passed);
        assert_eq!(failure.errors.len(), 1);
        assert_eq!(failure.warnings.len(), 1);
    }

    /// 🔒 SAFETY: 测试配置规则链式构建喵
    #[test]
    fn test_rule_builder() {
        let rule = ValidationRule::new("username".to_string())
            .required()
            .with_type("string".to_string())
            .with_length_range(3, 20)
            .with_pattern(r"^[a-zA-Z0-9_]+$".to_string());

        assert!(rule.required);
        assert_eq!(rule.expected_type, Some("string".to_string()));
        assert_eq!(rule.min_length, Some(3));
        assert_eq!(rule.max_length, Some(20));
        assert_eq!(rule.regex_pattern, Some(r"^[a-zA-Z0-9_]+$".to_string()));
    }
}
