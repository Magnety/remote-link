//! WebRTC P2P 连接管理：状态机、ICE/STUN/TURN 配置、会话生命周期。

use chrono::Utc;
use serde::{Serialize, Deserialize};
use rl_protocol::{ConnectMode, ConnectionState};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};

#[derive(Debug, thiserror::Error)]
pub enum ConnectionError {
    #[error("连接超时")]
    Timeout,
    #[error("ICE 收集失败")]
    IceFailed,
    #[error("会话不存在: {0}")]
    SessionNotFound(String),
    #[error("连接状态错误: {0}")]
    StateError(String),
}

/// ICE/STUN/TURN 配置
#[derive(Debug, Clone, Serialize)]
pub struct IceConfig {
    pub stun_servers: Vec<String>,
    pub turn_servers: Vec<TurnServer>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TurnServer {
    pub url: String,
    pub username: String,
    pub password: String,
}

impl Default for IceConfig {
    fn default() -> Self {
        Self {
            stun_servers: vec![
                "stun:stun.l.google.com:19302".into(),
                "stun:stun1.l.google.com:19302".into(),
            ],
            turn_servers: vec![],
        }
    }
}

/// 会话信息
#[derive(Debug, Clone, Serialize)]
pub struct SessionInfo {
    pub session_id: String,
    pub device_id: String,
    pub device_name: String,
    pub state: ConnectionState,
    pub mode: ConnectMode,
    pub started_at: i64,
    pub ice_config: IceConfig,
    pub latency_ms: Option<i32>,
}

/// 连接管理器
pub struct ConnectionManager {
    sessions: Arc<RwLock<HashMap<String, SessionInfo>>>,
    ice_config: IceConfig,
}

impl ConnectionManager {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(RwLock::new(HashMap::new())),
            ice_config: IceConfig::default(),
        }
    }

    pub fn set_ice_config(&mut self, config: IceConfig) {
        self.ice_config = config;
    }

    pub fn create_session(
        &self,
        device_id: &str,
        device_name: &str,
        mode: ConnectMode,
    ) -> SessionInfo {
        let session = SessionInfo {
            session_id: uuid::Uuid::new_v4().to_string(),
            device_id: device_id.to_string(),
            device_name: device_name.to_string(),
            state: ConnectionState::Idle,
            mode,
            started_at: Utc::now().timestamp(),
            ice_config: self.ice_config.clone(),
            latency_ms: None,
        };
        let mut sessions = self.sessions.write().unwrap();
        sessions.insert(session.session_id.clone(), session.clone());
        session
    }

    pub fn update_state(&self, session_id: &str, state: ConnectionState) -> Result<(), ConnectionError> {
        let mut sessions = self.sessions.write().unwrap();
        let session = sessions.get_mut(session_id)
            .ok_or_else(|| ConnectionError::SessionNotFound(session_id.into()))?;
        session.state = state;
        Ok(())
    }

    pub fn update_latency(&self, session_id: &str, latency_ms: i32) {
        if let Some(session) = self.sessions.write().unwrap().get_mut(session_id) {
            session.latency_ms = Some(latency_ms);
        }
    }

    pub fn get_session(&self, session_id: &str) -> Option<SessionInfo> {
        self.sessions.read().unwrap().get(session_id).cloned()
    }

    pub fn get_active_sessions(&self) -> Vec<SessionInfo> {
        self.sessions
            .read()
            .unwrap()
            .values()
            .filter(|s| s.state == ConnectionState::Connected || s.state == ConnectionState::Reconnecting)
            .cloned()
            .collect()
    }

    pub fn remove_session(&self, session_id: &str) {
        self.sessions.write().unwrap().remove(session_id);
    }

    pub fn session_count(&self) -> usize {
        self.sessions.read().unwrap().len()
    }
}

impl Default for ConnectionManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_lifecycle() {
        let mut cm = ConnectionManager::new();
        let session = cm.create_session("dev-1", "Test PC", ConnectMode::FullControl);
        assert_eq!(session.state, ConnectionState::Idle);
        assert_eq!(cm.session_count(), 1);

        cm.update_state(&session.session_id, ConnectionState::Requesting).unwrap();
        cm.update_state(&session.session_id, ConnectionState::Negotiating).unwrap();
        cm.update_state(&session.session_id, ConnectionState::Connected).unwrap();

        let s = cm.get_session(&session.session_id).unwrap();
        assert_eq!(s.state, ConnectionState::Connected);
        assert_eq!(cm.get_active_sessions().len(), 1);

        cm.remove_session(&session.session_id);
        assert_eq!(cm.session_count(), 0);
    }

    #[test]
    fn test_ice_config() {
        let config = IceConfig::default();
        assert!(!config.stun_servers.is_empty());
        assert!(config.turn_servers.is_empty());
    }
}
