import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/models.dart';

/// 设备配对页面（创建设备组 / 加入设备组）
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final _codeCtrl = TextEditingController();
  bool _joining = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  void _goHome() {
    final state = context.read<AppState>();
    state.refreshDevices();
    state.goToHome();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final self = state.selfDevice;
    final theme = Theme.of(context);
    

    return Scaffold(
      appBar: AppBar(
        title: const Text('设备配对'),
        actions: [
          if (state.devices.isNotEmpty)
            TextButton(onPressed: _goHome, child: const Text('跳过，直接进主页')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionTitle('当前设备'),
              const SizedBox(height: 12),
              if (self != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(self.platform.icon,
                            color: theme.colorScheme.primary),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(self.deviceName,
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                _StatusPill(status: DeviceStatus.online),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('设备 ID: ${self.deviceId}',
                                style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 28),
              const _SectionTitle('设备组配对码'),
              const SizedBox(height: 4),
              const Text('同一用户的所有设备使用同一个配对码加入设备组。',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.primary),
                  ),
                  child: Text(
                    state.groupCode,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6,
                      color: theme.colorScheme.primary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制配对码'),
                ),
              ),
              const SizedBox(height: 28),
              // 加入设备组
              const _SectionTitle('在其他设备上加入本设备组'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      decoration: const InputDecoration(
                        hintText: '输入配对码（在其他设备上）',
                        prefixIcon: Icon(Icons.qr_code),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _joining ? null : _join,
                    child: _joining
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('加入'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // 进入主页
              FilledButton.icon(
                onPressed: _goHome,
                icon: const Icon(Icons.home),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('进入设备管理', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _copyCode() {
    final state = context.read<AppState>();
    Clipboard.setData(ClipboardData(text: state.groupCode));
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配对码已复制'), duration: Duration(seconds: 2)));
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    setState(() => _joining = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('配对码 ${_codeCtrl.text.trim()} 已记录（演示模式）'),
        duration: const Duration(seconds: 2),
      ),
    );
    _codeCtrl.clear();
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey));
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
      decoration: BoxDecoration(
        color: status.dot.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: status.dot, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(status.label, style: TextStyle(fontSize: 11, color: status.dot)),
        ],
      ),
    );
  }
}