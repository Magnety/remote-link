//! RemoteLink Rust 核心 FFI 层。
//!
//! 为 Dart (dart:ffi / flutter_rust_bridge) 提供 C ABI 接口。
//! 返回字符串的函数返回 *mut c_char (CString)，调用方用 rl_string_free 释放。

use std::sync::{Mutex, LazyLock};
use std::ffi::CString;
use std::os::raw::{c_char, c_int};

use rl_identity::{create_device_identity, KeyPair, Platform};
use rl_security::{E2eCipher, ReplayProtector};
use rl_storage::{Storage, AppSettings, StoredDevice};
use rl_connection::{ConnectionManager, IceConfig, TurnServer};
use rl_discovery::DeviceStateCache;

/// 全局状态
static KEYPAIR: LazyLock<Mutex<Option<KeyPair>>> = LazyLock::new(|| Mutex::new(None));
static STORAGE: LazyLock<Mutex<Option<Storage>>> = LazyLock::new(|| Mutex::new(None));
static CONNECTIONS: LazyLock<Mutex<ConnectionManager>> = LazyLock::new(|| Mutex::new(ConnectionManager::new()));
static DEVICE_CACHE: LazyLock<Mutex<DeviceStateCache>> = LazyLock::new(|| Mutex::new(DeviceStateCache::new()));
static REPLAY: LazyLock<Mutex<ReplayProtector>> = LazyLock::new(|| Mutex::new(ReplayProtector::default()));

/// 从 C 字符串指针提取 Rust String (owned)
unsafe fn cstr_to_string(s: *const c_char) -> String {
    if s.is_null() {
        return String::new();
    }
    let mut len = 0usize;
    while *s.add(len) != 0 {
        len += 1;
    }
    let bytes = std::slice::from_raw_parts(s as *const u8, len);
    String::from_utf8_lossy(bytes).into_owned()
}

/// 将 Rust String 转为 CString 指针
fn str_to_cptr(s: &str) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

/// 释放字符串
#[no_mangle]
pub extern "C" fn rl_string_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// 初始化核心（日志 + 存储）
#[no_mangle]
pub extern "C" fn rl_init(db_path: *const c_char) -> c_int {
    let _ = tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .try_init();

    let path = unsafe { cstr_to_string(db_path) };
    let path = if path.is_empty() { String::from(":memory:") } else { path };
    match Storage::open(&path) {
        Ok(s) => {
            *STORAGE.lock().unwrap() = Some(s);
            0
        }
        Err(e) => {
            tracing::error!("存储初始化失败: {}", e);
            -1
        }
    }
}

/// 生成设备身份，返回 JSON 字符串
#[no_mangle]
pub extern "C" fn rl_create_identity(
    device_name: *const c_char,
    platform_str: *const c_char,
) -> *mut c_char {
    let name = unsafe { cstr_to_string(device_name) };
    let platform_in = unsafe { cstr_to_string(platform_str) };
    let name = if name.is_empty() { "Unknown".to_string() } else { name };
    let platform = match platform_in.as_str() {
        "windows" => Platform::Windows,
        "macos" => Platform::MacOS,
        "android" => Platform::Android,
        _ => Platform::Linux,
    };

    match create_device_identity(&name, platform) {
        Ok((identity, kp)) => {
            let ed_priv = kp.ed25519_private_hex();
            let x_priv = kp.x25519_private_hex();
            let ed_pub = kp.ed25519_public_hex.clone();
            let x_pub = kp.x25519_public_hex.clone();
            *KEYPAIR.lock().unwrap() = Some(kp);
            let json = serde_json::json!({
                "identity": identity,
                "ed25519_private": ed_priv,
                "x25519_private": x_priv,
                "ed25519_public": ed_pub,
                "x25519_public": x_pub,
            });
            str_to_cptr(&json.to_string())
        }
        Err(e) => {
            tracing::error!("身份创建失败: {}", e);
            str_to_cptr("null")
        }
    }
}

/// 恢复设备身份
#[no_mangle]
pub extern "C" fn rl_restore_identity(
    ed25519_private: *const c_char,
    x25519_private: *const c_char,
) -> *mut c_char {
    let ed = unsafe { cstr_to_string(ed25519_private) };
    let x = unsafe { cstr_to_string(x25519_private) };
    match KeyPair::restore(&ed, &x) {
        Ok(kp) => {
            let ed_pub = kp.ed25519_public_hex.clone();
            let x_pub = kp.x25519_public_hex.clone();
            *KEYPAIR.lock().unwrap() = Some(kp);
            str_to_cptr(&format!(
                "{{\"ed25519_public\":\"{}\",\"x25519_public\":\"{}\"}}",
                ed_pub, x_pub
            ))
        }
        Err(e) => {
            tracing::error!("身份恢复失败: {}", e);
            str_to_cptr("null")
        }
    }
}

/// 签名消息
#[no_mangle]
pub extern "C" fn rl_sign(message: *const c_char) -> *mut c_char {
    let msg = unsafe { cstr_to_string(message) };
    let guard = KEYPAIR.lock().unwrap();
    match guard.as_ref() {
        Some(kp) => str_to_cptr(&kp.sign(msg.as_bytes())),
        None => str_to_cptr(""),
    }
}

/// 验证签名
#[no_mangle]
pub extern "C" fn rl_verify(message: *const c_char, signature: *const c_char) -> c_int {
    let msg = unsafe { cstr_to_string(message) };
    let sig = unsafe { cstr_to_string(signature) };
    let guard = KEYPAIR.lock().unwrap();
    match guard.as_ref() {
        Some(kp) => if kp.verify(msg.as_bytes(), &sig) { 1 } else { 0 },
        None => 0,
    }
}

/// 获取公钥
#[no_mangle]
pub extern "C" fn rl_get_public_keys() -> *mut c_char {
    let guard = KEYPAIR.lock().unwrap();
    match guard.as_ref() {
        Some(kp) => str_to_cptr(&format!(
            "{{\"ed25519\":\"{}\",\"x25519\":\"{}\"}}",
            kp.ed25519_public_hex, kp.x25519_public_hex
        )),
        None => str_to_cptr("null"),
    }
}

/// 保存设备
#[no_mangle]
pub extern "C" fn rl_save_device(json: *const c_char) -> c_int {
    let device_json = unsafe { cstr_to_string(json) };
    let guard = STORAGE.lock().unwrap();
    let storage = match guard.as_ref() {
        Some(s) => s,
        None => return -1,
    };
    match serde_json::from_str::<StoredDevice>(&device_json) {
        Ok(d) => if storage.upsert_device(&d).is_ok() { 0 } else { -1 },
        Err(e) => {
            tracing::error!("设备 JSON 解析失败: {}", e);
            -1
        }
    }
}

/// 获取组内设备列表
#[no_mangle]
pub extern "C" fn rl_get_devices(group_id: *const c_char) -> *mut c_char {
    let group = unsafe { cstr_to_string(group_id) };
    let guard = STORAGE.lock().unwrap();
    let storage = match guard.as_ref() {
        Some(s) => s,
        None => return str_to_cptr("[]"),
    };
    match storage.get_devices_by_group(&group) {
        Ok(devices) => {
            let json = serde_json::to_string(&devices).unwrap_or_else(|_| "[]".into());
            str_to_cptr(&json)
        }
        Err(_) => str_to_cptr("[]"),
    }
}

/// 删除设备
#[no_mangle]
pub extern "C" fn rl_delete_device(device_id: *const c_char) -> c_int {
    let id = unsafe { cstr_to_string(device_id) };
    let guard = STORAGE.lock().unwrap();
    match guard.as_ref() {
        Some(s) => if s.delete_device(&id).is_ok() { 0 } else { -1 },
        None => -1,
    }
}

/// 保存设置
#[no_mangle]
pub extern "C" fn rl_save_settings(json: *const c_char) -> c_int {
    let settings_json = unsafe { cstr_to_string(json) };
    let guard = STORAGE.lock().unwrap();
    let storage = match guard.as_ref() {
        Some(s) => s,
        None => return -1,
    };
    match serde_json::from_str::<AppSettings>(&settings_json) {
        Ok(settings) => if storage.save_settings(&settings).is_ok() { 0 } else { -1 },
        Err(e) => {
            tracing::error!("设置 JSON 解析失败: {}", e);
            -1
        }
    }
}

/// 获取设置
#[no_mangle]
pub extern "C" fn rl_get_settings() -> *mut c_char {
    let guard = STORAGE.lock().unwrap();
    match guard.as_ref() {
        Some(s) => match s.get_settings() {
            Ok(settings) => {
                let json = serde_json::to_string(&settings).unwrap_or_else(|_| "{}".into());
                str_to_cptr(&json)
            }
            Err(_) => str_to_cptr("{}"),
        },
        None => str_to_cptr("{}"),
    }
}

/// E2E 加密
#[no_mangle]
pub extern "C" fn rl_e2e_encrypt(key_hex: *const c_char, plaintext: *const c_char) -> *mut c_char {
    let key = unsafe { cstr_to_string(key_hex) };
    let pt = unsafe { cstr_to_string(plaintext) };
    let key_bytes = match hex::decode(&key) {
        Ok(b) => b,
        Err(_) => return str_to_cptr(""),
    };
    let mut key32 = [0u8; 32];
    let len = key_bytes.len().min(32);
    key32[..len].copy_from_slice(&key_bytes[..len]);
    match E2eCipher::new(&key32).encrypt(pt.as_bytes()) {
        Ok(enc) => str_to_cptr(&enc),
        Err(_) => str_to_cptr(""),
    }
}

/// E2E 解密
#[no_mangle]
pub extern "C" fn rl_e2e_decrypt(key_hex: *const c_char, encoded: *const c_char) -> *mut c_char {
    let key = unsafe { cstr_to_string(key_hex) };
    let enc = unsafe { cstr_to_string(encoded) };
    let key_bytes = match hex::decode(&key) {
        Ok(b) => b,
        Err(_) => return str_to_cptr(""),
    };
    let mut key32 = [0u8; 32];
    let len = key_bytes.len().min(32);
    key32[..len].copy_from_slice(&key_bytes[..len]);
    match E2eCipher::new(&key32).decrypt(&enc) {
        Ok(pt) => str_to_cptr(&String::from_utf8_lossy(&pt)),
        Err(_) => str_to_cptr(""),
    }
}

/// 创建连接会话
#[no_mangle]
pub extern "C" fn rl_create_session(
    device_id: *const c_char,
    device_name: *const c_char,
    mode: *const c_char,
) -> *mut c_char {
    let id = unsafe { cstr_to_string(device_id) };
    let name = unsafe { cstr_to_string(device_name) };
    let mode_in = unsafe { cstr_to_string(mode) };
    let mode = match mode_in.as_str() {
        "readonly" => rl_protocol::ConnectMode::ReadOnly,
        _ => rl_protocol::ConnectMode::FullControl,
    };
    let session = CONNECTIONS.lock().unwrap().create_session(&id, &name, mode);
    let sid = session.session_id.clone();
    str_to_cptr(&sid)
}

/// 更新会话状态
#[no_mangle]
pub extern "C" fn rl_update_session_state(session_id: *const c_char, state_str: *const c_char) -> c_int {
    let sid = unsafe { cstr_to_string(session_id) };
    let state_in = unsafe { cstr_to_string(state_str) };
    let state = match state_in.as_str() {
        "IDLE" => rl_protocol::ConnectionState::Idle,
        "REQUESTING" => rl_protocol::ConnectionState::Requesting,
        "AUTHORIZING" => rl_protocol::ConnectionState::Authorizing,
        "NEGOTIATING" => rl_protocol::ConnectionState::Negotiating,
        "CONNECTING" => rl_protocol::ConnectionState::Connecting,
        "CONNECTED" => rl_protocol::ConnectionState::Connected,
        "RECONNECTING" => rl_protocol::ConnectionState::Reconnecting,
        "DISCONNECTED" => rl_protocol::ConnectionState::Disconnected,
        "FAILED" => rl_protocol::ConnectionState::Failed,
        _ => return -1,
    };
    if CONNECTIONS.lock().unwrap().update_state(&sid, state).is_ok() { 0 } else { -1 }
}

/// 获取活跃会话
#[no_mangle]
pub extern "C" fn rl_get_active_sessions() -> *mut c_char {
    let sessions = CONNECTIONS.lock().unwrap().get_active_sessions();
    let json = serde_json::to_string(&sessions).unwrap_or_else(|_| "[]".into());
    str_to_cptr(&json)
}

/// 设置 ICE 配置
#[no_mangle]
pub extern "C" fn rl_set_ice_config(json: *const c_char) -> c_int {
    let cfg = unsafe { cstr_to_string(json) };
    #[derive(serde::Deserialize)]
    struct IceCfg {
        #[serde(default)]
        stun_servers: Vec<String>,
        #[serde(default)]
        turn_servers: Vec<TurnServer>,
    }
    match serde_json::from_str::<IceCfg>(&cfg) {
        Ok(c) => {
            CONNECTIONS.lock().unwrap().set_ice_config(IceConfig {
                stun_servers: c.stun_servers,
                turn_servers: c.turn_servers,
            });
            0
        }
        Err(_) => -1,
    }
}

/// 更新设备状态缓存
#[no_mangle]
pub extern "C" fn rl_update_device_cache(json: *const c_char) -> c_int {
    let state_json = unsafe { cstr_to_string(json) };
    #[derive(serde::Deserialize)]
    struct StateIn {
        device_id: String,
        device_name: String,
        platform: String,
        group_id: String,
        #[serde(default)]
        status: String,
        #[serde(default)]
        last_seen: i64,
        #[serde(default)]
        network_version: u64,
        capabilities: Option<String>,
    }
    match serde_json::from_str::<StateIn>(&state_json) {
        Ok(s) => {
            let status = match s.status.as_str() {
                "ONLINE" => rl_protocol::DeviceStatus::Online,
                "STALE" => rl_protocol::DeviceStatus::Stale,
                "OFFLINE" => rl_protocol::DeviceStatus::Offline,
                "UNKNOWN" => rl_protocol::DeviceStatus::Unknown,
                "CONNECTING" => rl_protocol::DeviceStatus::Connecting,
                "IN_SESSION" => rl_protocol::DeviceStatus::InSession,
                _ => rl_protocol::DeviceStatus::Unknown,
            };
            DEVICE_CACHE.lock().unwrap().update(rl_discovery::DeviceState {
                device_id: s.device_id,
                device_name: s.device_name,
                platform: s.platform,
                group_id: s.group_id,
                status,
                last_seen: s.last_seen,
                network_version: s.network_version,
                capabilities: s.capabilities,
            });
            0
        }
        Err(_) => -1,
    }
}

/// 获取缓存设备状态
#[no_mangle]
pub extern "C" fn rl_get_device_cache(group_id: *const c_char) -> *mut c_char {
    let group = unsafe { cstr_to_string(group_id) };
    let states = DEVICE_CACHE.lock().unwrap().get_by_group(&group);
    let json = serde_json::to_string(&states).unwrap_or_else(|_| "[]".into());
    str_to_cptr(&json)
}

/// 标记过期设备
#[no_mangle]
pub extern "C" fn rl_mark_stale_devices() {
    DEVICE_CACHE.lock().unwrap().mark_stale();
}
