//! 通信协议定义：消息类型、字段结构、序列化/反序列化。

use serde::{Deserialize, Serialize, de::DeserializeOwned};

/// 协议版本
pub const PROTOCOL_VERSION: u32 = 1;

/// 消息类型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum MessageType {
    DeviceOnline,
    DeviceUpdate,
    DeviceHeartbeat,
    DeviceOffline,
    DeviceDiscover,
    DeviceDiscoverResponse,
    DevicePairRequest,
    DevicePairAccept,
    DevicePairReject,
    ConnectRequest,
    ConnectAccept,
    ConnectReject,
    SdpOffer,
    SdpAnswer,
    IceCandidates,
    ConnectionEstablished,
    ConnectionFailed,
    Disconnect,
}

/// 设备在线状态
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DeviceStatus {
    Online,
    Stale,
    Offline,
    Unknown,
    Connecting,
    InSession,
}

/// 连接状态
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ConnectionState {
    Idle,
    Requesting,
    Authorizing,
    Negotiating,
    Connecting,
    Connected,
    Reconnecting,
    Disconnected,
    Failed,
}

/// ICE Candidate
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IceCandidate {
    pub candidate: String,
    pub sdp_mid: Option<String>,
    pub sdp_mline_index: Option<u32>,
}

/// 连接请求载荷
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectRequestPayload {
    pub mode: ConnectMode,
    pub monitor_index: Option<u32>,
    pub preferred_resolution: Option<(u32, u32)>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectMode {
    ReadOnly,
    FullControl,
}

/// 连接接受载荷
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectAcceptPayload {
    pub mode: ConnectMode,
    pub session_timeout_secs: u64,
    pub clipboard_allowed: bool,
    pub file_transfer_allowed: bool,
}

/// SDP 载荷
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SdpPayload {
    pub sdp: String,
    pub sdp_type: String,
}

/// ICE 候选载荷
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IceCandidatesPayload {
    pub candidates: Vec<IceCandidate>,
}

/// 配对请求载荷
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PairRequestPayload {
    pub device_name: String,
    pub platform: String,
    pub group_code: String,
    pub ed25519_public_key: String,
    pub x25519_public_key: String,
}

/// 心跳载荷
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeartbeatPayload {
    pub status: DeviceStatus,
    pub network_version: u64,
    pub extra: Option<String>,
}

/// 设备发现请求载荷
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscoverPayload {
    pub group_id: String,
}

/// 设备发现响应载荷
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DiscoverResponsePayload {
    pub devices: Vec<DeviceInfo>,
}

/// 设备信息
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub status: DeviceStatus,
    pub last_seen: i64,
    pub network_version: u64,
    pub capabilities: Option<String>,
}

/// 消息体（完整信令消息）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignalingMessage {
    pub protocol_version: u32,
    pub message_type: MessageType,
    pub message_id: String,
    pub group_id: String,
    pub sender_device_id: String,
    pub target_device_id: Option<String>,
    pub session_id: Option<String>,
    pub sequence: u64,
    pub timestamp: i64,
    pub expires_at: i64,
    pub payload: Option<String>,
    pub signature: String,
    #[serde(default)]
    pub is_fragmented: bool,
    #[serde(default)]
    pub fragment_index: u32,
    #[serde(default)]
    pub fragment_total: u32,
}

impl SignalingMessage {
    pub fn new(
        message_type: MessageType,
        group_id: &str,
        sender_device_id: &str,
        target_device_id: Option<&str>,
        session_id: Option<&str>,
        payload: Option<impl Serialize>,
    ) -> Self {
        let message_id = uuid::Uuid::new_v4().to_string();
        let now = chrono::Utc::now().timestamp();
        let expires_at = now + 300;

        let payload_str = payload
            .map(|p| serde_json::to_string(&p).unwrap_or_default())
            .filter(|s: &String| !s.is_empty() && s != "null");

        Self {
            protocol_version: PROTOCOL_VERSION,
            message_type,
            message_id,
            group_id: group_id.to_string(),
            sender_device_id: sender_device_id.to_string(),
            target_device_id: target_device_id.map(|s| s.to_string()),
            session_id: session_id.map(|s| s.to_string()),
            sequence: 0,
            timestamp: now,
            expires_at,
            payload: payload_str,
            signature: String::new(),
            is_fragmented: false,
            fragment_index: 0,
            fragment_total: 0,
        }
    }

    pub fn with_signature(mut self, signature: &str) -> Self {
        self.signature = signature.to_string();
        self
    }

    pub fn with_sequence(mut self, seq: u64) -> Self {
        self.sequence = seq;
        self
    }

    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(self)
    }

    pub fn from_json(json: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(json)
    }

    pub fn is_expired(&self) -> bool {
        chrono::Utc::now().timestamp() > self.expires_at
    }

    pub fn get_payload<T: DeserializeOwned>(&self) -> Result<Option<T>, serde_json::Error> {
        match &self.payload {
            Some(p) => Ok(serde_json::from_str(p)?),
            None => Ok(None),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_roundtrip() {
        let msg = SignalingMessage::new(
            MessageType::DeviceOnline,
            "group-123",
            "device-abc",
            None,
            None,
            Some(HeartbeatPayload {
                status: DeviceStatus::Online,
                network_version: 1,
                extra: None,
            }),
        );
        let json = msg.to_json().unwrap();
        let msg2 = SignalingMessage::from_json(&json).unwrap();
        assert_eq!(msg2.message_type, MessageType::DeviceOnline);
        assert_eq!(msg2.group_id, "group-123");
        assert!(!msg2.is_expired());
    }

    #[test]
    fn test_message_type_serialization() {
        let mt = MessageType::SdpOffer;
        let json = serde_json::to_string(&mt).unwrap();
        assert_eq!(json, "\"SDP_OFFER\"");
    }

    #[test]
    fn test_expiry() {
        let mut msg = SignalingMessage::new(
            MessageType::Disconnect,
            "g", "d", None, None, None::<serde_json::Value>,
        );
        msg.expires_at = 0;
        assert!(msg.is_expired());
    }
}
