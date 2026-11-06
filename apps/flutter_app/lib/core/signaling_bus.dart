import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/models.dart';

/// 信令总线：连接 OneBot (NapCat) WebSocket 或通过 Mock 回环，
/// 实现"每台设备绑定一个 QQ 机器人、同群互传"的信令交换。
///
/// - publish: 本机发出信令 JSON 字符串
/// - onMessage: 收到其他设备的信令 JSON 字符串
/// - status: 连接状态
class SignalingBus {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _heartbeat;
  Timer? _reconnectTimer;
  final Completer<void> _ready = Completer<void>();
  bool _running = false;
  bool _closedByUser = false;

  final _statusCtrl = StreamController<bool>.broadcast();
  final _messageCtrl = StreamController<String>.broadcast();
  final _logCtrl = StreamController<String>.broadcast();

  bool get connected => _statusCtrl.hasListener && _connected;
  bool _connected = false;
  String _groupId = '';
  int _obGroupId = 0;
  bool get isConnected => _connected;
  Stream<bool> get onStatus => _statusCtrl.stream;
  Stream<String> get onMessage => _messageCtrl.stream;
  Stream<String> get onLog => _logCtrl.stream;

  static bool _isRlMsg(String s) {
    final t = s.trim();
    if (!t.startsWith('[RL]')) return false;
    try {
      jsonDecode(t.substring(4));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 启动。config: adapterType=oneBot 时 wsUrl=appid, token=apiKey, group=extra.group_id
  Future<void> start(SignalingConfig config, {required String selfDeviceId, required String selfDeviceName, required String groupId}) async {
    _closedByUser = false;
    _groupId = groupId;
    switch (config.adapterType) {
      case AdapterType.oneBot:
        await _connectOneBot(config, selfDeviceId, selfDeviceName, groupId);
      case AdapterType.mock:
        _log('Mock 信令总线已启动（本地回环，无网络）');
        _setConnected(true);
        if (!_ready.isCompleted) _ready.complete();
      case AdapterType.qqOfficial:
        _log('QQ 官方适配器（演示模式）');
        _setConnected(true);
        if (!_ready.isCompleted) _ready.complete();
    }
    // 心跳
    _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) {
      publish({
        'protocol_version': 1,
        'message_type': 'DEVICE_HEARTBEAT',
        'message_id': _uuid(),
        'group_id': groupId,
        'sender_device_id': selfDeviceId,
        'target_device_id': null,
        'session_id': null,
        'sequence': 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300,
        'payload': jsonEncode({'device_name': selfDeviceName}),
        'signature': '',
      });
    });
  }

  void _setConnected(bool v) {
    if (_connected != v) {
      _connected = v;
      try { _statusCtrl.add(v); } catch (_) {}
    }
  }

  void _log(String s) {
    final d = DateTime.now();
    final ts = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';
    _logCtrl.add('[$ts] $s');
  }

  Future<void> _connectOneBot(SignalingConfig config, String selfId, String selfName, String groupId) async {
    final url = config.appid; // ws://host:port
    final token = config.apiKey;
    int obGroupNum = 0;
    if (config.extra.isNotEmpty && config.extra != '{}') {
      try {
        obGroupNum = (jsonDecode(config.extra)['group_id'] as num).toInt();
      } catch (_) {}
    }
    _obGroupId = obGroupNum;
    _log('连接 OneBot: $url (群: ${obGroupNum != 0 ? obGroupNum : groupId})');
    try {
      final ch = await _wsConnect(url, token);
      _channel = ch;
      _sub = ch.stream.listen((data) => _handleRaw(data.toString(), selfId),
          onError: (e) {
        _log('WS 错误: $e');
        _setConnected(false);
      },
          onDone: () {
        _log('WS 断开');
        _setConnected(false);
      });
      _setConnected(true);
      if (!_ready.isCompleted) _ready.complete();
      _log('OneBot 已连接');
      // 上线广播
      publish({
        'protocol_version': 1,
        'message_type': 'DEVICE_ONLINE',
        'message_id': _uuid(),
        'group_id': groupId,
        'sender_device_id': selfId,
        'target_device_id': null,
        'session_id': null,
        'sequence': 0,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300,
        'payload': jsonEncode({'device_name': selfName}),
        'signature': '',
      });
    } catch (e) {
      _log('OneBot 连接失败: $e');
      _setConnected(false);
      // 自动重连
      _reconnectTimer = Timer(const Duration(seconds: 5), () {
        if (!_closedByUser) _connectOneBot(config, selfId, selfName, groupId);
      });
    }
  }

  Future<WebSocketChannel> _wsConnect(String url, String token) async {
    // NapCat/OneBot 12 支持 Sec-WebSocket-Protocol 传 token
    final headers = <String, String>{};
    if (token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    final channel = IOWebSocketChannel.connect(Uri.parse(url), headers: headers);
    // 等待连接建立
    final ok = await channel.ready.timeout(const Duration(seconds: 10)).catchError((e) {
      throw '连接超时: $e';
    });
    return channel;
  }

  void _handleRaw(String raw, String selfId) {
    final t = raw.trim();
    // OneBot 11 推送格式: {"post_type":"message","message_type":"group","group_id":...,"message":[{"type":"text","data":{"text":"..."}}],...}
    if (t.startsWith('{')) {
      try {
        final j = jsonDecode(t) as Map<String, dynamic>;
        final postType = j['post_type'];
        if (postType == 'message') {
          final msgs = j['message'];
          if (msgs is List) {
            for (final seg in msgs) {
              if (seg is Map && seg['type'] == 'text') {
                final text = (seg['data'] as Map?)?['text']?.toString() ?? '';
                if (text.trim().startsWith('[RL]')) {
                  _deliver(text.substring(4), selfId);
                }
              }
            }
          }
        }
      } catch (_) {}
    } else if (t.startsWith('[RL]')) {
      _deliver(t.substring(4), selfId);
    }
  }

  void _deliver(String rlJson, String selfId) {
    try {
      final j = jsonDecode(rlJson) as Map<String, dynamic>;
      final sender = j['sender_device_id']?.toString() ?? '';
      if (sender == selfId) return; // 自己的消息
      final target = j['target_device_id']?.toString();
      if (target != null && target != '' && target != selfId) {
        // 定向消息但不是给本机的 → 忽略
        return;
      }
      _messageCtrl.add(rlJson);
    } catch (_) {}
  }

  /// 发出信令（Dart 侧构造好的 JSON 对象）
  void publish(Map<String, dynamic> msg) {
    final json = '[RL]${jsonEncode(msg)}';
    final ch = _channel;
    if (ch != null) {
      // OneBot 11: 通过 WS 发送 action 请求到群
      final action = {
        'action': 'send_group_msg',
        'params': {
          'group_id': _obGroupId,
          'message': [
            {'type': 'text', 'data': {'text': json}}
          ],
        },
      };
      ch.sink.add(jsonEncode(action));
      _log('→ ${msg['message_type']}');
    } else {
      _log('→ (未连接, Mock 模式) ${msg['message_type']}');
    }
  }

  Future<void> stop() async {
    _closedByUser = true;
    _heartbeat?.cancel();
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    try { await _channel?.sink.close(); } catch (_) {}
    _setConnected(false);
  }

  void dispose() {
    _stopT?.cancel();
    _statusCtrl.close();
    _messageCtrl.close();
    _logCtrl.close();
  }

  Timer? _stopT;

  static String _uuid() {
    final rnd = _rand;
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static final _rand = _Rng();
}

class _Rng {
  int _s = 0x9e3779b9 ^ DateTime.now().microsecondsSinceEpoch;
  int nextInt(int max) {
    _s ^= (_s << 13); _s ^= (_s >> 7); _s ^= (_s << 17);
    return (_s & 0x7fffffff) % max;
  }
}
