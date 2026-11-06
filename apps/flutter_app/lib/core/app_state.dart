import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';
import 'rust_bridge.dart';
import 'signaling_bus.dart';

/// 应用主路由
enum AppRoute { welcome, setup, pairing, home }

/// 全局应用状态
class AppState extends ChangeNotifier {
  final bool rustAvailable;
  final RustBridge _rust;
  SharedPreferences? _prefs;

  // 路由
  AppRoute _route = AppRoute.welcome;
  AppRoute get route => _route;

  // 当前设备
  Device? _selfDevice;
  Device? get selfDevice => _selfDevice;

  // 信令配置
  SignalingConfig? _signaling;
  SignalingConfig? get signaling => _signaling;
  bool _signalingVerified = false;
  bool get signalingVerified => _signalingVerified;
  String _signalingError = '';
  String get signalingError => _signalingError;
  bool _verifying = false;
  bool get verifying => _verifying;

  // 设备列表
  final List<Device> _devices = [];
  List<Device> get devices => _devices;

  // 设置
  AppSettings _settings = AppSettings();
  AppSettings get settings => _settings;

  // 信令总线 (QQ 群互传)
  final SignalingBus _bus = SignalingBus();
  bool _busRunning = false;
  bool get busRunning => _busRunning;
  bool _busConnected = false;
  bool get busConnected => _busConnected;

  AppState({required this.rustAvailable}) : _rust = RustBridge() {
    _rust.init();
  }

  /// 启动引导
  Future<void> bootstrap() async {
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/remote_link.db';
    _rust.rlInit(dbPath);

    _prefs = await SharedPreferences.getInstance();
    await _loadPersisted();

    if (_signaling == null) {
      _setRoute(AppRoute.welcome);
    } else if (_selfDevice == null) {
      _setRoute(AppRoute.setup);
    } else {
      _setRoute(AppRoute.home);
    }
    notifyListeners();
  }

  void _setRoute(AppRoute r) {
    _route = r;
    notifyListeners();
  }

  // ---------- 持久化 ----------
  Future<void> _loadPersisted() async {
    final prefs = _prefs!;
    // 信令
    final sigJson = prefs.getString('signaling_config');
    if (sigJson != null) {
      try {
        final j = jsonDecode(sigJson) as Map<String, dynamic>;
        _signaling = SignalingConfig(
          adapterType: AdapterType.values.firstWhere(
            (a) => a.name == j['adapter_type'],
            orElse: () => AdapterType.mock,
          ),
          appid: j['app_id'] ?? '',
          apiKey: j['api_key'] ?? '',
          extra: jsonEncode(j['extra'] ?? {}),
        );
      } catch (_) {}
    }
    // 设备身份
    final selfJson = prefs.getString('self_device');
    if (selfJson != null) {
      try {
        _selfDevice = Device.fromJson(jsonDecode(selfJson) as Map<String, dynamic>);
      } catch (_) {}
    }
    // 密钥
    final edPriv = prefs.getString('ed25519_private') ?? '';
    final xPriv = prefs.getString('x25519_private') ?? '';
    if (edPriv.isNotEmpty) {
      _rust.restoreIdentity(edPriv, xPriv);
    }
    // 设置
    final setJson = prefs.getString('app_settings');
    if (setJson != null) {
      try {
        _settings = AppSettings.fromJson(jsonDecode(setJson) as Map<String, dynamic>);
      } catch (_) {}
    }
  }

  Future<void> _persist() async {
    final prefs = _prefs!;
    if (_signaling != null) {
      await prefs.setString('signaling_config', jsonEncode(_signaling!.toJson()));
    }
    if (_selfDevice != null) {
      await prefs.setString('self_device', jsonEncode(_selfDevice!.toJson()));
    }
    await prefs.setString('app_settings', jsonEncode(_settings.toJson()));
  }

  // ---------- 向导流程 ----------

  void goToSetup() => _setRoute(AppRoute.setup);
  void goToPairing() => _setRoute(AppRoute.pairing);
  void goToHome() => _setRoute(AppRoute.home);

  /// 保存信令配置
  Future<void> saveSignaling(SignalingConfig config) async {
    _signaling = config;
    _signalingVerified = false;
    _signalingError = '';
    await _persist();
    notifyListeners();
  }

  /// 验证信令连接
  Future<void> verifySignaling() async {
    final cfg = _signaling;
    if (cfg == null) return;
    _verifying = true;
    _signalingError = '';
    notifyListeners();
    try {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      // 基本格式验证
      switch (cfg.adapterType) {
        case AdapterType.mock:
          _signalingVerified = true;
          _signalingError = '';
          break;
        case AdapterType.qqOfficial:
          if (cfg.appid.isEmpty || cfg.apiKey.isEmpty) {
            _signalingVerified = false;
            _signalingError = 'QQ 官方适配器需要 AppID 和 AppSecret';
          } else {
            _signalingVerified = true;
            _signalingError = '凭据有效；注意：官方回调需公网地址，无服务器场景能力受限';
          }
          break;
        case AdapterType.oneBot:
          if (!cfg.appid.startsWith('ws://') && !cfg.appid.startsWith('wss://')) {
            _signalingVerified = false;
            _signalingError = 'OneBot 需要 WebSocket 地址 (ws:// 或 wss://)';
          } else if (cfg.apiKey.isEmpty) {
            _signalingVerified = false;
            _signalingError = 'OneBot 需要 Access Token';
          } else {
            _signalingVerified = true;
            _signalingError = '凭据有效；非官方接入，注意 QQ 账号风险';
          }
          break;
      }
    } catch (e) {
      _signalingVerified = false;
      _signalingError = '验证失败: $e';
    } finally {
      _verifying = false;
      await _persist();
      notifyListeners();
    }
  }

  /// 创建设备身份（首台设备）
  Future<void> createDeviceIdentity(String name, String platform) async {
    final json = _rust.createIdentity(name, platform);
    final j = jsonDecode(json) as Map<String, dynamic>;
    final identity = j['identity'] as Map<String, dynamic>;
    _selfDevice = Device(
      deviceId: identity['device_id'] as String,
      deviceName: name,
      platform: Platform.values.firstWhere(
        (p) => p.name == platform,
        orElse: () => Platform.linux,
      ),
      groupId: identity['group_id'] as String,
      status: DeviceStatus.online,
      lastSeen: DateTime.now(),
      isSelf: true,
      ed25519PublicKey: identity['ed25519_public_key'] as String,
      x25519PublicKey: identity['x25519_public_key'] as String,
    );
    // 保存私钥
    await _prefs!.setString('ed25519_private', j['ed25519_private'] as String);
    await _prefs!.setString('x25519_private', j['x25519_private'] as String);
    await _persist();
    notifyListeners();
  }

  /// 创建设备组（生成配对码）
  String get groupCode {
    final id = _selfDevice?.groupId ?? '000000';
    // 取 group_id 前 8 位作为配对码
    return id.replaceAll('-', '').substring(0, 8).toUpperCase();
  }

  // ---------- 设备管理 ----------

  Future<void> refreshDevices() async {
    _rust.markStaleDevices();
    // 从存储加载同组设备（Mock/演示）
    if (_selfDevice != null) {
      final json = _rust.getDevices(_selfDevice!.groupId);
      final list = jsonDecode(json) as List;
      _devices.clear();
      for (final d in list) {
        _devices.add(Device.fromJson(d as Map<String, dynamic>));
      }
      // 确保本机在列表中
      if (!_devices.any((d) => d.deviceId == _selfDevice!.deviceId)) {
        _devices.insert(0, _selfDevice!);
      }
    }
    notifyListeners();
  }

  Future<void> renameDevice(String id, String newName) async {
    final idx = _devices.indexWhere((d) => d.deviceId == id);
    if (idx >= 0) {
      final old = _devices[idx];
      _devices[idx] = Device(
        deviceId: old.deviceId,
        deviceName: newName,
        platform: old.platform,
        groupId: old.groupId,
        status: old.status,
        lastSeen: old.lastSeen,
        isTrusted: old.isTrusted,
        isSelf: old.isSelf,
        ed25519PublicKey: old.ed25519PublicKey,
        x25519PublicKey: old.x25519PublicKey,
      );
      if (old.isSelf) _selfDevice = _devices[idx];
      await _persist();
      notifyListeners();
    }
  }

  Future<void> deleteDevice(String id) async {
    _devices.removeWhere((d) => d.deviceId == id);
    await _persist();
    notifyListeners();
  }

  Future<void> toggleTrust(String id) async {
    final idx = _devices.indexWhere((d) => d.deviceId == id);
    if (idx >= 0) {
      final old = _devices[idx];
      _devices[idx] = Device(
        deviceId: old.deviceId,
        deviceName: old.deviceName,
        platform: old.platform,
        groupId: old.groupId,
        status: old.status,
        lastSeen: old.lastSeen,
        isTrusted: !old.isTrusted,
        isSelf: old.isSelf,
        ed25519PublicKey: old.ed25519PublicKey,
        x25519PublicKey: old.x25519PublicKey,
      );
      await _persist();
      notifyListeners();
    }
  }

  // ---------- 设置 ----------

  Future<void> updateSettings(AppSettings s) async {
    _settings = s;
    await _persist();
    notifyListeners();
  }

  // ---------- 信令总线 (QQ 群互传) ----------

  Stream<String> get busLog => _bus.onLog;

  /// 启动信令总线：连接本机绑定的 QQ 机器人 (OneBot WS) 或 Mock
  Future<void> startSignaling() async {
    final sig = _signaling;
    final self = _selfDevice;
    if (sig == null || self == null || _busRunning) return;
    _busRunning = true;
    notifyListeners();
    _bus.onStatus.listen((c) {
      _busConnected = c;
      notifyListeners();
    });
    _bus.onMessage.listen(_onBusMessage);
    try {
      await _bus.start(sig,
          selfDeviceId: self.deviceId,
          selfDeviceName: self.deviceName,
          groupId: self.groupId);
    } catch (e) {
      debugPrint('bus start error: $e');
    }
  }

  void _onBusMessage(String rlJson) {
    try {
      final j = jsonDecode(rlJson) as Map<String, dynamic>;
      final type = (j['message_type'] ?? '').toString();
      final sender = (j['sender_device_id'] ?? '').toString();
      final name = (j['payload'] != null
          ? (jsonDecode(j['payload'] as String)['device_name'] ?? '')
          : '') as String;
      if (sender == _selfDevice?.deviceId) return;
      switch (type) {
        case 'DEVICE_ONLINE':
        case 'DEVICE_HEARTBEAT':
          final idx = _devices.indexWhere((d) => d.deviceId == sender);
          final dev = Device(
            deviceId: sender,
            deviceName: name.isNotEmpty ? name : '设备 $sender',
            platform: Platform.linux,
            groupId: _selfDevice!.groupId,
            status: DeviceStatus.online,
            lastSeen: DateTime.now(),
            isTrusted: idx >= 0 ? _devices[idx].isTrusted : false,
          );
          if (idx >= 0) {
            _devices[idx] = dev;
          } else {
            _devices.add(dev);
          }
          notifyListeners();
          break;
        case 'DEVICE_OFFLINE':
          final i2 = _devices.indexWhere((d) => d.deviceId == sender);
          if (i2 >= 0 && !_devices[i2].isSelf) _devices.removeAt(i2);
          notifyListeners();
          break;
        default:
          // CONNECT_REQUEST / SDP / ICE 等留给会话层
          break;
      }
    } catch (_) {}
  }

  /// 停止信令总线
  Future<void> stopSignaling() async {
    if (!_busRunning) return;
    await _bus.stop();
    _busRunning = false;
    _busConnected = false;
    notifyListeners();
  }

  /// 重置（删除配置）
  Future<void> resetConfig() async {
    await _prefs!.remove('signaling_config');
    await _prefs!.remove('self_device');
    await _prefs!.remove('ed25519_private');
    await _prefs!.remove('x25519_private');
    await _prefs!.remove('app_settings');
    _signaling = null;
    _selfDevice = null;
    _signalingVerified = false;
    _settings = AppSettings();
    _devices.clear();
    _setRoute(AppRoute.welcome);
    notifyListeners();
  }
}
