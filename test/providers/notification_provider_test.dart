import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/app_notification.dart';
import 'package:isdasafev2/providers/notification_provider.dart';

import '../support/fake_notification_repository.dart';

void main() {
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('loads existing notifications without announcing them as new', () async {
    final announced = <AppNotification>[];
    final provider = NotificationProvider(
      repository: FakeNotificationRepository(seed: [fakeNotification('a')]),
      onNewNotification: announced.add,
    );
    await flush();

    expect(provider.notifications.length, 1);
    expect(provider.unreadCount, 1);
    expect(announced, isEmpty);
  });

  test('a notification that arrives live is announced once', () async {
    final repository = FakeNotificationRepository(
      seed: [fakeNotification('a')],
    );
    final announced = <AppNotification>[];
    final provider = NotificationProvider(
      repository: repository,
      onNewNotification: announced.add,
    );
    final incoming = <AppNotification>[];
    provider.incoming.listen(incoming.add);
    await flush();

    repository.push(
      fakeNotification('b', type: 'pond_rejected', title: 'Pond not verified'),
    );
    await flush();

    expect(provider.notifications.map((n) => n.id), ['b', 'a']);
    expect(announced.map((n) => n.id), ['b']);
    expect(incoming.map((n) => n.id), ['b']);
    expect(announced.single.isPondVerification, isTrue);
  });

  test('markRead clears the unread count and tells the repository', () async {
    final repository = FakeNotificationRepository(
      seed: [fakeNotification('a'), fakeNotification('b')],
    );
    final provider = NotificationProvider(repository: repository);
    await flush();
    expect(provider.unreadCount, 2);

    await provider.markRead('a');
    expect(provider.unreadCount, 1);
    expect(repository.markedRead, ['a']);

    await provider.markAllRead();
    expect(provider.unreadCount, 0);
    expect(repository.markedRead, ['a', 'b']);
  });

  test('clears when the user signs out', () async {
    final repository = FakeNotificationRepository(
      seed: [fakeNotification('a')],
    );
    final provider = NotificationProvider(repository: repository);
    await flush();
    expect(provider.notifications, isNotEmpty);

    repository.setUserId(null);
    await flush();

    expect(provider.notifications, isEmpty);
  });
}
