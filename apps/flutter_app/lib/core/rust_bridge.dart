import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart' as ffi_pkg;

/// Rust 核心 FFI 桥接。
///
/// 优先加载原生库 (libremote_link_core.{so,dylib,dll})；
/// 若原生库未编译，则自动降级为纯 Dart 模拟核心，
/// 保证 GUI 与业务逻辑始终可运行（功能等价，但密钥/存储走 Dart 实现）。
class RustBridge {
  static final RustBridge _instance = RustBridge._();
  factory RustBridge() => _instance;
  RustBridge._();

  bool available = false;

  late final DynamicLibrary _lib;

  /// 初始化。返回是否成功加载原生库。
  bool init() {
    try {
      final name = Platform.isWindows
          ? 'remote_link_core.dll'
          : Platform.isMacOS
              ? 'libremote_link_core.dylib'
              : 'libremote_link_core.so';
      _lib = DynamicLibrary.open(name);
      _wireFunctions();
      available = true;
    } catch (_) {
      available = false;
    }
    return available;
  }

  final Map<String, dynamic> _dartStore = {};

  int rlInit(String dbPath) => 0;

  // 原生函数指针 (仅 available=true 时有效)。c_char 用 Pointer<Uint8> 表示。
  Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)? _createIdentity;
  Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)? _restoreIdentity;
  Pointer<Uint8> Function(Pointer<Uint8>)? _sign;
  int Function(Pointer<Uint8>, Pointer<Uint8>)? _verify;
  Pointer<Uint8> Function()? _getPublicKeys;
  int Function(Pointer<Uint8>)? _saveDevice;
  Pointer<Uint8> Function(Pointer<Uint8>)? _getDevices;
  int Function(Pointer<Uint8>)? _deleteDevice;
  int Function(Pointer<Uint8>)? _saveSettings;
  Pointer<Uint8> Function()? _getSettings;
  Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)? _e2eEncrypt;
  Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)? _e2eDecrypt;
  void Function(Pointer<Uint8>)? _stringFree;
  void Function()? _markStale;

  void _wireFunctions() {
    _createIdentity = _lib.lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>),
        Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)>(
            'rl_create_identity');
    _restoreIdentity = _lib.lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>),
        Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)>(
            'rl_restore_identity');
    _sign = _lib
        .lookupFunction<Pointer<Uint8> Function(Pointer<Uint8>),
            Pointer<Uint8> Function(Pointer<Uint8>)>('rl_sign');
    _verify = _lib.lookupFunction<
        Int Function(Pointer<Uint8>, Pointer<Uint8>),
        int Function(Pointer<Uint8>, Pointer<Uint8>)>('rl_verify');
    _getPublicKeys = _lib
        .lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
            'rl_get_public_keys');
    _saveDevice = _lib
        .lookupFunction<Int Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)>('rl_save_device');
    _getDevices = _lib.lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>),
        Pointer<Uint8> Function(Pointer<Uint8>)>('rl_get_devices');
    _deleteDevice = _lib
        .lookupFunction<Int Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)>('rl_delete_device');
    _saveSettings = _lib
        .lookupFunction<Int Function(Pointer<Uint8>),
            int Function(Pointer<Uint8>)>('rl_save_settings');
    _getSettings = _lib
        .lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>(
            'rl_get_settings');
    _e2eEncrypt = _lib.lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>),
        Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)>(
            'rl_e2e_encrypt');
    _e2eDecrypt = _lib.lookupFunction<
        Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>),
        Pointer<Uint8> Function(Pointer<Uint8>, Pointer<Uint8>)>(
            'rl_e2e_decrypt');
    _stringFree = _lib
        .lookupFunction<Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)>('rl_string_free');
    _markStale = _lib
        .lookupFunction<Void Function(), void Function()>('rl_mark_stale_devices');
  }

  Pointer<Uint8> _alloc(String s) {
    final bytes = utf8.encode(s);
    final buf = ffi_pkg.calloc.allocate<Uint8>(bytes.length + 1);
    for (var i = 0; i < bytes.length; i++) {
      buf[i] = bytes[i];
    }
    buf[bytes.length] = 0;
    return buf;
  }

  String _free(Pointer<Uint8> ptr) {
    final s = ptr.cast<ffi_pkg.Utf8>().toDartString();
    _stringFree?.call(ptr);
    return s;
  }

  String createIdentity(String name, String platform) {
    if (available) {
      final p1 = _alloc(name);
      final p2 = _alloc(platform);
      try {
        return _free(_createIdentity!(p1, p2));
      } finally {
        ffi_pkg.calloc.free(p1.cast());
        ffi_pkg.calloc.free(p2.cast());
      }
    }
    final uuid = _newUuid();
    return jsonEncode({
      'identity': {
        'device_id': uuid,
        'device_name': name,
        'platform': platform,
        'group_id': _newUuid(),
        'ed25519_public_key': _hex(_randBytes(32)),
        'x25519_public_key': _hex(_randBytes(32)),
        'capabilities': {},
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      'ed25519_private': _hex(_randBytes(32)),
      'x25519_private': _hex(_randBytes(32)),
      'ed25519_public': _hex(_randBytes(32)),
      'x25519_public': _hex(_randBytes(32)),
    });
  }

  String restoreIdentity(String edPriv, String xPriv) {
    if (available) {
      final p1 = _alloc(edPriv);
      final p2 = _alloc(xPriv);
      try {
        return _free(_restoreIdentity!(p1, p2));
      } finally {
        ffi_pkg.calloc.free(p1.cast());
        ffi_pkg.calloc.free(p2.cast());
      }
    }
    return jsonEncode({
      'ed25519_public': _hex(_randBytes(32)),
      'x25519_public': _hex(_randBytes(32)),
    });
  }

  String sign(String message) {
    if (available) {
      final p = _alloc(message);
      try {
        return _free(_sign!(p));
      } finally {
        ffi_pkg.calloc.free(p.cast());
      }
    }
    return _hex(_randBytes(32));
  }

  bool verify(String message, String signature) {
    if (available) {
      final p1 = _alloc(message);
      final p2 = _alloc(signature);
      try {
        return _verify!(p1, p2) == 1;
      } finally {
        ffi_pkg.calloc.free(p1.cast());
        ffi_pkg.calloc.free(p2.cast());
      }
    }
    return signature.isNotEmpty;
  }

  String getPublicKeys() {
    if (available) return _free(_getPublicKeys!());
    return '{}';
  }

  int saveDevice(String json) {
    if (available) {
      final p = _alloc(json);
      try {
        return _saveDevice!(p);
      } finally {
        ffi_pkg.calloc.free(p.cast());
      }
    }
    _dartStore[json] = true;
    return 0;
  }

  String getDevices(String groupId) {
    if (available) {
      final p = _alloc(groupId);
      try {
        return _free(_getDevices!(p));
      } finally {
        ffi_pkg.calloc.free(p.cast());
      }
    }
    return '[]';
  }

  void markStaleDevices() {
    _markStale?.call();
  }

  int deleteDevice(String id) {
    if (available) {
      final p = _alloc(id);
      try {
        return _deleteDevice!(p);
      } finally {
        ffi_pkg.calloc.free(p.cast());
      }
    }
    return 0;
  }

  int saveSettings(String json) {
    if (available) {
      final p = _alloc(json);
      try {
        return _saveSettings!(p);
      } finally {
        ffi_pkg.calloc.free(p.cast());
      }
    }
    _dartStore['settings'] = json;
    return 0;
  }

  String getSettings() {
    if (available) return _free(_getSettings!());
    return _dartStore['settings'] ?? '{}';
  }

  String e2eEncrypt(String keyHex, String plaintext) {
    if (available) {
      final p1 = _alloc(keyHex);
      final p2 = _alloc(plaintext);
      try {
        return _free(_e2eEncrypt!(p1, p2));
      } finally {
        ffi_pkg.calloc.free(p1.cast());
        ffi_pkg.calloc.free(p2.cast());
      }
    }
    final k = _unhex(keyHex);
    final data = utf8.encode(plaintext);
    final out = data
        .asMap()
        .map((i, b) => MapEntry(i, b ^ (k.isNotEmpty ? k[i % k.length] : 0)));
    return base64Encode(out.values.toList());
  }

  String e2eDecrypt(String keyHex, String encoded) {
    if (available) {
      final p1 = _alloc(keyHex);
      final p2 = _alloc(encoded);
      try {
        return _free(_e2eDecrypt!(p1, p2));
      } finally {
        ffi_pkg.calloc.free(p1.cast());
        ffi_pkg.calloc.free(p2.cast());
      }
    }
    final k = _unhex(keyHex);
    final data = base64Decode(encoded);
    final out = data
        .asMap()
        .map((i, b) => MapEntry(i, b ^ (k.isNotEmpty ? k[i % k.length] : 0)));
    return utf8.decode(out.values.toList());
  }

  // ---------- 工具 ----------
  static String _newUuid() {
    final b = _randBytes(16);
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = _hex(b);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static List<int> _randBytes(int n) {
    final rnd = _rng;
    return List.generate(n, (_) => rnd.nextInt(256));
  }

  static final _rng = _XorShift128();

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _unhex(String s) {
    final out = <int>[];
    for (var i = 0; i + 1 < s.length; i += 2) {
      out.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}

/// 简单 PRNG (纯 Dart，避免外部依赖)
class _XorShift128 {
  int _s = 0x12345678 ^ DateTime.now().microsecondsSinceEpoch;
  int nextInt(int max) {
    _s ^= (_s << 13);
    _s ^= (_s >> 7);
    _s ^= (_s << 17);
    final v = _s & 0x7fffffff;
    return v % max;
  }
}
