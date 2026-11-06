//! OneBot (NapCat / go-cqhttp) 信令适配器。
//!
//! 通过 WebSocket 连接到 OneBot v11 实现（NapCat 等）。
//! 这是非官方接入方式，使用真实 QQ 账号，需注意账号风险。
//!
//! 连接方式：
//! - app_id 字段存 WebSocket 地址 (ws://host:port)
//! - api_key 字段存 Access Token
//! - extra.group_id 存 QQ 群号
//!
//! 消息协议：通过 QQ 群消息收发 RemoteLink JSON 信令。

use std::sync::Arc;
use tokio::sync::{Mutex, mpsc};
use futures_util::{SinkExt, StreamExt};
use tokio_tungstenite::tungstenite::Message as WsMessage;
use rl_protocol::SignalingMessage;
use rl_signaling::{AdapterType, ReceivedMessage, SignalingCapabilities, SignalingConfig, SignalingError, SignalingProvider};

/// OneBot v11 消息结构
#[derive(Debug, serde::Serialize, serde::Deserialize)]
struct OneBotMessage {
    post_type: String,
    #[serde(default)]
    message_type: String,
    #[serde(default)]
    group_id: i64,
    #[serde(default)]
    message_id: i64,
    #[serde(default)]
    raw_message: String,
    #[serde(default)]
    message: Vec<OneBotSegment>,
    #[serde(default)]
    self_id: i64,
}

#[derive(Debug, serde::Serialize, serde::Deserialize, Default)]
struct OneBotSegment {
    #[serde(rename = "type")]
    seg_type: String,
    data: serde_json::Value,
}

pub struct OneBotSignaling {
    capabilities: SignalingCapabilities,
    config: Option<SignalingConfig>,
    group_id: i64,
    outgoing: Option<mpsc::Sender<String>>,
    connected: bool,
    // 接收通道
    incoming_rx: Option<mpsc::Receiver<String>>,
}

impl OneBotSignaling {
    pub fn new() -> Self {
        Self {
            capabilities: SignalingCapabilities {
                supports_device_discovery: false, // OneBot 不直接提供设备发现，需应用层实现
                supports_multi_client: true,
                max_message_size: 2048,
                rate_limit_per_min: Some(20),
                requires_public_endpoint: true, // 通常需要 NapCat 常驻公网
                description: "OneBot 适配器 (NapCat/go-cqhttp, 非官方 QQ 接入)".into(),
            },
            config: None,
            group_id: 0,
            outgoing: None,
            connected: false,
            incoming_rx: None,
        }
    }

    fn parse_onebot(&self, raw: &str) -> Option<ReceivedMessage> {
        let msg: OneBotMessage = serde_json::from_str(raw).ok()?;
        if msg.post_type != "message" {
            return None;
        }
        // 只处理群消息
        if msg.message_type != "group" && msg.group_id != self.group_id {
            return None;
        }
        // 提取文本
        let text = msg.message.iter().find_map(|seg| {
            if seg.seg_type == "text" {
                seg.data.get("text").and_then(|t| t.as_str()).map(|s| s.to_string())
            } else {
                None
            }
        })?;
        // 尝试解析 RemoteLink 信令
        let signaling = SignalingMessage::from_json(&text).ok()?;
        Some(ReceivedMessage {
            message: signaling,
            raw: raw.to_string(),
        })
    }
}

impl Default for OneBotSignaling {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait::async_trait]
impl SignalingProvider for OneBotSignaling {
    async fn connect(&mut self, config: &SignalingConfig) -> Result<SignalingCapabilities, SignalingError> {
        if config.adapter_type != AdapterType::OneBot {
            return Err(SignalingError::Adapter("OneBot 适配器仅接受 OneBot 类型配置".into()));
        }
        let ws_url = config.app_id.clone();
        let token = config.api_key.clone();
        self.group_id = config.extra.get("group_id")
            .and_then(|v| v.as_i64())
            .unwrap_or(0);

        // 建立 WebSocket 连接
        let (mut ws_stream, _response) = tokio_tungstenite::connect_async(&ws_url)
            .await
            .map_err(|e| SignalingError::Connection(format!("WebSocket 连接失败: {}", e)))?;

        // 拆分：sink (发送) 和 stream (接收)
        let (mut ws_sink, mut ws_stream) = ws_stream.split();

        // 创建发送通道
        let (outgoing_tx, mut outgoing_rx) = mpsc::channel::<String>(64);
        let (incoming_tx, incoming_rx) = mpsc::channel::<String>(256);

        // 发送任务
        let _send_handle = tokio::spawn(async move {
            // 发送 meta_event 认证
            let meta = serde_json::json!({
                "post_type": "meta_event",
                "meta_event_type": "lifecycle",
                "status": "connected"
            });
            if let Err(e) = ws_sink.send(WsMessage::Text(meta.to_string())).await {
                tracing::error!("OneBot 发送失败: {}", e);
            }
            while let Some(msg) = outgoing_rx.recv().await {
                if let Err(e) = ws_sink.send(WsMessage::Text(msg)).await {
                    tracing::error!("OneBot 发送失败: {}", e);
                    break;
                }
            }
        });

        // 接收任务
        tokio::spawn(async move {
            while let Some(Ok(item)) = ws_stream.next().await {
                if let WsMessage::Text(text) = item {
                    if incoming_tx.send(text).await.is_err() {
                        break;
                    }
                }
            }
        });

        self.outgoing = Some(outgoing_tx);
        self.incoming_rx = Some(incoming_rx);
        self.connected = true;
        self.config = Some(config.clone());

        tracing::info!("OneBot 已连接到 {}", ws_url);
        Ok(self.capabilities.clone())
    }

    async fn disconnect(&mut self) {
        self.connected = false;
        self.config = None;
        self.outgoing = None;
        self.incoming_rx = None;
    }

    async fn publish(&self, msg: &SignalingMessage) -> Result<(), SignalingError> {
        let tx = self.outgoing.as_ref()
            .ok_or(SignalingError::NotConnected)?;
        let json = msg.to_json().map_err(|e| SignalingError::SendFailed(e.to_string()))?;
        // 包装为 OneBot 群消息
        let ob = serde_json::json!({
            "action": "send_group_msg",
            "group_id": self.group_id,
            "message": [
                { "type": "text", "data": { "text": format!("[RL]{}", json) } }
            ]
        });
        tx.send(ob.to_string())
            .await
            .map_err(|_| SignalingError::SendFailed("发送通道关闭".into()))?;
        Ok(())
    }

    async fn receive(&mut self) -> Result<ReceivedMessage, SignalingError> {
        let rx = self.incoming_rx.as_mut()
            .ok_or(SignalingError::NotConnected)?;
        match rx.recv().await {
            Some(raw) => {
                // 去除 [RL] 前缀
                let cleaned = raw.trim();
                if let Some(parsed) = self.parse_onebot(cleaned) {
                    Ok(parsed)
                } else {
                    // 尝试直接解析（可能已去前缀）
                    let stripped = cleaned.strip_prefix("[RL]").unwrap_or(cleaned);
                    match SignalingMessage::from_json(stripped) {
                        Ok(msg) => Ok(ReceivedMessage { message: msg, raw: cleaned.to_string() }),
                        Err(_) => Err(SignalingError::Receive("非 RemoteLink 消息".into())),
                    }
                }
            }
            None => Err(SignalingError::Receive("接收通道关闭".into())),
        }
    }

    fn get_capabilities(&self) -> &SignalingCapabilities {
        &self.capabilities
    }

    async fn request_device_discovery(&self, group_id: &str) -> Result<(), SignalingError> {
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::DeviceDiscover,
            group_id,
            "onebot-sender",
            None,
            None,
            Some(rl_protocol::DiscoverPayload { group_id: group_id.into() }),
        );
        self.publish(&msg).await
    }

    async fn send_connection_request(&self, target: &str, session: &str, payload: &str) -> Result<(), SignalingError> {
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::ConnectRequest,
            &self.config.as_ref().map(|c| c.extra.get("group_id").and_then(|v| v.as_i64()).unwrap_or(0).to_string()).unwrap_or_default(),
            "onebot-sender",
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
            &self.config.as_ref().map(|c| c.extra.get("group_id").and_then(|v| v.as_i64()).unwrap_or(0).to_string()).unwrap_or_default(),
            "onebot-sender",
            Some(target),
            Some(session),
            Some(serde_json::json!({"payload": payload})),
        );
        self.publish(&msg).await
    }

    async fn send_sdp_offer(&self, target: &str, session: &str, sdp: &str) -> Result<(), SignalingError> {
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::SdpOffer,
            &self.config.as_ref().map(|c| c.extra.get("group_id").and_then(|v| v.as_i64()).unwrap_or(0).to_string()).unwrap_or_default(),
            "onebot-sender",
            Some(target),
            Some(session),
            Some(rl_protocol::SdpPayload { sdp: sdp.into(), sdp_type: "offer".into() }),
        );
        self.publish(&msg).await
    }

    async fn send_sdp_answer(&self, target: &str, session: &str, sdp: &str) -> Result<(), SignalingError> {
        let msg = SignalingMessage::new(
            rl_protocol::MessageType::SdpAnswer,
            &self.config.as_ref().map(|c| c.extra.get("group_id").and_then(|v| v.as_i64()).unwrap_or(0).to_string()).unwrap_or_default(),
            "onebot-sender",
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
            &self.config.as_ref().map(|c| c.extra.get("group_id").and_then(|v| v.as_i64()).unwrap_or(0).to_string()).unwrap_or_default(),
            "onebot-sender",
            Some(target),
            Some(session),
            Some(rl_protocol::IceCandidatesPayload { candidates }),
        );
        self.publish(&msg).await
    }
}