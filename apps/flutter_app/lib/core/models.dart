import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io' as io;

/// 设备平台
enum Platform { windows, macos, android, linux }

extension PlatformX on Platform {
  String get label {
    switch (this) {
      case Platform.windows: return 'Windows';
      case Platform.macos: return 'macOS';
      case Platform.android: return 'Android';
      case Platform.linux: return 'Linux';
    }
  }

  IconData get icon {
    switch (this) {
      case Platform.windows: return Icons.computer;
      case Platform.macos: return Icons.laptop_mac;
      case Platform.android: return Icons.smartphone;
      case Platform.linux: return Icons.desktop_windows;
    }
  }

  /// 当前运行平台
  static Platform current() {
    if (io.Platform.isWindows) return Platform.windows;
    if (io.Platform.isMacOS) return Platform.macos;
    if (io.Platform.isAndroid) return Platform.android;
    return Platform.linux;
  }
}

/// 设备在线状态
enum DeviceStatus { online, stale, offline, unknown, connecting, inSession }

extension DeviceStatusX on DeviceStatus {
  String get label {
    switch (this) {
      case DeviceStatus.online: return '在线';
      case DeviceStatus.stale: return '状态过期';
      case DeviceStatus.offline: return '离线';
      case DeviceStatus.unknown: return '未知';
      case DeviceStatus.connecting: return '连接中';
      case DeviceStatus.inSession: return '会话中';
    }
  }
  Color get dot => switch (this) {
    DeviceStatus.online => Colors.greenAccent,
    DeviceStatus.inSession => Colors.blueAccent,
    DeviceStatus.connecting => Colors.amberAccent,
    DeviceStatus.stale => Colors.orange,
    _ => Colors.grey,
  };
}

/// 连接状态
enum RemoteConnState {
  idle, requesting, authorizing, negotiating,
  connecting, connected, reconnecting, disconnected, failed,
}

/// 信令适配器类型
enum AdapterType { mock, qqOfficial, oneBot }

extension AdapterTypeX on AdapterType {
  String get label {
    switch (this) {
      case AdapterType.mock: return 'Mock (本地测试)';
      case AdapterType.qqOfficial: return 'QQ 官方机器人';
      case AdapterType.oneBot: return 'OneBot (NapCat)';
    }
  }
}

/// 信令配置
class SignalingConfig {
  final AdapterType adapterType;
  final String appid;
  final String apiKey;
  final String extra; // JSON

  const SignalingConfig({
    required this.adapterType,
    this.appid = '',
    this.apiKey = '',
    this.extra = '{}',
  });

  Map<String, dynamic> toJson() => {
        'adapter_type': adapterType.name,
        'app_id': appid,
        'api_key': apiKey,
        'extra': jsonDecode(extra),
      };
}

/// 设备信息
class Device {
  final String deviceId;
  final String deviceName;
  final Platform platform;
  final String groupId;
  final DeviceStatus status;
  final DateTime lastSeen;
  final bool isTrusted;
  final bool isSelf;
  final String ed25519PublicKey;
  final String x25519PublicKey;

  const Device({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.groupId,
    required this.status,
    required this.lastSeen,
    this.isTrusted = false,
    this.isSelf = false,
    this.ed25519PublicKey = '',
    this.x25519PublicKey = '',
  });

  Map<String, dynamic> toJson() => {
        'device_id': deviceId,
        'device_name': deviceName,
        'platform': platform.name,
        'group_id': groupId,
        'status': status.name.toUpperCase(),
        'last_seen': lastSeen.millisecondsSinceEpoch ~/ 1000,
        'ed25519_public_key': ed25519PublicKey,
        'x25519_public_key': x25519PublicKey,
        'capabilities_json': '{}',
        'is_trusted': isTrusted,
      };

  static Device fromJson(Map<String, dynamic> j) => Device(
        deviceId: j['device_id'] ?? '',
        deviceName: j['device_name'] ?? '未知设备',
        platform: _parsePlatform(j['platform']),
        groupId: j['group_id'] ?? '',
        status: _parseStatus(j['status']),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(
            (j['last_seen'] ?? 0) * 1000),
        isTrusted: j['is_trusted'] ?? false,
        ed25519PublicKey: j['ed25519_public_key'] ?? '',
        x25519PublicKey: j['x25519_public_key'] ?? '',
      );

  static Platform _parsePlatform(dynamic v) {
    final s = (v ?? '').toString().toLowerCase();
    return Platform.values.firstWhere(
      (p) => p.name == s,
      orElse: () => Platform.linux,
    );
  }

  static DeviceStatus _parseStatus(dynamic v) {
    final s = (v ?? 'unknown').toString().toUpperCase();
    return switch (s) {
      'ONLINE' => DeviceStatus.online,
      'STALE' => DeviceStatus.stale,
      'OFFLINE' => DeviceStatus.offline,
      'CONNECTING' => DeviceStatus.connecting,
      'IN_SESSION' => DeviceStatus.inSession,
      _ => DeviceStatus.unknown,
    };
  }
}

/// 应用设置
class AppSettings {
  String deviceName;
  bool autoStart;
  int heartbeatIntervalSecs;
  String videoQuality;
  List<String> stunServers;
  String turnServer;
  String turnUsername;
  String turnPassword;
  bool unattendedMode;
  bool readonlyMode;

  AppSettings({
    this.deviceName = '',
    this.autoStart = false,
    this.heartbeatIntervalSecs = 600,
    this.videoQuality = 'auto',
    this.stunServers = const [
      'stun:stun.l.google.com:19302',
      'stun:stun1.l.google.com:19302',
    ],
    this.turnServer = '',
    this.turnUsername = '',
    this.turnPassword = '',
    this.unattendedMode = false,
    this.readonlyMode = false,
  });

  Map<String, dynamic> toJson() => {
        'device_name': deviceName,
        'auto_start': autoStart,
        'heartbeat_interval_secs': heartbeatIntervalSecs,
        'video_quality': videoQuality,
        'stun_servers': stunServers,
        'turn_server': turnServer,
        'turn_username': turnUsername,
        'turn_password': turnPassword,
        'unattended_mode': unattendedMode,
        'readonly_mode': readonlyMode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        deviceName: j['device_name'] ?? '',
        autoStart: j['auto_start'] ?? false,
        heartbeatIntervalSecs: j['heartbeat_interval_secs'] ?? 600,
        videoQuality: j['video_quality'] ?? 'auto',
        stunServers: (j['stun_servers'] as List?)?.cast<String>() ??
            const ['stun:stun.l.google.com:19302'],
        turnServer: j['turn_server'] ?? '',
        turnUsername: j['turn_username'] ?? '',
        turnPassword: j['turn_password'] ?? '',
        unattendedMode: j['unattended_mode'] ?? false,
        readonlyMode: j['readonly_mode'] ?? false,
      );
}
