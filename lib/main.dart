import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'providers/pond_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => PondProvider(),
      child: const IsdaSafeApp(),
    ),
  );
}
