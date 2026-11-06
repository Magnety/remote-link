import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/app_state.dart';

/// 欢迎页面
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withOpacity(0.4),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.videocam, size: 48, color: Colors.white),
              ),
              const SizedBox(height: 24),
              const Text(
                'RemoteLink',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '跨平台远程控制 · QQ 信令 · WebRTC P2P',
                style: TextStyle(fontSize: 15, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withOpacity(0.2)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _FeatureRow(
                        icon: Icons.public, text: '无公网服务器，QQ 机器人自动发现设备'),
                    _FeatureRow(icon: Icons.bolt, text: 'WebRTC P2P 直连，低延迟远程桌面'),
                    _FeatureRow(icon: Icons.lock, text: 'Ed25519 设备签名 + 端到端加密'),
                    _FeatureRow(icon: Icons.devices,
                        text: 'Windows / macOS / Android 一套代码多端运行'),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              FilledButton.icon(
                onPressed: () => context.read<AppState>().goToSetup(),
                icon: const Icon(Icons.chevron_right),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  child: Text('开始配置', style: TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('v0.1.0', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
