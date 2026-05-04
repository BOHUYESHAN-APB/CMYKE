//!
//! # 安全模块集成测试
//!
//! ⚠️ SAFETY: 测试 crypto, allowlist, sandbox 模块的集成喵
//!
//! ## 测试范围
//! - CryptoService 加密/解密循环喵
//! - AllowlistService 白名单检查喵
//! - SandboxService 沙箱执行喵
//!
//! ## 运行命令
//! ```bash
//! cargo test --test integration security_test -- --nocapture
//! ```

use crate::security::{CryptoService, CryptoError, generate_key, AllowlistService, AllowlistConfig, AllowlistError, SandboxService, SandboxConfig, SandboxError};
use std::time::Duration;

/// 测试加密服务喵
#[tokio::test]
async fn test_crypto_service() {
    // 1. 测试密钥生成喵
    let key = generate_key();
    assert_eq!(key.len(), 44); // Base64 编码的 32 字节
    
    // 2. 测试加密/解密循环喵
    let crypto = CryptoService::new(&base64::Engine::decode(&base64::Engine::general_purpose::STANDARD, &key).unwrap()).unwrap();
    
    let plaintext = "测试敏感数据喵！😸";
    let encrypted = crypto.encrypt(plaintext).unwrap();
    let decrypted = crypto.decrypt(&encrypted).unwrap();
    
    assert_eq!(plaintext, decrypted);
}

/// 测试加密服务空字符串喵
#[tokio::test]
async fn test_crypto_empty_string() {
    let key = generate_key();
    let crypto = CryptoService::new(&base64::Engine::decode(&base64::Engine::general_purpose::STANDARD, &key).unwrap()).unwrap();
    
    let encrypted = crypto.encrypt("").unwrap();
    let decrypted = crypto.decrypt(&encrypted).unwrap();
    
    assert_eq!("", decrypted);
}

/// 测试加密服务错误密钥喵
#[tokio::test]
async fn test_crypto_invalid_key() {
    let result = CryptoService::new(&[1, 2, 3]); // 错误长度的密钥
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), CryptoError::InvalidKeyLength));
}

/// 测试白名单服务命令检查喵
#[tokio::test]
async fn test_allowlist_command_check() {
    let config = AllowlistConfig::default();
    let service = AllowlistService::new(config);
    
    // 测试允许的命令喵
    assert!(service.check_command("git").is_ok());
    assert!(service.check_command("ls").is_ok());
    assert!(service.check_command("cat").is_ok());
    
    // 测试拒绝的命令喵
    assert!(service.check_command("rm").is_err());
    assert!(service.check_command("chmod").is_err());
    assert!(service.check_command("sudo").is_err());
}

/// 测试白名单服务路径检查喵
#[tokio::test]
async fn test_allowlist_path_check() {
    let config = AllowlistConfig::default();
    let service = AllowlistService::new(config);
    
    // 测试允许的路径喵
    assert!(service.check_path("/home/ubuntu/.openclaw/workspace").is_ok());
    assert!(service.check_path("/tmp/test.txt").is_ok());
    
    // 测试拒绝的路径喵
    assert!(service.check_path("/etc/passwd").is_err());
    assert!(service.check_path("/root/.ssh/id_rsa").is_err());
    
    // 测试路径遍历攻击喵
    assert!(service.check_path("/home/ubuntu/.openclaw/../../../etc/passwd").is_err());
}

/// 测试沙箱服务执行喵
#[tokio::test]
async fn test_sandbox_execution() {
    let allowlist_config = AllowlistConfig::default();
    let allowlist_service = AllowlistService::new(allowlist_config);
    let sandbox_config = SandboxConfig::default();
    let sandbox = SandboxService::new(allowlist_service, sandbox_config);
    
    // 测试允许的命令喵
    let result = sandbox.execute("echo", &["Hello, Neko-Claw!"]);
    assert!(result.is_ok());
    let result = result.unwrap();
    assert!(result.stdout.contains("Hello, Neko-Claw!"));
    assert_eq!(result.exit_code, 0);
}

/// 测试沙箱服务命令白名单喵
#[tokio::test]
async fn test_sandbox_command_whitelist() {
    let allowlist_config = AllowlistConfig::default();
    let allowlist_service = AllowlistService::new(allowlist_config);
    let sandbox_config = SandboxConfig::default();
    let sandbox = SandboxService::new(allowlist_service, sandbox_config);
    
    // 测试拒绝的命令喵
    let result = sandbox.execute("rm", &["-rf", "/tmp/test"]);
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), SandboxError::CommandNotAllowed(_)));
}

/// 测试沙箱服务参数注入防护喵
#[tokio::test]
async fn test_sandbox_parameter_injection_protection() {
    let allowlist_config = AllowlistConfig::default();
    let allowlist_service = AllowlistService::new(allowlist_config);
    let sandbox_config = SandboxConfig::default();
    let sandbox = SandboxService::new(allowlist_service, sandbox_config);
    
    // 测试管道注入喵
    let result = sandbox.execute("echo", &["test | cat"]);
    assert!(result.is_err());
    assert!(matches!(result.unwrap_err(), SandboxError::ParameterInjection(_)));
    
    // 测试命令分隔喵
    let result = sandbox.execute("echo", &["test ; ls"]);
    assert!(result.is_err());
}

/// 测试异步执行喵
#[tokio::test]
async fn test_sandbox_async_execution() {
    let allowlist_config = AllowlistConfig::default();
    let allowlist_service = AllowlistService::new(allowlist_config);
    let sandbox_config = SandboxConfig::default();
    let sandbox = SandboxService::new(allowlist_service, sandbox_config);
    
    let result = sandbox.execute_async("echo", &["Async test"]).await;
    assert!(result.is_ok());
    let result = result.unwrap();
    assert!(result.stdout.contains("Async test"));
    assert!(!result.timed_out);
}

/// 测试白名单服务默认配置喵
#[tokio::test]
fn test_allowlist_default_config() {
    let config = AllowlistConfig::default();
    
    // 检查默认命令喵
    assert!(!config.commands.is_empty());
    assert!(config.commands.iter().any(|c| c.command == "git"));
    assert!(config.commands.iter().any(|c| c.command == "ls"));
    
    // 检查默认路径喵
    assert!(!config.paths.is_empty());
    assert!(config.paths.iter().any(|p| p.pattern.contains("nekoclaw")));
    
    // 检查默认拒绝策略喵
    assert!(config.default_deny);
}

/// 测试沙箱服务默认配置喵
#[tokio::test]
fn test_sandbox_default_config() {
    let config = SandboxConfig::default();
    
    // 检查默认超时喵
    assert_eq!(config.timeout_seconds, 30);
    
    // 检查工作目录喵
    assert!(config.working_directory.is_some());
    
    // 检查环境变量白名单喵
    assert!(!config.env_whitelist.is_empty());
}
