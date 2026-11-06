//! 设备发现与状态同步模块。

use chrono::Utc;
use rl_protocol::{DeviceInfo, DeviceStatus};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use serde::Serialize;

/// 设备状态缓存
pub struct DeviceStateCache {
    devices: Arc<RwLock<HashMap<String, DeviceState>>>,
}

#[derive(Debug, Clone, Serialize)]
pub struct DeviceState {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub group_id: String,
    pub status: DeviceStatus,
    pub last_seen: i64,
    pub network_version: u64,
    pub capabilities: Option<String>,
}

/// 状态有效期（秒）
const STATE_TTL_SECS: i64 = 120;

impl DeviceStateCache {
    pub fn new() -> Self {
        Self {
            devices: Arc::new(RwLock::new(HashMap::new())),
        }
    }

    pub fn update(&self, state: DeviceState) {
        let mut devices = self.devices.write().unwrap();
        devices.insert(state.device_id.clone(), state);
    }

    pub fn get(&self, device_id: &str) -> Option<DeviceState> {
        self.devices.read().unwrap().get(device_id).cloned()
    }

    pub fn get_by_group(&self, group_id: &str) -> Vec<DeviceState> {
        self.devices
            .read()
            .unwrap()
            .values()
            .filter(|d| d.group_id == group_id)
            .cloned()
            .collect()
    }

    /// 标记过期设备为 Stale
    pub fn mark_stale(&self) {
        let now = Utc::now().timestamp();
        let mut devices = self.devices.write().unwrap();
        for state in devices.values_mut() {
            if state.status == DeviceStatus::Online && now - state.last_seen > STATE_TTL_SECS {
                state.status = DeviceStatus::Stale;
            }
            if state.status == DeviceStatus::Stale && now - state.last_seen > STATE_TTL_SECS * 3 {
                state.status = DeviceStatus::Offline;
            }
        }
    }

    pub fn remove(&self, device_id: &str) {
        self.devices.write().unwrap().remove(device_id);
    }

    pub fn len(&self) -> usize {
        self.devices.read().unwrap().len()
    }

    pub fn is_empty(&self) -> bool {
        self.devices.read().unwrap().is_empty()
    }
}

impl Default for DeviceStateCache {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_state(id: &str) -> DeviceState {
        DeviceState {
            device_id: id.into(),
            device_name: format!("Device {}", id),
            platform: "windows".into(),
            group_id: "grp-1".into(),
            status: DeviceStatus::Online,
            last_seen: Utc::now().timestamp(),
            network_version: 1,
            capabilities: None,
        }
    }

    #[test]
    fn test_cache_update_and_get() {
        let cache = DeviceStateCache::new();
        let state = test_state("dev-1");
        cache.update(state.clone());
        assert_eq!(cache.len(), 1);
        let retrieved = cache.get("dev-1").unwrap();
        assert_eq!(retrieved.device_name, "Device dev-1");
        assert_eq!(retrieved.status, DeviceStatus::Online);
    }

    #[test]
    fn test_group_filtering() {
        let cache = DeviceStateCache::new();
        cache.update(test_state("dev-1"));
        cache.update(test_state("dev-2"));
        let devices = cache.get_by_group("grp-1");
        assert_eq!(devices.len(), 2);
        let empty = cache.get_by_group("grp-2");
        assert!(empty.is_empty());
    }

    #[test]
    fn test_stale_marking() {
        let cache = DeviceStateCache::new();
        let mut state = test_state("dev-1");
        state.last_seen = Utc::now().timestamp() - STATE_TTL_SECS - 10;
        cache.update(state);
        cache.mark_stale();
        let s = cache.get("dev-1").unwrap();
        assert_eq!(s.status, DeviceStatus::Stale);
    }
}
