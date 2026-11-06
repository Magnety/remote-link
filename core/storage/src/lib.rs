//! SQLite 本地存储：设备缓存、设置、会话记录。

use rusqlite::{Connection, params};
use std::path::Path;
use serde::{Deserialize, Serialize};

#[derive(Debug, thiserror::Error)]
pub enum StorageError {
    #[error("数据库错误: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("JSON 错误: {0}")]
    Json(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredDevice {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub group_id: String,
    pub status: String,
    pub last_seen: i64,
    pub network_version: u64,
    pub ed25519_public_key: String,
    pub x25519_public_key: String,
    pub capabilities_json: String,
    pub is_trusted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct AppSettings {
    pub device_name: String,
    pub auto_start: bool,
    pub heartbeat_interval_secs: u64,
    pub video_quality: String,
    pub stun_servers: Vec<String>,
    pub turn_server: Option<String>,
    pub turn_username: Option<String>,
    pub turn_password: Option<String>,
    pub unattended_mode: bool,
    pub readonly_mode: bool,
}

pub struct Storage {
    conn: Connection,
}

impl Storage {
    pub fn open(path: &str) -> Result<Self, StorageError> {
        let conn = if path == ":memory:" {
            Connection::open_in_memory()?
        } else {
            if let Some(parent) = Path::new(path).parent() {
                std::fs::create_dir_all(parent).ok();
            }
            Connection::open(path)?
        };
        let s = Self { conn };
        s.migrate()?;
        Ok(s)
    }

    fn migrate(&self) -> Result<(), StorageError> {
        self.conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS devices (
                device_id TEXT PRIMARY KEY,
                device_name TEXT NOT NULL,
                platform TEXT NOT NULL,
                group_id TEXT NOT NULL,
                status TEXT DEFAULT 'UNKNOWN',
                last_seen INTEGER DEFAULT 0,
                network_version INTEGER DEFAULT 0,
                ed25519_public_key TEXT,
                x25519_public_key TEXT,
                capabilities_json TEXT,
                is_trusted INTEGER DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS sessions (
                session_id TEXT PRIMARY KEY,
                device_id TEXT NOT NULL,
                started_at INTEGER NOT NULL,
                ended_at INTEGER,
                status TEXT DEFAULT 'active',
                latency_ms INTEGER
            );
            CREATE INDEX IF NOT EXISTS idx_devices_group ON devices(group_id);
            CREATE INDEX IF NOT EXISTS idx_sessions_device ON sessions(device_id);"
        )?;
        Ok(())
    }

    pub fn upsert_device(&self, d: &StoredDevice) -> Result<(), StorageError> {
        self.conn.execute(
            "INSERT OR REPLACE INTO devices (device_id, device_name, platform, group_id, status, last_seen, network_version, ed25519_public_key, x25519_public_key, capabilities_json, is_trusted)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![
                d.device_id, d.device_name, d.platform, d.group_id,
                d.status, d.last_seen, d.network_version,
                d.ed25519_public_key, d.x25519_public_key,
                d.capabilities_json, d.is_trusted as i32,
            ],
        )?;
        Ok(())
    }

    pub fn get_devices_by_group(&self, group_id: &str) -> Result<Vec<StoredDevice>, StorageError> {
        let mut stmt = self.conn.prepare(
            "SELECT device_id, device_name, platform, group_id, status, last_seen, network_version,
             ed25519_public_key, x25519_public_key, capabilities_json, is_trusted
             FROM devices WHERE group_id = ?1 ORDER BY last_seen DESC"
        )?;
        let rows = stmt.query_map(params![group_id], |row| {
            Ok(StoredDevice {
                device_id: row.get(0)?,
                device_name: row.get(1)?,
                platform: row.get(2)?,
                group_id: row.get(3)?,
                status: row.get(4)?,
                last_seen: row.get(5)?,
                network_version: row.get(6)?,
                ed25519_public_key: row.get(7)?,
                x25519_public_key: row.get(8)?,
                capabilities_json: row.get(9)?,
                is_trusted: row.get::<_, i32>(10)? != 0,
            })
        })?;
        let mut devices = Vec::new();
        for row in rows {
            devices.push(row?);
        }
        Ok(devices)
    }

    pub fn delete_device(&self, device_id: &str) -> Result<(), StorageError> {
        self.conn.execute("DELETE FROM devices WHERE device_id = ?1", params![device_id])?;
        Ok(())
    }

    pub fn set_device_trusted(&self, device_id: &str, trusted: bool) -> Result<(), StorageError> {
        self.conn.execute(
            "UPDATE devices SET is_trusted = ?2 WHERE device_id = ?1",
            params![device_id, trusted as i32],
        )?;
        Ok(())
    }

    pub fn get_settings(&self) -> Result<AppSettings, StorageError> {
        let mut settings = AppSettings::default();
        let keys = ["device_name", "auto_start", "heartbeat_interval_secs", "video_quality", "unattended_mode", "readonly_mode"];
        for key in keys {
            let val: Option<String> = self.conn
                .query_row("SELECT value FROM settings WHERE key = ?1", params![key], |row| row.get(0))
                .ok();
            if let Some(v) = val {
                match key {
                    "device_name" => settings.device_name = v,
                    "auto_start" => settings.auto_start = v == "true",
                    "heartbeat_interval_secs" => settings.heartbeat_interval_secs = v.parse().unwrap_or(600),
                    "video_quality" => settings.video_quality = v,
                    "unattended_mode" => settings.unattended_mode = v == "true",
                    "readonly_mode" => settings.readonly_mode = v == "true",
                    _ => {}
                }
            }
        }
        Ok(settings)
    }

    pub fn save_settings(&self, s: &AppSettings) -> Result<(), StorageError> {
        let pairs = [
            ("device_name", s.device_name.clone()),
            ("auto_start", s.auto_start.to_string()),
            ("heartbeat_interval_secs", s.heartbeat_interval_secs.to_string()),
            ("video_quality", s.video_quality.clone()),
            ("unattended_mode", s.unattended_mode.to_string()),
            ("readonly_mode", s.readonly_mode.to_string()),
        ];
        for (k, v) in pairs {
            self.conn.execute(
                "INSERT OR REPLACE INTO settings (key, value) VALUES (?1, ?2)",
                params![k, v],
            )?;
        }
        Ok(())
    }

    pub fn record_session(
        &self,
        session_id: &str,
        device_id: &str,
        started_at: i64,
        ended_at: Option<i64>,
        status: &str,
        latency_ms: Option<i32>,
    ) -> Result<(), StorageError> {
        self.conn.execute(
            "INSERT OR REPLACE INTO sessions (session_id, device_id, started_at, ended_at, status, latency_ms)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![session_id, device_id, started_at, ended_at, status, latency_ms],
        )?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_device_roundtrip() {
        let s = Storage::open(":memory:").unwrap();
        let d = StoredDevice {
            device_id: "dev-1".into(),
            device_name: "Test PC".into(),
            platform: "windows".into(),
            group_id: "grp-1".into(),
            status: "ONLINE".into(),
            last_seen: 1000,
            network_version: 1,
            ed25519_public_key: "abc".into(),
            x25519_public_key: "def".into(),
            capabilities_json: "{}".into(),
            is_trusted: true,
        };
        s.upsert_device(&d).unwrap();
        let devices = s.get_devices_by_group("grp-1").unwrap();
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].device_name, "Test PC");
    }

    #[test]
    fn test_settings_roundtrip() {
        let s = Storage::open(":memory:").unwrap();
        let mut settings = AppSettings::default();
        settings.device_name = "My PC".into();
        settings.heartbeat_interval_secs = 300;
        settings.unattended_mode = true;
        s.save_settings(&settings).unwrap();
        let loaded = s.get_settings().unwrap();
        assert_eq!(loaded.device_name, "My PC");
        assert_eq!(loaded.heartbeat_interval_secs, 300);
        assert!(loaded.unattended_mode);
    }
}
