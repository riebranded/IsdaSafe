import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/models/pond_verification.dart';
import 'package:isdasafev2/providers/notification_provider.dart';
import 'package:isdasafev2/providers/pond_provider.dart';
import 'package:isdasafev2/screens/notifications_screen.dart';
import 'package:isdasafev2/services/pond_snapshot_cache.dart';
import 'package:isdasafev2/theme/app_theme.dart';

import '../support/fake_notification_repository.dart';
import '../support/fake_pond_repository.dart';

void main() {
  Widget build({required List<Pond> ponds, required FakeNotificationRepository notifications}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PondProvider(repository: FakePondRepository(seed: ponds))),
        ChangeNotifierProvider(create: (_) => NotificationProvider(repository: notifications)),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: NotificationsScreen(cache: PondSnapshotCache())),
      ),
    );
  }

  final waitingPond = Pond(id: 'bld', name: 'Roof Pond', verificationStatus: VerificationStatus.needsPhotos);

  FakeNotificationRepository photosNeeded() => FakeNotificationRepository(
    seed: [
      fakeNotification(
        'n1',
        type: 'pond_needs_photos',
        title: 'Photos needed',
        body: 'We need a little more to verify Roof Pond.',
      ).copyWithPond('bld'),
    ],
  );

  testWidgets('tapping a "photos needed" notification opens the photo modal and marks it read', (tester) async {
    final notifications = photosNeeded();
    await tester.pumpWidget(build(ponds: [waitingPond], notifications: notifications));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Photos needed'));
    await tester.pumpAndSettle();

    expect(find.text('Add photos of “Roof Pond”'), findsOneWidget);
    expect(notifications.markedRead, ['n1']);
  });

  testWidgets('the card has an explicit Add photos button that opens the same modal', (tester) async {
    await tester.pumpWidget(build(ponds: [waitingPond], notifications: photosNeeded()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add photos'));
    await tester.pumpAndSettle();

    expect(find.text('Add photos of “Roof Pond”'), findsOneWidget);
  });

  testWidgets('once the pond is no longer waiting there is no button, and tapping says so', (tester) async {
    await tester.pumpWidget(
      build(ponds: [Pond(id: 'bld', name: 'Roof Pond')], notifications: photosNeeded()),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Add photos'), findsNothing);

    await tester.tap(find.text('Photos needed'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Add photos of'), findsNothing);
    expect(find.textContaining("isn't waiting for photos"), findsOneWidget);
  });

  testWidgets('other notifications just mark read and open nothing', (tester) async {
    final notifications = FakeNotificationRepository(
      seed: [fakeNotification('n2', title: 'Pond verified').copyWithPond('bld')],
    );
    await tester.pumpWidget(build(ponds: [waitingPond], notifications: notifications));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pond verified'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Add photos of'), findsNothing);
    expect(notifications.markedRead, ['n2']);
  });
}
