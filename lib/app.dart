import 'package:flutter/material.dart';

import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';

/// Suppresses the draggable scrollbar Flutter draws by default on
/// mouse-based platforms (web, desktop) for every scrollable widget.
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class IsdaSafeApp extends StatelessWidget {
  const IsdaSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IsdaSafe',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      scrollBehavior: const _NoScrollbarBehavior(),
      home: const AuthGate(),
    );
  }
}
