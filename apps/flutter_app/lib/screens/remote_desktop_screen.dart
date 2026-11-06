import 'package:flutter/material.dart';
import 'dart:io' as io;
import '../core/models.dart';

/// 远程桌面页面（控制端）
class RemoteDesktopScreen extends StatefulWidget {
  final Device device;
  const RemoteDesktopScreen({super.key, required this.device});

  @override
  State<RemoteDesktopScreen> createState() => _RemoteDesktopScreenState();
}

class _RemoteDesktopScreenState extends State<RemoteDesktopScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  RemoteConnState _connState = RemoteConnState.idle;
  int _latencyMs = 0;
  double _zoom = 1.0;
  bool _fullscreen = false;
  bool _showKeyboard = false;
  String _quality = 'auto';
  String _statusText = '正在发起连接请求…';

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    _simulateConnect();
  }

  Future<void> _simulateConnect() async {
    setState(() {
      _connState = RemoteConnState.requesting;
      _statusText = '正在发送连接请求到 ${widget.device.deviceName}…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() {
      _connState = RemoteConnState.negotiating;
      _statusText = '交换 SDP Offer/Answer…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _connState = RemoteConnState.connecting;
      _statusText = 'ICE 连通性检查中 (STUN)…';
    });
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    setState(() {
      _connState = RemoteConnState.connected;
      _statusText = 'P2P 连接已建立';
      _latencyMs = 18 + (DateTime.now().millisecond % 30);
    });
    _tickLatency();
  }

  Future<void> _tickLatency() async {
    while (mounted && _connState == RemoteConnState.connected) {
      await Future<void>.delayed(const Duration(seconds: 2));
      setState(() {
        _latencyMs = 12 + (DateTime.now().millisecond % 40);
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAndroid = PlatformX.current() == Platform.android;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // 顶部状态栏
          _TopBar(
            device: widget.device,
            connState: _connState,
            statusText: _statusText,
            latencyMs: _latencyMs,
            quality: _quality,
            onBack: () => Navigator.of(context).pop(),
            onDisconnect: _disconnect,
            onFullscreen: () => setState(() => _fullscreen = !_fullscreen),
          ),
          // 视频区域
          Expanded(
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) {
                return Container(
                  alignment: Alignment.center,
                  color: const Color(0xFF0A0E14),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_connState == RemoteConnState.connected) ...[
                        // 模拟远程桌面画面
                        Container(
                          width: 800,
                          height: 450,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary.withOpacity(0.25),
                                const Color(0xFF111827),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: theme.colorScheme.primary.withOpacity(0.4)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.desktop_windows,
                                  size: 64,
                                  color: theme.colorScheme.primary.withOpacity(0.6)),
                              const SizedBox(height: 16),
                              Text('${widget.device.deviceName} 的屏幕',
                                  style: TextStyle(
                                      fontSize: 20,
                                      color: Colors.white70)),
                              const SizedBox(height: 8),
                              Text('WebRTC 视频流 (H.264) · 实时渲染区域',
                                  style:
                                      const TextStyle(color: Colors.white38, fontSize: 13)),
                            ],
                          ),
                        ),
                      ] else
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 56,
                              height: 56,
                              child: CircularProgressIndicator(
                                strokeWidth: 4,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(_statusText,
                                style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      // 延迟角标
                      if (_connState == RemoteConnState.connected)
                        Positioned(
                          right: 16,
                          top: 12,
                          child: _LatencyBadge(ms: _latencyMs),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          // 底部工具栏
          _BottomBar(
            isAndroid: isAndroid,
            connState: _connState,
            showKeyboard: _showKeyboard,
            quality: _quality,
            onToggleKeyboard: () => setState(() => _showKeyboard = !_showKeyboard),
            onQuality: (q) => setState(() { if (q != null) _quality = q; }),
            onClipboard: () => _toast(context, '剪贴板已同步'),
            onFile: () => _toast(context, '文件传输（演示）'),
            onMonitor: () => _toast(context, '切换显示器（演示）'),
            onPointerMode: () => _toast(context, '切换指针模式'),
          ),
        ],
      ),
    );
  }

  void _disconnect() {
    setState(() {
      _connState = RemoteConnState.disconnected;
      _statusText = '已断开连接';
    });
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }
}

class _TopBar extends StatelessWidget {
  final Device device;
  final RemoteConnState connState;
  final String statusText;
  final int latencyMs;
  final String quality;
  final VoidCallback onBack;
  final VoidCallback onDisconnect;
  final VoidCallback onFullscreen;

  const _TopBar({
    required this.device,
    required this.connState,
    required this.statusText,
    required this.latencyMs,
    required this.quality,
    required this.onBack,
    required this.onDisconnect,
    required this.onFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black87,
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: onBack),
          Icon(device.platform.icon,
              color: connState == RemoteConnState.connected
                  ? theme.colorScheme.primary
                  : Colors.white38,
              size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(device.deviceName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text(_stateLabel(connState),
                    style: TextStyle(
                        color: connState == RemoteConnState.connected
                            ? Colors.greenAccent
                            : Colors.white54,
                        fontSize: 11)),
              ],
            ),
          ),
          if (connState == RemoteConnState.connected)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text('${latencyMs}ms',
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
            ),
          IconButton(
            tooltip: '全屏',
            icon: const Icon(Icons.fullscreen),
            onPressed: onFullscreen,
          ),
          IconButton(
            tooltip: '断开',
            icon: const Icon(Icons.link_off),
            onPressed: onDisconnect,
          ),
        ],
      ),
    );
  }

  String _stateLabel(RemoteConnState s) {
    return switch (s) {
      RemoteConnState.idle => '空闲',
      RemoteConnState.requesting => '请求中',
      RemoteConnState.authorizing => '授权中',
      RemoteConnState.negotiating => '协商中',
      RemoteConnState.connecting => '连接中',
      RemoteConnState.connected => '已连接',
      RemoteConnState.reconnecting => '重连中',
      RemoteConnState.disconnected => '已断开',
      RemoteConnState.failed => '连接失败',
    };
  }
}

class _LatencyBadge extends StatelessWidget {
  final int ms;
  const _LatencyBadge({required this.ms});
  @override
  Widget build(BuildContext context) {
    final color = ms < 30
        ? Colors.greenAccent
        : ms < 80
            ? Colors.amberAccent
            : Colors.redAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.network_check, size: 14, color: color),
          const SizedBox(width: 4),
          Text('$ms ms', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool isAndroid;
  final RemoteConnState connState;
  final bool showKeyboard;
  final String quality;
  final VoidCallback onToggleKeyboard;
  final ValueChanged<String?> onQuality;
  final VoidCallback onClipboard;
  final VoidCallback onFile;
  final VoidCallback onMonitor;
  final VoidCallback onPointerMode;

  const _BottomBar({
    required this.isAndroid,
    required this.connState,
    required this.showKeyboard,
    required this.quality,
    required this.onToggleKeyboard,
    required this.onQuality,
    required this.onClipboard,
    required this.onFile,
    required this.onMonitor,
    required this.onPointerMode,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = connState == RemoteConnState.connected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.black87,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ToolButton(
              icon: Icons.keyboard,
              label: isAndroid ? '键盘' : '软键盘',
              active: showKeyboard,
              enabled: enabled,
              onTap: onToggleKeyboard),
          _ToolButton(
              icon: Icons.content_copy, label: '剪贴板', enabled: enabled, onTap: onClipboard),
          _ToolButton(icon: Icons.folder, label: '文件', enabled: enabled, onTap: onFile),
          _ToolButton(
              icon: Icons.tv, label: '显示器', enabled: enabled, onTap: onMonitor),
          _ToolButton(
              icon: Icons.touch_app, label: '指针', enabled: enabled, onTap: onPointerMode),
          // 画质
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.hd, size: 16, color: Colors.white54),
                const SizedBox(width: 6),
                DropdownButton<String>(
                  value: quality,
                  underline: const SizedBox(),
                  dropdownColor: Colors.grey.shade900,
                  items: const [
                    DropdownMenuItem(value: 'auto', child: Text('画质: 自动')),
                    DropdownMenuItem(value: 'high', child: Text('画质: 高')),
                    DropdownMenuItem(value: 'medium', child: Text('画质: 均衡')),
                    DropdownMenuItem(value: 'low', child: Text('画质: 低延迟')),
                  ],
                  onChanged: enabled ? onQuality : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool active;
  final bool enabled;
  const _ToolButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.active = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.blue.shade800 : Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 20,
                  color: enabled ? (active ? Colors.white : Colors.white70) : Colors.white30),
              const SizedBox(height: 2),
              Text(label,
                  style: TextStyle(
                      fontSize: 10,
                      color: enabled ? (active ? Colors.white : Colors.white54) : Colors.white24)),
            ],
          ),
        ),
      ),
    );
  }
}