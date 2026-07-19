import 'package:flutter/material.dart';

import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

class IsdaSafeApp extends StatelessWidget {
  const IsdaSafeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IsdaSafe',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const AppShell(),
    );
  }
}
