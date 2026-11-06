//! 安全模块：端到端加密、防重放、消息去重。

use aes_gcm::{Aes256Gcm, KeyInit, Key, Nonce, aead::Aead};
use rand::RngCore;
use base64::{Engine, engine::general_purpose::STANDARD};

#[derive(Debug, thiserror::Error)]
pub enum SecurityError {
    #[error("加密失败")]
    EncryptFailed,
    #[error("解密失败")]
    DecryptFailed,
    #[error("密钥长度错误")]
    KeyLength,
    #[error("重放攻击检测")]
    ReplayDetected,
    #[error("消息重复")]
    DuplicateMessage,
}

/// AES-256-GCM 加密器
pub struct E2eCipher {
    cipher: Aes256Gcm,
}

impl E2eCipher {
    pub fn new(key: &[u8; 32]) -> Self {
        let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
        Self { cipher }
    }

    pub fn from_shared_secret(shared: &[u8]) -> Self {
        let mut key = [0u8; 32];
        let len = shared.len().min(32);
        key[..len].copy_from_slice(&shared[..len]);
        Self::new(&key)
    }

    pub fn encrypt(&self, plaintext: &[u8]) -> Result<String, SecurityError> {
        let mut nonce_bytes = [0u8; 12];
        rand::thread_rng().fill_bytes(&mut nonce_bytes);
        let nonce = Nonce::from_slice(&nonce_bytes);

        let ciphertext = self.cipher.encrypt(nonce, plaintext)
            .map_err(|_| SecurityError::EncryptFailed)?;

        let mut combined = Vec::with_capacity(12 + ciphertext.len());
        combined.extend_from_slice(&nonce_bytes);
        combined.extend_from_slice(&ciphertext);

        Ok(STANDARD.encode(&combined))
    }

    pub fn decrypt(&self, encoded: &str) -> Result<Vec<u8>, SecurityError> {
        let combined = STANDARD.decode(encoded)
            .map_err(|_| SecurityError::DecryptFailed)?;

        if combined.len() < 12 + 16 {
            return Err(SecurityError::DecryptFailed);
        }

        let nonce = Nonce::from_slice(&combined[..12]);
        let ciphertext = &combined[12..];

        self.cipher.decrypt(nonce, ciphertext)
            .map_err(|_| SecurityError::DecryptFailed)
    }
}

/// 防重放：记录已处理的 message_id
#[derive(Default)]
pub struct ReplayProtector {
    seen: std::collections::HashSet<String>,
}

impl ReplayProtector {
    pub fn check_and_mark(&mut self, message_id: &str) -> Result<(), SecurityError> {
        if self.seen.contains(message_id) {
            return Err(SecurityError::DuplicateMessage);
        }
        self.seen.insert(message_id.to_string());
        if self.seen.len() > 10000 {
            let to_remove: Vec<String> = self
                .seen
                .iter()
                .take(self.seen.len() - 5000)
                .cloned()
                .collect();
            for k in to_remove {
                self.seen.remove(&k);
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_e2e_roundtrip() {
        let key = [42u8; 32];
        let cipher = E2eCipher::new(&key);
        let plaintext = b"secret remotelink message";
        let encrypted = cipher.encrypt(plaintext).unwrap();
        assert_ne!(encrypted, STANDARD.encode(plaintext));
        let decrypted = cipher.decrypt(&encrypted).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_replay_protection() {
        let mut rp = ReplayProtector::default();
        rp.check_and_mark("msg-1").unwrap();
        assert!(rp.check_and_mark("msg-1").is_err());
        rp.check_and_mark("msg-2").unwrap();
    }
}
