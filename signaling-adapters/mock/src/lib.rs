//! Mock 信令适配器：用于本地开发和单元测试，无需真实 QQ 机器人。

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use rl_protocol::SignalingMessage;
use rl_signaling::{AdapterType, ReceivedMessage, SignalingCapabilities, SignalingConfig, SignalingError, SignalingProvider};

/// 内存中的消息总线（模拟 QQ 群消息）
pub struct MockBus {
    messages: Arc<Mutex<VecDeque<ReceivedMessage>>>,
}

impl MockBus {
    pub fn new() -> Self {
        Self {
            messages: Arc::new(Mutex::new(VecDeque::new())),
        }
    }

    pub fn push(&self, msg: ReceivedMessage) {
        self.messages.lock().unwrap().push_back(msg);
    }

    pub fn pop(&self) -> Option<ReceivedMessage> {
        self.messages.lock().unwrap().pop_front()
    }

    pub fn len(&self) -> usize {
        self.messages.lock().unwrap().len()
    }
}

impl Default for MockBus {
    fn default() -> Self {
        Self::new()
    }
}

pub struct MockSignaling {
    bus: MockBus,
    connected: bool,
    config: Option<SignalingConfig>,
    capabilities: SignalingCapabilities,
}

impl MockSignaling {
    pub fn new() -> Self {
        Self {
            bus: MockBus::new(),
            connected: false,
            config: None,
            capabilities: SignalingCapabilities {
                supports_device_discovery: true,
                supports_multi_client: true,
                max_message_size: 4096,
                rate_limit_per_min: Some(60),
                requires_public_endpoint: false,
                description: "Mock 适配器 (本地开发/测试)".into(),
            },
        }
    }

    pub fn with_bus(bus: MockBus) -> Self {
        Self {
            bus,
            connected: false,
            config: None,
            capabilities: SignalingCapabilities {
                supports_device_discovery: true,
                supports_multi_client: true,
                max_message_size: 4096,
                rate_limit_per_min: Some(60),
                requires_public_endpoint: false,
                description: "Mock 适配器 (本地开发/测试)".into(),
            },
        }
    }

    pub fn bus(&self) -> &MockBus {
        &self.bus
    }

    pub fn is_connected(&self) -> bool {
        self.connected
    }
}

impl Default for MockSignaling {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl SignalingProvider for MockSignaling {
    async fn connect(&mut self, config: &SignalingConfig) -> Result<SignalingCapabilities, SignalingError> {
        if config.adapter_type != AdapterType::Mock {
            return Err(SignalingError::Adapter("Mock 适配器仅接受 Mock 类型配置".into()));
        }
        self.connected = true;
        self.config = Some(config.clone());
        Ok(self.capabilities.clone())
    }

    async fn disconnect(&mut self) {
        self.connected = false;
        self.config = None;
    }

    async fn publish(&self, msg: &SignalingMessage) -> Result<(), SignalingError> {
        if !self.connected {
            return Err(SignalingError::NotConnected);
        }
        let json = msg.to_json().map_err(|e| SignalingError::SendFailed(e.to_string()))?;
        self.bus.push(ReceivedMessage {
            message: msg.clone(),
            raw: json,
        });
        Ok(())
    }

    async fn receive(&mut self) -> Result<ReceivedMessage, SignalingError> {
        if !self.connected {
            return Err(SignalingError::NotConnected);
        }
        // 非阻塞：返回下一条或超时
        match self.bus.pop() {
            Some(msg) => Ok(msg),
            None => {
                tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                Err(SignalingError::Receive("无消息 (Mock)".into()))
            }
        }
    }

    fn get_capabilities(&self) -> &SignalingCapabilities {
        &self.capabilities
    }

    async fn request_device_discovery(&self, group_id: &str) -> Result<(), SignalingError> {
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::DeviceDiscover,
            group_id,
            "mock-sender",
            None,
            None,
            Some(rl_protocol::DiscoverPayload { group_id: group_id.into() }),
        );
        self.publish(&msg).await
    }

    async fn send_connection_request(&self, target: &str, session: &str, payload: &str) -> Result<(), SignalingError> {
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::ConnectRequest,
            &self.config.as_ref().map(|c| c.app_id.clone()).unwrap_or_default(),
            "mock-sender",
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
            "mock-sender",
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
            "mock-sender",
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
            "mock-sender",
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
            "mock-sender",
            Some(target),
            Some(session),
            Some(rl_protocol::IceCandidatesPayload { candidates }),
        );
        self.publish(&msg).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_publish_receive() {
        let mut mock = MockSignaling::new();
        let config = SignalingConfig {
            adapter_type: AdapterType::Mock,
            app_id: "grp-test".into(),
            api_key: "key".into(),
            extra: serde_json::json!({}),
        };
        let caps = mock.connect(&config).await.unwrap();
        assert!(caps.supports_device_discovery);
        assert!(mock.is_connected());

        let msg = SignalingMessage::new(
            rl_protocol::MessageType::DeviceOnline,
            "grp-test",
            "dev-1",
            None,
            None,
            None::<serde_json::Value>,
        );
        mock.publish(&msg).await.unwrap();

        let received = mock.receive().await.unwrap();
        assert_eq!(received.message.message_type, rl_protocol::MessageType::DeviceOnline);
        assert_eq!(received.message.sender_device_id, "dev-1");

        mock.disconnect().await;
        assert!(!mock.is_connected());
    }

    #[tokio::test]
    async fn test_mock_capabilities() {
        let mock = MockSignaling::new();
        let caps = mock.get_capabilities();
        assert!(caps.supports_multi_client);
        assert!(!caps.requires_public_endpoint);
        assert_eq!(caps.rate_limit_per_min, Some(60));
    }
}
