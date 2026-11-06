import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../core/app_state.dart';
import '../core/models.dart';
import 'settings_screen.dart';
import 'remote_desktop_screen.dart';

/// 设备管理主页
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = context.read<AppState>();
      s.refreshDevices();
      // 自动启动信令总线 (QQ 群互传)
      if (!s.busRunning && s.signaling != null && s.selfDevice != null) {
        s.startSignaling();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final self = state.selfDevice;

    final online = state.devices
        .where((d) => !d.isSelf && (d.status == DeviceStatus.online || d.status == DeviceStatus.inSession))
        .where((d) => d.deviceName.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    final offline = state.devices
        .where((d) => !d.isSelf && (d.status == DeviceStatus.offline || d.status == DeviceStatus.stale || d.status == DeviceStatus.unknown))
        .where((d) => d.deviceName.toLowerCase().contains(_search.toLowerCase()))
        .toList();

    return Scaffold(
      body: Row(
        children: [
          // 侧边栏
          _Sidebar(
            onSettings: () => _showSettings(context),
          ),
          const VerticalDivider(width: 1),
          // 主内容
          Expanded(
            child: Column(
              children: [
                // 顶部栏
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Text('设备管理',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      // 搜索框
                      Container(
                        width: 220,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _search = v),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search, size: 20),
                            hintText: '搜索设备…',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 10),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: '刷新',
                        onPressed: () => state.refreshDevices(),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // 信令总线状态条
                _SignalingBar(state: state),
                // 当前设备卡片
                if (self != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: _SelfCard(device: self),
                  ),
                // 设备列表
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _SectionHeader(
                          label: '在线设备',
                          count: online.length,
                          color: Colors.greenAccent),
                      ...online.map((d) => _DeviceTile(
                            device: d,
                            onConnect: () => _connect(context, d),
                            onDetails: () => _details(context, d),
                          )),
                      if (online.isEmpty) _EmptyHint(text: '暂无在线设备'),
                      const SizedBox(height: 12),
                      _SectionHeader(
                          label: '离线 / 未知设备',
                          count: offline.length,
                          color: Colors.grey),
                      ...offline.map((d) => _DeviceTile(
                            device: d,
                            onConnect: () => _connect(context, d),
                            onDetails: () => _details(context, d),
                          )),
                      if (offline.isEmpty) _EmptyHint(text: '暂无离线设备'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _connect(BuildContext context, Device d) {
    if (d.status == DeviceStatus.offline || d.status == DeviceStatus.stale) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${d.deviceName} 当前离线，正在尝试唤醒…')),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RemoteDesktopScreen(device: d)),
    );
  }

  void _details(BuildContext context, Device d) {
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(d.platform.icon),
            const SizedBox(width: 8),
            Expanded(child: Text(d.deviceName)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(label: '设备 ID', value: d.deviceId),
            _DetailRow(label: '平台', value: d.platform.label),
            _DetailRow(label: '状态', value: d.status.label),
            _DetailRow(label: '最后活动', value: fmt.format(d.lastSeen)),
            _DetailRow(label: '可信设备', value: d.isTrusted ? '是' : '否'),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => _renameDialog(ctx, d),
                  child: const Text('重命名'),
                ),
                TextButton(
                  onPressed: () {
                    context.read<AppState>().toggleTrust(d.deviceId);
                    Navigator.pop(ctx);
                  },
                  child: Text(d.isTrusted ? '撤销信任' : '标记可信'),
                ),
                TextButton(
                  onPressed: () {
                    context.read<AppState>().deleteDevice(d.deviceId);
                    Navigator.pop(ctx);
                  },
                  child: const Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _renameDialog(BuildContext context, Device d) {
    final ctrl = TextEditingController(text: d.deviceName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名设备'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '设备名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              context.read<AppState>().renameDevice(d.deviceId, ctrl.text.trim());
              Navigator.pop(ctx);
              if (context != ctx) {}
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

// ---------- 子组件 ----------

class _Sidebar extends StatelessWidget {
  final VoidCallback onSettings;
  const _Sidebar({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final self = state.selfDevice;
    final platform = PlatformX.current();

    return SizedBox(
      width: 230,
      child: Container(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
        child: Column(
          children: [
            // Logo
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.videocam, size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  const Text('RemoteLink',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const Divider(height: 1),
            // 当前设备
            if (self != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(platform.icon, size: 16, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(self.deviceName,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                          Text(platform.label,
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(child: const SizedBox()),
            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.settings, size: 20),
                    title: const Text('设置', style: TextStyle(fontSize: 14)),
                    onTap: onSettings,
                  ),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.help_outline, size: 20),
                    title: const Text('关于', style: TextStyle(fontSize: 14)),
                    onTap: () => _about(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _about(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('关于 RemoteLink'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('版本 v0.1.0'),
            SizedBox(height: 8),
            Text('跨平台远程控制软件', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 8),
            Text('技术栈: Flutter + Rust + WebRTC', style: TextStyle(fontSize: 12, color: Colors.grey)),
            SizedBox(height: 8),
            Text('信令: QQ 机器人 (OneBot/NapCat)', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }
}

class _SelfCard extends StatelessWidget {
  final Device device;
  const _SelfCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.home_work, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本机 · ${device.deviceName}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('正在广播在线状态，等待其他设备配对',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              ],
            ),
          ),
          _StatusPill(status: device.status),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SectionHeader({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label (${count})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final Device device;
  final VoidCallback onConnect;
  final VoidCallback onDetails;
  const _DeviceTile({required this.device, required this.onConnect, required this.onDetails});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat('HH:mm');
    final canConnect = device.status == DeviceStatus.online ||
        device.status == DeviceStatus.inSession ||
        device.status == DeviceStatus.connecting;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(device.platform.icon,
              color: device.status == DeviceStatus.online
                  ? theme.colorScheme.primary
                  : Colors.grey),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(device.deviceName,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            _StatusPill(status: device.status),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text('${device.platform.label} · 最后活动 ${fmt.format(device.lastSeen)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonal(
              onPressed: canConnect ? onConnect : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(canConnect ? '连接' : '离线'),
            ),
            const SizedBox(height: 4),
            IconButton(
              icon: const Icon(Icons.more_vert, size: 18),
              onPressed: onDetails,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(text,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

/// 状态胶囊
class _StatusPill extends StatelessWidget {
  final DeviceStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: status.dot.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: status.dot, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(status.label, style: TextStyle(fontSize: 11, color: status.dot)),
        ],
      ),
    );
  }
}
/// 信令总线状态条：显示 QQ 群连接状态，可启动/停止
class _SignalingBar extends StatefulWidget {
  final AppState state;
  const _SignalingBar({required this.state});

  @override
  State<_SignalingBar> createState() => _SignalingBarState();
}

class _SignalingBarState extends State<_SignalingBar> {
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _sub = widget.state.busLog.listen((l) {
      setState(() {
        _logs.add(l);
        if (_logs.length > 50) _logs.removeRange(0, _logs.length - 50);
      });
    });
  }

  StreamSubscription<String>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final adapterLabel = state.signaling?.adapterType.label ?? '未配置';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.busConnected
                  ? Colors.greenAccent
                  : (state.busRunning ? Colors.amber : Colors.grey),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QQ 群信令: $adapterLabel · '
                  '${state.busConnected ? '已连接' : (state.busRunning ? '连接中…' : '未启动')}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (_logs.isNotEmpty)
                  Text(
                    _logs.last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: state.busRunning
                ? () => state.stopSignaling()
                : () => state.startSignaling(),
            child: Text(state.busRunning ? '停止信令' : '启动信令'),
          ),
        ],
      ),
    );
  }
}
