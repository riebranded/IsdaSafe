import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/theme_provider.dart';
import 'screens/auth/auth_gate.dart';
import 'theme/app_theme.dart';

/// Suppresses the draggable scrollbar Flutter draws by default on
/// mouse-based platforms (web, desktop) for every scrollable widget.
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

class IsdaSafeApp extends StatelessWidget {
  const IsdaSafeApp({super.key, this.home = const AuthGate()});

  /// The first screen. Defaults to the auth gate; tests swap it out so they
  /// don't need a Supabase session.
  final Widget home;

  @override
  Widget build(BuildContext context) {
    final themeMode = context.watch<ThemeProvider>().themeMode;

    return MaterialApp(
      title: 'IsdaSafe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      scrollBehavior: const _NoScrollbarBehavior(),
      // On wide screens a floating snackbar would span the whole window; keep
      // it a readable card instead. (Phones keep the themed side insets.)
      builder: (context, child) {
        final theme = Theme.of(context);
        final wide = MediaQuery.sizeOf(context).width > 560;
        return Theme(
          data: theme.copyWith(
            snackBarTheme: theme.snackBarTheme.copyWith(
              width: wide ? 480 : null,
            ),
          ),
          child: child!,
        );
      },
      home: home,
    );
  }
}
