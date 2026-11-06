import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/models.dart';

/// 设置页面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _stunCtrl;
  late final TextEditingController _turnServerCtrl;
  late final TextEditingController _turnUserCtrl;
  late final TextEditingController _turnPassCtrl;
  late final int _heartbeat;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>().settings;
    _nameCtrl = TextEditingController(text: s.deviceName);
    _stunCtrl = TextEditingController(text: s.stunServers.join('\n'));
    _turnServerCtrl = TextEditingController(text: s.turnServer);
    _turnUserCtrl = TextEditingController(text: s.turnUsername);
    _turnPassCtrl = TextEditingController(text: s.turnPassword);
    _heartbeat = s.heartbeatIntervalSecs;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _stunCtrl.dispose();
    _turnServerCtrl.dispose();
    _turnUserCtrl.dispose();
    _turnPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final old = state.settings;
    final s = AppSettings(
      deviceName: _nameCtrl.text.trim(),
      autoStart: old.autoStart,
      heartbeatIntervalSecs: _heartbeat,
      videoQuality: old.videoQuality,
      stunServers: _stunCtrl.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      turnServer: _turnServerCtrl.text.trim(),
      turnUsername: _turnUserCtrl.text.trim(),
      turnPassword: _turnPassCtrl.text.trim(),
      unattendedMode: old.unattendedMode,
      readonlyMode: old.readonlyMode,
    );
    await state.updateSettings(s);
    // 更新本机名
    if (state.selfDevice != null && s.deviceName.isNotEmpty) {
      await state.renameDevice(state.selfDevice!.deviceId, s.deviceName);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设置已保存'), duration: Duration(seconds: 2)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = state.settings;
    final theme = Theme.of(context);
    final isDesktop = PlatformX.current() != Platform.android;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          FilledButton.tonal(
            onPressed: _save,
            child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text('保存')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 设备
          _Section('设备'),
          _Tile(
            icon: Icons.edit_note,
            title: '设备名称',
            value: _nameCtrl,
          ),
          const SizedBox(height: 16),

          // 信令
          _Section('QQ 机器人信令'),
          _Tile(
            icon: Icons.cloud,
            title: '信令适配器',
            subtitle: state.signaling?.adapterType.label ?? '未配置',
            trailing: TextButton(
              onPressed: () {
                Navigator.pop(context);
                state.goToSetup();
              },
              child: const Text('修改'),
            ),
          ),
          const SizedBox(height: 16),

          // 网络
          _Section('网络 (STUN / TURN)'),
          _Tile(
            icon: Icons.public,
            title: 'STUN 服务器 (每行一个)',
            value: _stunCtrl,
            multiLine: true,
          ),
          const SizedBox(height: 8),
          _Tile(
              icon: Icons.swap_horiz, title: 'TURN 服务器 URL', value: _turnServerCtrl),
          _Tile(icon: Icons.person, title: 'TURN 用户名', value: _turnUserCtrl),
          _Tile(
              icon: Icons.key,
              title: 'TURN 密码',
              value: _turnPassCtrl,
              obscure: true),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer),
            title: const Text('心跳间隔'),
            subtitle: Text('$_heartbeat 秒 (建议 600-1800，受 QQ 限流约束)'),
            trailing: DropdownButton<int>(
              value: _heartbeat,
              items: const [
                DropdownMenuItem(value: 300, child: Text('5 分钟')),
                DropdownMenuItem(value: 600, child: Text('10 分钟')),
                DropdownMenuItem(value: 1200, child: Text('20 分钟')),
                DropdownMenuItem(value: 1800, child: Text('30 分钟')),
              ],
              onChanged: (v) => setState(() => _heartbeat = v!),
            ),
          ),
          const SizedBox(height: 16),

          // 安全
          _Section('安全'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('无人值守模式'),
            subtitle: const Text('被控端免确认连接（需本机主动开启）'),
            value: s.unattendedMode,
            onChanged: (v) => setState(() => s.unattendedMode = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('只读屏幕模式'),
            subtitle: const Text('默认只允许查看屏幕，不可控制'),
            value: s.readonlyMode,
            onChanged: (v) => setState(() => s.readonlyMode = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('开机自启动'),
            value: s.autoStart,
            onChanged: (v) => setState(() => s.autoStart = v),
          ),
          const SizedBox(height: 16),

          // 视频
          _Section('视频质量'),
          _Tile(
            icon: Icons.hd,
            title: '画质模式',
            trailing: DropdownButton<String>(
              value: s.videoQuality,
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('自动')),
                DropdownMenuItem(value: 'high', child: Text('高质量')),
                DropdownMenuItem(value: 'medium', child: Text('均衡')),
                DropdownMenuItem(value: 'low', child: Text('低延迟')),
              ],
              onChanged: (v) => setState(() => s.videoQuality = v!),
            ),
          ),
          const SizedBox(height: 16),

          // 危险区
          _Section('危险区'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('删除全部配置', style: TextStyle(color: Colors.red)),
            subtitle: const Text('清除 QQ 凭据、设备身份和设置'),
            onTap: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('确认删除？'),
                  content: const Text('将清除所有本地配置并返回欢迎页'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
                    FilledButton(
                      onPressed: () {
                        state.resetConfig();
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('删除', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Center(
            child: Text('RemoteLink v0.1.0 · Flutter + Rust + WebRTC',
                style: TextStyle(color: theme.colorScheme.outline, fontSize: 12)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 4),
      child: Text(text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final TextEditingController? value;
  final Widget? trailing;
  final bool multiLine;
  final bool obscure;
  const _Tile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.multiLine = false,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, size: 22),
        title: Text(title),
        subtitle: value != null
            ? null
            : (subtitle != null ? Text(subtitle!) : null),
        trailing: trailing ??
            (value != null
                ? TextField(
                    controller: value,
                    obscureText: obscure,
                    maxLines: multiLine ? null : 1,
                    minLines: multiLine ? 2 : 1,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  )
                : null),
      ),
    );
  }
}