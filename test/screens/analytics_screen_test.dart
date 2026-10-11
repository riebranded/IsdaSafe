import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:isdasafev2/providers/pond_provider.dart';
import 'package:isdasafev2/screens/analytics_screen.dart';
import 'package:isdasafev2/services/pond_snapshot_cache.dart';
import 'package:isdasafev2/theme/app_theme.dart';

import '../support/fake_pond_repository.dart';

void main() {
  testWidgets('the pond is picked from a dropdown', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => PondProvider(repository: FakePondRepository()),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: AnalyticsScreen(cache: PondSnapshotCache())),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dropdown = find.byType(DropdownMenu<String>);
    expect(dropdown, findsOneWidget);
    expect(
      tester.widget<DropdownMenu<String>>(dropdown).initialSelection,
      'pond-a',
    );

    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pond B').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<DropdownMenu<String>>(find.byType(DropdownMenu<String>))
          .initialSelection,
      'pond-b',
    );
  });
}
