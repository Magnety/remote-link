//! 信令模块：SignalingProvider 统一接口 + 信令状态管理。

use serde::{Deserialize, Serialize};
use thiserror::Error;
use rl_protocol::{SignalingMessage, MessageType};

#[derive(Debug, Error)]
pub enum SignalingError {
    #[error("未连接")]
    NotConnected,
    #[error("连接错误: {0}")]
    Connection(String),
    #[error("消息发送失败: {0}")]
    SendFailed(String),
    #[error("消息接收错误: {0}")]
    Receive(String),
    #[error("适配器错误: {0}")]
    Adapter(String),
    #[error("不支持的操作: {0}")]
    Unsupported(String),
}

/// 信令适配器能力
#[derive(Debug, Clone, Default)]
pub struct SignalingCapabilities {
    pub supports_device_discovery: bool,
    pub supports_multi_client: bool,
    pub max_message_size: usize,
    pub rate_limit_per_min: Option<u32>,
    pub requires_public_endpoint: bool,
    pub description: String,
}

/// 信令连接配置
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalingConfig {
    /// 适配器类型
    #[serde(rename = "adapter_type")]
    pub adapter_type: AdapterType,
    /// AppID / Endpoint
    #[serde(default)]
    pub app_id: String,
    /// API Key / AppSecret / Token
    #[serde(default)]
    pub api_key: String,
    /// 额外参数 (JSON)
    #[serde(default)]
    pub extra: serde_json::Value,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum AdapterType {
    #[default]
    Mock,
    QqOfficial,
    OneBot,
}

/// 信令接收消息
#[derive(Debug, Clone)]
pub struct ReceivedMessage {
    pub message: SignalingMessage,
    pub raw: String,
}

/// 统一信令提供者接口
#[async_trait::async_trait]
pub trait SignalingProvider: Send + Sync {
    /// 连接信令服务器
    async fn connect(&mut self, config: &SignalingConfig) -> Result<SignalingCapabilities, SignalingError>;
    /// 断开连接
    async fn disconnect(&mut self);
    /// 发布消息
    async fn publish(&self, msg: &SignalingMessage) -> Result<(), SignalingError>;
    /// 接收下一条消息
    async fn receive(&mut self) -> Result<ReceivedMessage, SignalingError>;
    /// 获取能力
    fn get_capabilities(&self) -> &SignalingCapabilities;
    /// 请求设备发现
    async fn request_device_discovery(&self, group_id: &str) -> Result<(), SignalingError>;
    /// 发送连接请求
    async fn send_connection_request(&self, target_device_id: &str, session_id: &str, payload: &str) -> Result<(), SignalingError>;
    /// 发送连接响应
    async fn send_connection_response(&self, target_device_id: &str, session_id: &str, accepted: bool, payload: &str) -> Result<(), SignalingError>;
    /// 发送 SDP Offer
    async fn send_sdp_offer(&self, target_device_id: &str, session_id: &str, sdp: &str) -> Result<(), SignalingError>;
    /// 发送 SDP Answer
    async fn send_sdp_answer(&self, target_device_id: &str, session_id: &str, sdp: &str) -> Result<(), SignalingError>;
    /// 发送 ICE Candidates
    async fn send_ice_candidates(&self, target_device_id: &str, session_id: &str, candidates_json: &str) -> Result<(), SignalingError>;
}

/// 信令管理器：封装具体适配器
pub struct SignalingManager {
    capabilities: SignalingCapabilities,
    connected: bool,
    config: Option<SignalingConfig>,
}

impl SignalingManager {
    pub fn new() -> Self {
        Self {
            capabilities: SignalingCapabilities::default(),
            connected: false,
            config: None,
        }
    }

    pub fn is_connected(&self) -> bool {
        self.connected
    }

    pub fn capabilities(&self) -> &SignalingCapabilities {
        &self.capabilities
    }

    pub fn config(&self) -> Option<&SignalingConfig> {
        self.config.as_ref()
    }
}

impl Default for SignalingManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_serialization() {
        let config = SignalingConfig {
            adapter_type: AdapterType::OneBot,
            app_id: "ws://localhost:3001".into(),
            api_key: "token123".into(),
            extra: serde_json::json!({}),
        };
        let json = serde_json::to_string(&config).unwrap();
        let config2: SignalingConfig = serde_json::from_str(&json).unwrap();
        assert_eq!(config2.adapter_type, AdapterType::OneBot);
        assert_eq!(config2.app_id, "ws://localhost:3001");
    }
}
