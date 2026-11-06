//! 设备身份模块：生成 Device ID、Ed25519/X25519 密钥对、设备组管理。

use serde::{Deserialize, Serialize};
use ed25519_dalek::{SigningKey, VerifyingKey, Signer, Verifier, Signature};
use x25519_dalek::{StaticSecret, PublicKey};
use rand::rngs::OsRng;
use uuid::Uuid;
use chrono::Utc;

#[derive(Debug, thiserror::Error)]
pub enum IdentityError {
    #[error("密钥生成失败: {0}")]
    KeyGen(String),
    #[error("签名验证失败")]
    SignatureInvalid,
    #[error("密钥长度错误")]
    KeyLength,
    #[error("序列化错误: {0}")]
    Serialize(String),
}

/// 设备平台
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Platform {
    Windows,
    MacOS,
    Android,
    Linux,
}

impl std::fmt::Display for Platform {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            Platform::Windows => write!(f, "Windows"),
            Platform::MacOS => write!(f, "macOS"),
            Platform::Android => write!(f, "Android"),
            Platform::Linux => write!(f, "Linux"),
        }
    }
}

/// 设备能力
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct DeviceCapabilities {
    #[serde(default)]
    pub can_control: bool,
    #[serde(default)]
    pub can_be_controlled: bool,
    #[serde(default)]
    pub supports_clipboard: bool,
    #[serde(default)]
    pub supports_file_transfer: bool,
    #[serde(default)]
    pub supports_audio: bool,
    #[serde(default)]
    pub max_video_width: u32,
    #[serde(default)]
    pub max_video_height: u32,
}

impl DeviceCapabilities {
    pub fn for_windows() -> Self {
        Self {
            can_control: true,
            can_be_controlled: true,
            supports_clipboard: true,
            supports_file_transfer: true,
            supports_audio: true,
            max_video_width: 3840,
            max_video_height: 2160,
            ..Default::default()
        }
    }
    pub fn for_macos() -> Self {
        Self {
            can_control: true,
            can_be_controlled: true,
            supports_clipboard: true,
            supports_file_transfer: true,
            supports_audio: true,
            max_video_width: 3840,
            max_video_height: 2160,
            ..Default::default()
        }
    }
    pub fn for_android() -> Self {
        Self {
            can_control: true,
            can_be_controlled: false,
            supports_clipboard: true,
            supports_file_transfer: true,
            supports_audio: false,
            max_video_width: 1920,
            max_video_height: 1080,
            ..Default::default()
        }
    }
}

/// 设备身份（完整）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceIdentity {
    pub device_id: String,
    pub device_name: String,
    pub platform: Platform,
    pub group_id: String,
    pub ed25519_public_key: String,
    pub x25519_public_key: String,
    pub capabilities: DeviceCapabilities,
    pub created_at: i64,
}

/// 密钥对
#[derive(Clone)]
pub struct KeyPair {
    pub ed25519_signing: SigningKey,
    pub ed25519_verifying: VerifyingKey,
    pub x25519_static: StaticSecret,
    pub ed25519_public_hex: String,
    pub x25519_public_hex: String,
}

impl std::fmt::Debug for KeyPair {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        f.debug_struct("KeyPair")
            .field("ed25519_public_hex", &self.ed25519_public_hex)
            .field("x25519_public_hex", &self.x25519_public_hex)
            .finish()
    }
}

impl KeyPair {
    pub fn generate() -> Result<Self, IdentityError> {
        let mut csprng = OsRng;
        let ed25519_signing = SigningKey::generate(&mut csprng);
        let ed25519_verifying = ed25519_signing.verifying_key();
        let x25519_static = StaticSecret::random_from_rng(&mut csprng);

        let ed25519_public_hex = hex::encode(ed25519_verifying.as_bytes());
        let x25519_public = PublicKey::from(&x25519_static);
        let x25519_public_hex = hex::encode(x25519_public.to_bytes());

        Ok(Self {
            ed25519_signing,
            ed25519_verifying,
            x25519_static,
            ed25519_public_hex,
            x25519_public_hex,
        })
    }

    pub fn restore(
        ed25519_private_hex: &str,
        x25519_private_hex: &str,
    ) -> Result<Self, IdentityError> {
        let ed25519_bytes = hex::decode(ed25519_private_hex)
            .map_err(|e| IdentityError::Serialize(e.to_string()))?;
        let x25519_bytes = hex::decode(x25519_private_hex)
            .map_err(|e| IdentityError::Serialize(e.to_string()))?;

        let ed25519_signing = SigningKey::from_bytes(&ed25519_bytes.try_into().unwrap());
        let ed25519_verifying = ed25519_signing.verifying_key();
        let x25519_arr: [u8; 32] = x25519_bytes.try_into().map_err(|_| IdentityError::KeyLength)?;
        let x25519_static = StaticSecret::from(x25519_arr);

        let ed25519_public_hex = hex::encode(ed25519_verifying.as_bytes());
        let x25519_public = PublicKey::from(&x25519_static);
        let x25519_public_hex = hex::encode(x25519_public.to_bytes());

        Ok(Self {
            ed25519_signing,
            ed25519_verifying,
            x25519_static,
            ed25519_public_hex,
            x25519_public_hex,
        })
    }

    pub fn ed25519_private_hex(&self) -> String {
        hex::encode(self.ed25519_signing.to_bytes())
    }
    pub fn x25519_private_hex(&self) -> String {
        hex::encode(self.x25519_static.to_bytes())
    }

    /// 签名消息
    pub fn sign(&self, message: &[u8]) -> String {
        let sig: Signature = self.ed25519_signing.sign(message);
        hex::encode(sig.to_bytes())
    }

    /// 验证签名
    pub fn verify(&self, message: &[u8], signature_hex: &str) -> bool {
        let sig_bytes = match hex::decode(signature_hex) {
            Ok(b) => b,
            Err(_) => return false,
        };
        let sig = match Signature::from_slice(&sig_bytes) {
            Ok(s) => s,
            Err(_) => return false,
        };
        self.ed25519_verifying.verify(message, &sig).is_ok()
    }
}

/// 创建设备身份
pub fn create_device_identity(
    device_name: &str,
    platform: Platform,
) -> Result<(DeviceIdentity, KeyPair), IdentityError> {
    let kp = KeyPair::generate()?;
    let device_id = Uuid::new_v4().to_string();

    let capabilities = match platform {
        Platform::Windows => DeviceCapabilities::for_windows(),
        Platform::MacOS => DeviceCapabilities::for_macos(),
        Platform::Android => DeviceCapabilities::for_android(),
        Platform::Linux => DeviceCapabilities::for_macos(),
    };

    let identity = DeviceIdentity {
        device_id: device_id.clone(),
        device_name: device_name.to_string(),
        platform,
        group_id: Uuid::new_v4().to_string(),
        ed25519_public_key: kp.ed25519_public_hex.clone(),
        x25519_public_key: kp.x25519_public_hex.clone(),
        capabilities,
        created_at: Utc::now().timestamp(),
    };

    Ok((identity, kp))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_keypair_generate_and_sign() {
        let kp = KeyPair::generate().unwrap();
        let msg = b"hello remotelink";
        let sig = kp.sign(msg);
        assert!(kp.verify(msg, &sig));
        assert!(!kp.verify(b"other message", &sig));
    }

    #[test]
    fn test_identity_creation() {
        let (id, _kp) = create_device_identity("Test PC", Platform::Windows).unwrap();
        assert!(!id.device_id.is_empty());
        assert_eq!(id.platform, Platform::Windows);
        assert!(id.capabilities.can_be_controlled);
    }

    #[test]
    fn test_android_capabilities() {
        let caps = DeviceCapabilities::for_android();
        assert!(caps.can_control);
        assert!(!caps.can_be_controlled);
    }
}
