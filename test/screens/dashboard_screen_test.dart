import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:isdasafev2/providers/pond_provider.dart';
import 'package:isdasafev2/screens/dashboard_screen.dart';
import 'package:isdasafev2/services/pond_snapshot_cache.dart';
import 'package:isdasafev2/theme/app_theme.dart';
import 'package:isdasafev2/widgets/reading_card.dart';
import 'package:isdasafev2/widgets/status_badge.dart';

void main() {
  Widget buildMobileDashboard() {
    return ChangeNotifierProvider(
      create: (_) => PondProvider(),
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          // showDetailPane: false → the narrow/mobile compact layout.
          body: DashboardScreen(cache: PondSnapshotCache(), showDetailPane: false),
        ),
      ),
    );
  }

  Future<void> setPhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('mobile dashboard shows a status summary, then compact pond cards', (tester) async {
    await setPhoneSurface(tester);
    await tester.pumpWidget(buildMobileDashboard());
    await tester.pumpAndSettle();

    // No layout overflow at phone width (readings crammed into one row).
    expect(tester.takeException(), isNull);

    // Summary header with the three status buckets.
    expect(find.text('Normal'), findsAtLeastNWidgets(1));
    expect(find.text('Warning'), findsAtLeastNWidgets(1));
    expect(find.text('Critical'), findsAtLeastNWidgets(1));

    // One card per seeded pond, each with a status badge (top-right) and a
    // location line beneath the name.
    expect(find.byType(StatusBadge), findsNWidgets(3));
    expect(find.byIcon(Icons.location_on_outlined), findsNWidgets(3));

    // Readings are condensed to one row of compact chips — the full
    // ReadingCard grid is not used on mobile.
    expect(find.byType(ReadingCard), findsNothing);
    // Temperature values (e.g. "27.4°C") are shown, one per pond.
    expect(find.textContaining('°C'), findsNWidgets(3));
  });
}
