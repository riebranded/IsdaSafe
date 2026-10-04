import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/models/pond_verification.dart';
import 'package:isdasafev2/providers/notification_provider.dart';
import 'package:isdasafev2/providers/pond_provider.dart';
import 'package:isdasafev2/screens/dashboard_screen.dart';
import 'package:isdasafev2/services/pond_snapshot_cache.dart';
import 'package:isdasafev2/theme/app_theme.dart';
import 'package:isdasafev2/widgets/reading_card.dart';
import 'package:isdasafev2/widgets/status_badge.dart';

import '../support/fake_notification_repository.dart';
import '../support/fake_pond_repository.dart';

void main() {
  Widget buildMobileDashboard({
    FakeNotificationRepository? notifications,
    FakePondRepository? ponds,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) =>
              PondProvider(repository: ponds ?? FakePondRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationProvider(
            repository: notifications ?? FakeNotificationRepository(),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          // showDetailPane: false → the narrow/mobile compact layout.
          body: DashboardScreen(
            cache: PondSnapshotCache(),
            showDetailPane: false,
          ),
        ),
      ),
    );
  }

  Future<void> setPhoneSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'mobile dashboard shows a status summary, then compact pond cards',
    (tester) async {
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
    },
  );

  testWidgets(
    'a just-verified pond without species gets a prompt, only while its notification is unread',
    (tester) async {
      await setPhoneSurface(tester);
      final notifications = FakeNotificationRepository(
        seed: [
          // pond-a was just verified; pond-b's announcement was already read.
          fakeNotification('n1', title: 'Pond verified').copyWithPond('pond-a'),
          fakeNotification('n2', readAt: DateTime(2026)).copyWithPond('pond-b'),
        ],
      );
      await tester.pumpWidget(
        buildMobileDashboard(notifications: notifications),
      );
      await tester.pumpAndSettle();

      expect(find.text('“Pond A” is verified'), findsOneWidget);
      expect(find.text('“Pond B” is verified'), findsNothing);
      expect(find.text('Add species'), findsOneWidget);

      // "Later" dismisses it by marking the notification read.
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('“Pond A” is verified'), findsNothing);
      expect(notifications.markedRead, ['n1']);
    },
  );

  testWidgets('a pond hidden by buildings is not listed and shows no banner', (
    tester,
  ) async {
    await setPhoneSurface(tester);
    final repository = FakePondRepository(
      seed: [
        Pond(id: 'ok', name: 'Open Pond'),
        Pond(
          id: 'bld',
          name: 'Roof Pond',
          verificationStatus: VerificationStatus.needsPhotos,
          verificationMessage:
              'Buildings cover this spot. Add at least 3 photos.',
        ),
      ],
    );
    await tester.pumpWidget(buildMobileDashboard(ponds: repository));
    await tester.pumpAndSettle();

    // Not on the dashboard...
    expect(find.text('Open Pond'), findsOneWidget);
    expect(find.text('Roof Pond'), findsNothing);
    // ...and the request for photos lives in notifications, not here.
    expect(find.text('“Roof Pond” needs photos'), findsNothing);
    expect(find.text('Add photos'), findsNothing);
  });
}
