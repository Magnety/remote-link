import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/rust_bridge.dart';
import 'screens/welcome_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/home_screen.dart';

class RemoteLinkApp extends StatelessWidget {
  const RemoteLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(rustAvailable: RustBridge().available),
      child: MaterialApp(
        title: 'RemoteLink',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3B82F6),
            brightness: Brightness.dark,
          ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
          cardTheme: const CardThemeData(
            elevation: 2,
            margin: EdgeInsets.all(0),
          ),
        ),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        locale: const Locale('zh'),
        home: const _BootstrapGate(),
      ),
    );
  }
}

/// 启动引导门：等待 AppState.bootstrap() 完成后按路由显示页面
class _BootstrapGate extends StatefulWidget {
  const _BootstrapGate();

  @override
  State<_BootstrapGate> createState() => _BootstrapGateState();
}

class _BootstrapGateState extends State<_BootstrapGate> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await context.read<AppState>().bootstrap();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('bootstrap error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _ready = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 20),
              Text('RemoteLink 启动中…',
                  style: TextStyle(color: Colors.white54)),
            ],
          ),
        ),
      );
    }
    return _RouteSelector(error: _error);
  }
}

/// 根据初始化状态选择路由
class _RouteSelector extends StatelessWidget {
  final String? error;
  const _RouteSelector({this.error});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    Widget screen;
    switch (state.route) {
      case AppRoute.welcome:
        screen = const WelcomeScreen();
        break;
      case AppRoute.setup:
        screen = const SetupScreen();
        break;
      case AppRoute.pairing:
        screen = const PairingScreen();
        break;
      case AppRoute.home:
        screen = const HomeScreen();
        break;
    }
    if (error != null) {
      return Stack(children: [
        screen,
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Material(
            color: Colors.red.shade700.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('初始化警告: $error',
                        style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ]);
    }
    return screen;
  }
}
