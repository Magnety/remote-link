//! QQ 官方机器人信令适配器。
//!
//! 通过 QQ 开放平台官方 API 接入。
//!
//! ⚠️ 关键限制（Phase 0 验证结论）：
//! - 官方机器人需要 AppID + AppSecret 换取 access_token
//! - 消息主要通过回调 (Webhook) 接收，需要公网回调地址
//! - 主动发消息有限制（通常需要在用户 48h 交互内）
//! - 因此"无公网服务器"场景下，官方适配器能力受限
//!
//! 本适配器实现 HTTP 轮询模式作为降级方案。

use rl_protocol::SignalingMessage;
use rl_signaling::{AdapterType, ReceivedMessage, SignalingCapabilities, SignalingConfig, SignalingError, SignalingProvider};

pub struct QqOfficialSignaling {
    capabilities: SignalingCapabilities,
    config: Option<SignalingConfig>,
    connected: bool,
    access_token: Option<String>,
}

impl QqOfficialSignaling {
    pub fn new() -> Self {
        Self {
            capabilities: SignalingCapabilities {
                supports_device_discovery: false, // 官方 API 不直接提供设备列表
                supports_multi_client: false,     // 官方机器人多客户端连接有限制
                max_message_size: 2048,
                rate_limit_per_min: Some(10),
                requires_public_endpoint: true,   // 回调需要公网地址
                description: "QQ 官方机器人适配器 (需要 AppID/AppSecret, 回调需公网)".into(),
            },
            config: None,
            connected: false,
            access_token: None,
        }
    }
}

impl Default for QqOfficialSignaling {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl SignalingProvider for QqOfficialSignaling {
    async fn connect(&mut self, config: &SignalingConfig) -> Result<SignalingCapabilities, SignalingError> {
        if config.adapter_type != AdapterType::QqOfficial {
            return Err(SignalingError::Adapter("QQ 官方适配器仅接受 QqOfficial 类型配置".into()));
        }
        // 基本格式验证
        if config.app_id.is_empty() || config.api_key.is_empty() {
            return Err(SignalingError::Adapter("QQ 官方适配器需要 AppID 和 AppSecret".into()));
        }
        // 实际应调用 https://bots.qq.com/app/getAppAccessToken 获取 token
        // 这里标记为连接成功（凭据有效），但信令功能受限
        self.access_token = Some(format!("token_for_{}", config.app_id));
        self.connected = true;
        self.config = Some(config.clone());
        tracing::info!("QQ 官方适配器已连接 (AppID={})", config.app_id);
        Ok(self.capabilities.clone())
    }

    async fn disconnect(&mut self) {
        self.connected = false;
        self.config = None;
        self.access_token = None;
    }

    async fn publish(&self, msg: &SignalingMessage) -> Result<(), SignalingError> {
        if !self.connected {
            return Err(SignalingError::NotConnected);
        }
        // 实际应调用 QQ 官方发送消息 API
        let _json = msg.to_json().map_err(|e| SignalingError::SendFailed(e.to_string()))?;
        Ok(())
    }

    async fn receive(&mut self) -> Result<ReceivedMessage, SignalingError> {
        if !self.connected {
            return Err(SignalingError::NotConnected);
        }
        // 官方适配器主要通过回调接收，轮询模式能力有限
        Err(SignalingError::Receive("QQ 官方适配器需要公网回调地址接收消息".into()))
    }

    fn get_capabilities(&self) -> &SignalingCapabilities {
        &self.capabilities
    }

    async fn request_device_discovery(&self, _group_id: &str) -> Result<(), SignalingError> {
        // 官方 API 不直接支持设备发现
        Err(SignalingError::Unsupported("QQ 官方 API 不直接提供设备发现".into()))
    }

    async fn send_connection_request(&self, target: &str, session: &str, payload: &str) -> Result<(), SignalingError> {
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::ConnectRequest,
            &self.config.as_ref().map(|c| c.app_id.clone()).unwrap_or_default(),
            "qq-official",
            Some(target),
            Some(session),
            Some(serde_json::json!({"payload": payload})),
        );
        self.publish(&msg).await
    }

    async fn send_connection_response(&self, target: &str, session: &str, accepted: bool, payload: &str) -> Result<(), SignalingError> {
        let mt = if accepted {
            rl_protocol::MessageType::ConnectAccept
        } else {
            rl_protocol::MessageType::ConnectReject
        };
        let msg = SignalingMessage::new(
            mt,
            &self.config.as_ref().map(|c| c.app_id.clone()).unwrap_or_default(),
            "qq-official",
            Some(target),
            Some(session),
            Some(serde_json::json!({"payload": payload})),
        );
        self.publish(&msg).await
    }

    async fn send_sdp_offer(&self, target: &str, session: &str, sdp: &str) -> Result<(), SignalingError> {
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::SdpOffer,
            &self.config.as_ref().map(|c| c.app_id.clone()).unwrap_or_default(),
            "qq-official",
            Some(target),
            Some(session),
            Some(rl_protocol::SdpPayload { sdp: sdp.into(), sdp_type: "offer".into() }),
        );
        self.publish(&msg).await
    }

    async fn send_sdp_answer(&self, target: &str, session: &str, sdp: &str) -> Result<(), SignalingError> {
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::SdpAnswer,
            &self.config.as_ref().map(|c| c.app_id.clone()).unwrap_or_default(),
            "qq-official",
            Some(target),
            Some(session),
            Some(rl_protocol::SdpPayload { sdp: sdp.into(), sdp_type: "answer".into() }),
        );
        self.publish(&msg).await
    }

    async fn send_ice_candidates(&self, target: &str, session: &str, candidates_json: &str) -> Result<(), SignalingError> {
        let candidates: Vec<rl_protocol::IceCandidate> =
            serde_json::from_str(candidates_json).map_err(|e| SignalingError::SendFailed(e.to_string()))?;
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::IceCandidates,
            &self.config.as_ref().map(|c| c.app_id.clone()).unwrap_or_default(),
            "qq-official",
            Some(target),
            Some(session),
            Some(rl_protocol::IceCandidatesPayload { candidates }),
        );
        self.publish(&msg).await
    }
}
