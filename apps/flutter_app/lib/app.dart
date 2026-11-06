import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'screens/welcome_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/pairing_screen.dart';
import 'screens/home_screen.dart';

class RemoteLinkApp extends StatelessWidget {
  const RemoteLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
      home: _RouteSelector(),
    );
  }
}

/// 根据初始化状态选择路由
class _RouteSelector extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    switch (state.route) {
      case AppRoute.welcome:
        return const WelcomeScreen();
      case AppRoute.setup:
        return const SetupScreen();
      case AppRoute.pairing:
        return const PairingScreen();
      case AppRoute.home:
        return const HomeScreen();
    }
  }
}
