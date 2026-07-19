import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:isdasafev2/app.dart';
import 'package:isdasafev2/providers/pond_provider.dart';

void main() {
  Widget buildApp() {
    return ChangeNotifierProvider(
      create: (_) => PondProvider(),
      child: const IsdaSafeApp(),
    );
  }

  /// Above the shell's wide-layout breakpoint (1024px), the shell switches
  /// to the persistent sidebar + detail-pane layout instead of the mobile
  /// list -> full-screen-dashboard push flow.
  Future<void> setWideSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('wide layout shows a persistent sidebar with the first pond selected', (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // Sidebar branding + all ponds are visible at once (no push navigation).
    expect(find.text('IsdaSafe'), findsOneWidget);
    // Pond A is selected, so it appears both in the sidebar and as the
    // detail-pane header; the rest appear only in the sidebar.
    expect(find.text('Pond A'), findsNWidgets(2));
    expect(find.text('Pond B'), findsOneWidget);
    expect(find.text('Pond C'), findsOneWidget);

    // First pond's dashboard is shown inline in the detail pane by default.
    expect(find.text('Latest readings'), findsOneWidget);
    expect(find.text('Suitable fish species'), findsOneWidget);

    // No mobile back button — this is not a pushed route.
    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('wide layout switches the detail pane when a different pond is selected', (tester) async {
    await setWideSurface(tester);
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pond B'));
    await tester.pumpAndSettle();

    // Sidebar stays put (still visible) while the detail pane updates: Pond
    // B is now selected, so it appears twice (sidebar + header) and Pond A
    // drops back to just the sidebar.
    expect(find.text('Pond A'), findsOneWidget);
    expect(find.text('Pond B'), findsNWidgets(2));
    expect(find.text('Latest readings'), findsOneWidget);
  });
}
