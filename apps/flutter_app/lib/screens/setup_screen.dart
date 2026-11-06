import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';
import '../core/models.dart';

/// QQ 机器人配置页面（首次启动向导第二步）
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _appIdCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _groupIdCtrl;
  bool _showKey = false;
  late AdapterType _adapter;

  @override
  void initState() {
    super.initState();
    final sig = context.read<AppState>().signaling;
    _appIdCtrl = TextEditingController(text: sig?.appid ?? '');
    _apiKeyCtrl = TextEditingController(text: sig?.apiKey ?? '');
    _groupIdCtrl = TextEditingController(
        text: sig != null ? _extractGroupId(sig.extra) : '');
    _adapter = sig?.adapterType ?? AdapterType.oneBot;
  }

  String _extractGroupId(String extra) {
    try {
      final j = jsonDecode(extra.isNotEmpty ? extra : '{}') as Map<String, dynamic>;
      return (j['group_id']?.toString()) ?? '';
    } catch (_) {
      return '';
    }
  }

  String _deviceName() {
    try {
      return io.Platform.localHostname;
    } catch (_) {
      return '我的设备';
    }
  }

  @override
  void dispose() {
    _appIdCtrl.dispose();
    _apiKeyCtrl.dispose();
    _groupIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _onVerify() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    await state.saveSignaling(SignalingConfig(
      adapterType: _adapter,
      appid: _appIdCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      extra: _adapter == AdapterType.oneBot
          ? '{"group_id":${_groupIdCtrl.text.trim()}}'
          : '{}',
    ));
    await state.verifySignaling();
    if (context.mounted) {
      final s = context.read<AppState>();
      if (s.signalingVerified) {
        await s.createDeviceIdentity(
          _deviceName(),
          PlatformX.current().name,
        );
        s.goToPairing();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(s.signalingError.isNotEmpty ? s.signalingError : '验证未通过'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('配置 QQ 机器人信令'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionTitle('信令适配器类型'),
                const SizedBox(height: 12),
                SegmentedButton<AdapterType>(
                  segments: [
                    ButtonSegment(
                      value: AdapterType.oneBot,
                      label: const Text('OneBot (NapCat)'),
                      icon: const Icon(Icons.cloud),
                    ),
                    ButtonSegment(
                      value: AdapterType.qqOfficial,
                      label: const Text('QQ 官方'),
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                    ButtonSegment(
                      value: AdapterType.mock,
                      label: const Text('Mock 测试'),
                      icon: const Icon(Icons.science),
                    ),
                  ],
                  selected: {_adapter},
                  onSelectionChanged: (s) => setState(() => _adapter = s.first),
                ),
                const SizedBox(height: 24),
                const _SectionTitle('接入凭据'),
                const SizedBox(height: 12),
                _buildFields(theme),
                const SizedBox(height: 16),
                if (state.verifying)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(
                      children: [
                        SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 12),
                        Text('正在验证连接…'),
                      ],
                    ),
                  )
                else if (state.signalingError.isNotEmpty && !state.signalingVerified)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade400.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade400.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: Colors.red.shade300),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(state.signalingError,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                if (state.signalingVerified)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade400.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade400.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 20, color: Colors.green.shade300),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '验证通过${state.signalingError.isNotEmpty ? ' · ${state.signalingError}' : ''}',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_outline, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '凭据将保存到系统安全存储（Windows Credential Manager / macOS Keychain / Android Keystore），不写入日志或明文配置。',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: state.verifying ? null : _onVerify,
                  icon: state.verifying
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.verified),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Text('验证并继续', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFields(ThemeData theme) {
    final isOneBot = _adapter == AdapterType.oneBot;
    return Column(
      children: [
        TextFormField(
          controller: _appIdCtrl,
          decoration: InputDecoration(
            labelText: isOneBot ? 'WebSocket 地址' : 'AppID / Endpoint',
            hintText: isOneBot ? 'ws://host:port' : '例如 1000123456',
            prefixIcon: const Icon(Icons.link),
            border: const OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _apiKeyCtrl,
          obscureText: !_showKey,
          decoration: InputDecoration(
            labelText: isOneBot ? 'Access Token' : 'AppSecret / API Key',
            hintText: '输入密钥',
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
            border: const OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
        ),
        if (isOneBot) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _groupIdCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'QQ 群号',
              hintText: '例如 123456789',
              prefixIcon: Icon(Icons.group),
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
    );
  }
}
