//! # AES-256-GCM 加密模块
//!
//! ⚠️ SAFETY: 核心安全模块，用于保护 API Key 和敏感配置喵
//!
//! ## 功能说明
//! - 使用 AES-256-GCM 进行对称加密喵
//! - 自动生成随机 IV（每次加密都是唯一的喵）
//! - 支持加密和解密操作喵
//!
//! ## 加密流程
//! 1. 生成随机 12 字节 IV喵
//! 2. 使用主密钥对明文进行加密喵
//! 3. 返回加密后的密文（IV + 密文 + 认证标签）喵
//!
//! ## 解密流程  
//! 1. 从密文头部提取 12 字节 IV喵
//! 2. 使用主密钥解密剩余部分喵
//! 3. 验证 GCM 认证标签，确保数据完整性喵

use aes_gcm::aead::Aead;
use aes_gcm::{Aes256Gcm, Key, KeyInit, Nonce};
use base64::{engine::general_purpose::STANDARD as BASE64_STD, Engine as _};
use rand::rngs::OsRng;
use rand::RngCore;
use thiserror::Error;

/// 加密错误类型
#[derive(Error, Debug, Clone)]
pub enum CryptoError {
    /// 加密失败喵
    #[error("Encryption failed: {0}")]
    EncryptionError(String),

    /// 解密失败喵
    #[error("Decryption failed: {0}")]
    DecryptionError(String),

    /// 密钥无效喵
    #[error("Invalid key length")]
    InvalidKeyLength,

    /// 密文格式错误喵
    #[error("Invalid ciphertext format")]
    InvalidCiphertext,
}

/// 加密服务结构体
///
/// 🔐 SAFETY: 持有加密密钥，必须严格控制访问权限喵
#[derive(Clone)]
pub struct CryptoService {
    /// AES-256 加密密钥喵
    /// ⚠️ SAFETY: 核心敏感数据，仅限安全模块内部使用喵
    cipher: Aes256Gcm,
}

impl CryptoService {
    /// 创建加密服务喵
    ///
    /// ## Arguments
    /// * `key_bytes` - 32字节密钥（必须完全随机喵）
    ///
    /// ## Returns
    /// 加密服务实例喵
    ///
    /// 🔐 PERMISSION: 仅允许安全模块内部调用喵
    pub fn new(key_bytes: &[u8]) -> Result<Self, CryptoError> {
        if key_bytes.len() != 32 {
            return Err(CryptoError::InvalidKeyLength);
        }
        let key = Key::<Aes256Gcm>::from_slice(key_bytes);
        let cipher = Aes256Gcm::new(key);
        Ok(Self { cipher })
    }

    /// 加密明文喵
    ///
    /// ## Arguments
    /// * `plaintext` - 要加密的明文字符串喵
    ///
    /// ## Returns
    /// Base64编码的加密结果（格式: Base64(IV || Ciphertext || Tag)）喵
    ///
    /// 🔐 PERMISSION: 需要 Admin 权限才能调用喵
    pub fn encrypt(&self, plaintext: &str) -> Result<String, CryptoError> {
        // 1. 生成随机 12 字节 IV喵
        let mut iv_bytes = [0u8; 12];
        OsRng.fill_bytes(&mut iv_bytes);
        let nonce = Nonce::from_slice(&iv_bytes);

        // 2. 执行加密喵
        let ciphertext = self
            .cipher
            .encrypt(nonce, plaintext.as_bytes())
            .map_err(|e| CryptoError::EncryptionError(e.to_string()))?;

        // 3. 组合 IV + Ciphertext + Tag，返回 Base64 编码喵
        let combined = [&iv_bytes[..], &ciphertext].concat();
        Ok(BASE64_STD.encode(combined))
    }

    /// 解密密文喵
    ///
    /// ## Arguments
    /// * `encrypted_data` - Base64编码的加密数据喵
    ///
    /// ## Returns
    /// 解密后的明文字符串喵
    ///
    /// 🔐 PERMISSION: 需要 Admin 权限才能调用喵
    ///
    /// ## Panics
    /// 如果密文格式错误或认证失败，会返回错误喵（不会 panic）
    pub fn decrypt(&self, encrypted_data: &str) -> Result<String, CryptoError> {
        // 1. Base64 解码喵
        let combined = BASE64_STD
            .decode(encrypted_data)
            .map_err(|_| CryptoError::InvalidCiphertext)?;

        if combined.len() < 12 + 16 {
            return Err(CryptoError::InvalidCiphertext);
        }

        // 2. 分离 IV 和密文喵
        let (iv_bytes, ciphertext_with_tag) = combined.split_at(12);
        let nonce = Nonce::from_slice(iv_bytes);

        // 3. 执行解密喵
        let plaintext = self
            .cipher
            .decrypt(nonce, ciphertext_with_tag.as_ref())
            .map_err(|e| CryptoError::DecryptionError(e.to_string()))?;

        // 4. 转换为字符串喵
        String::from_utf8(plaintext).map_err(|e| CryptoError::DecryptionError(e.to_string()))
    }
}

/// 生成随机加密密钥喵
///
/// ## Returns
/// 32 字节随机密钥（Base64 编码）喵
///
/// ⚠️ SAFETY: 生成的密钥必须安全存储，丢失后无法恢复加密数据喵
pub fn generate_key() -> String {
    let mut key_bytes = [0u8; 32];
    OsRng.fill_bytes(&mut key_bytes);
    BASE64_STD.encode(key_bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 测试加密解密循环喵
    #[tokio::test]
    fn test_encrypt_decrypt_cycle() {
        let key = generate_key();
        let crypto = CryptoService::new(&BASE64_STD.decode(&key).unwrap()).unwrap();

        let plaintext = "测试敏感数据喵！😸";
        let encrypted = crypto.encrypt(plaintext).unwrap();
        let decrypted = crypto.decrypt(&encrypted).unwrap();

        assert_eq!(plaintext, decrypted);
    }

    /// 测试空字符串加密喵
    #[tokio::test]
    fn test_empty_string() {
        let key = generate_key();
        let crypto = CryptoService::new(&BASE64_STD.decode(&key).unwrap()).unwrap();

        let encrypted = crypto.encrypt("").unwrap();
        let decrypted = crypto.decrypt(&encrypted).unwrap();

        assert_eq!("", decrypted);
    }
}
