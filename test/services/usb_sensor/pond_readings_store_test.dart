import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/services/usb_sensor/pond_readings_store.dart';
import 'package:isdasafev2/services/usb_sensor/usb_sensor_hub.dart';
import 'package:isdasafev2/widgets/device_connection_banner.dart';
import 'package:isdasafev2/widgets/device_wifi_dialog.dart';

import '../../support/fake_serial_link.dart';

/// One paired device per entry in [uploads] (pond ID -> when its readings
/// arrived; empty for none yet).
class _Source implements PondReadingsSource {
  _Source(this.uploads);

  final Map<String, List<DateTime>> uploads;

  @override
  Future<Map<String, String>> devicesByPond() async => {
    for (final pondId in uploads.keys) pondId: 'A1B2C3D4E5F6',
  };

  @override
  Future<List<StoredReading>> recentReadings(
    String pondId, {
    int limit = 200,
  }) async => [
    // Newest first; every sensor failed, which still proves it's online.
    for (final time in uploads[pondId]!.reversed)
      (time: time, values: <MetricType, double>{}),
  ];
}

/// Uploads every [gap], the newest [ago] before now (oldest first).
List<DateTime> _every(Duration gap, {required Duration ago, int count = 6}) {
  final newest = DateTime.now().subtract(ago);
  return [for (var i = count - 1; i >= 0; i--) newest.subtract(gap * i)];
}

void main() {
  test('tells online, offline and never-connected devices apart', () async {
    const minute = Duration(minutes: 1);
    final store = PondReadingsStore(
      source: _Source({
        'fresh': _every(minute, ago: minute),
        'stale': _every(minute, ago: const Duration(minutes: 30)),
        'new': [],
      }),
    );
    await store.refresh();

    expect(store.connectionFor('fresh'), DeviceConnection.online);
    expect(store.connectionFor('stale'), DeviceConnection.offline);
    expect(store.connectionFor('new'), DeviceConnection.neverConnected);
    expect(store.connectionFor('no-device'), isNull);
    // Once-a-minute uploads: offline after three missed ones.
    expect(store.offlineAfterFor('fresh'), const Duration(minutes: 3));
    expect(
      store.connectionFor(
        'fresh',
        now: DateTime.now().add(const Duration(minutes: 3)),
      ),
      DeviceConnection.offline,
    );
  });

  test('allows for a device that sleeps between uploads', () async {
    const sleep = Duration(minutes: 15);
    final store = PondReadingsStore(
      source: _Source({
        'sleepy': _every(sleep, ago: const Duration(minutes: 20)),
        'gone': _every(sleep, ago: const Duration(minutes: 50)),
      }),
    );
    await store.refresh();

    expect(store.offlineAfterFor('sleepy'), const Duration(minutes: 45));
    expect(store.connectionFor('sleepy'), DeviceConnection.online);
    expect(store.connectionFor('gone'), DeviceConnection.offline);
  });

  testWidgets('an offline device offers to reconnect it to WiFi', (
    tester,
  ) async {
    final previous = PondReadingsStore.instance;
    addTearDown(() => PondReadingsStore.instance = previous);
    final store = PondReadingsStore.instance = PondReadingsStore(
      source: _Source({
        'p1': [DateTime.now().subtract(const Duration(hours: 2))],
      }),
    );
    await store.refresh();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeviceConnectionBanner(
            pond: Pond(id: 'p1', name: 'Pond A'),
          ),
        ),
      ),
    );
    expect(find.text('Device offline'), findsOneWidget);
    expect(find.textContaining('2 h ago'), findsOneWidget);

    await tester.tap(find.text('Reconnect to WiFi'));
    // Not pumpAndSettle: the "waiting for the device" spinner never stops.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Reconnect the device to WiFi'), findsOneWidget);
    expect(
      find.textContaining('IsdaSafe-E5F6', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('the offline banner fits a phone screen', (tester) async {
    final previous = PondReadingsStore.instance;
    addTearDown(() => PondReadingsStore.instance = previous);
    final store = PondReadingsStore.instance = PondReadingsStore(
      source: _Source({
        'p1': [DateTime.now().subtract(const Duration(hours: 2))],
      }),
    );
    await store.refresh();

    for (final width in [320.0, 360.0, 390.0]) {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              // Like the pond page's own padding.
              padding: const EdgeInsets.all(16),
              child: DeviceConnectionBanner(
                pond: Pond(id: 'p1', name: 'Pond A'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'width $width');

      final message = tester.getRect(find.textContaining('No reading since'));
      final button = tester.getRect(find.text('Reconnect to WiFi'));
      expect(message.right, lessThanOrEqualTo(width));
      expect(button.right, lessThanOrEqualTo(width));
      // The button has its own line under the message.
      expect(button.top, greaterThanOrEqualTo(message.bottom));
    }
  });

  testWidgets('changing an online device\'s WiFi asks it to open its hotspot', (
    tester,
  ) async {
    final registry = FakeDeviceRegistry();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDeviceWifiDialog(
              context,
              deviceId: 'A1B2C3D4E5F6',
              reason: WifiSetupReason.change,
              registry: registry,
              hub: UsbSensorHub(link: FakeSerialLink(isSupported: false)),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(registry.wifiSetupRequests, ['A1B2C3D4E5F6']);
    expect(find.text("Change the device's WiFi"), findsOneWidget);
    expect(
      find.textContaining('within about a minute', findRichText: true),
      findsOneWidget,
    );
  });

  group('once the device connects, a modal says so', () {
    final opened = DateTime(2026, 10, 11, 9);

    Future<FakeDeviceRegistry> open(
      WidgetTester tester,
      WifiSetupReason reason,
    ) async {
      final registry = FakeDeviceRegistry()
        ..wifi = (
          ssid: 'Old WiFi',
          ssidChangedAt: opened.subtract(const Duration(days: 3)),
          lastSeenAt: opened.subtract(const Duration(hours: 2)),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDeviceWifiDialog(
                context,
                deviceId: 'A1B2C3D4E5F6',
                reason: reason,
                registry: registry,
                hub: UsbSensorHub(link: FakeSerialLink(isSupported: false)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Waiting for the device to connect...'), findsOneWidget);
      return registry;
    }

    testWidgets('after reconnecting', (tester) async {
      final registry = await open(tester, WifiSetupReason.reconnect);

      // Nothing new yet: still waiting.
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Device connected to WiFi'), findsNothing);

      // It uploads again.
      registry.wifi = (
        ssid: 'Old WiFi',
        ssidChangedAt: registry.wifi!.ssidChangedAt,
        lastSeenAt: opened.add(const Duration(minutes: 1)),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Reconnect the device to WiFi'), findsNothing);
      expect(find.text('Device connected to WiFi'), findsOneWidget);
      expect(find.textContaining('"Old WiFi"'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Device connected to WiFi'), findsNothing);
    });

    testWidgets('after changing networks, only a new network counts', (
      tester,
    ) async {
      final registry = await open(tester, WifiSetupReason.change);

      // Still on the old network, uploading as usual: not done yet.
      registry.wifi = (
        ssid: 'Old WiFi',
        ssidChangedAt: registry.wifi!.ssidChangedAt,
        lastSeenAt: opened.add(const Duration(minutes: 1)),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('Device connected to WiFi'), findsNothing);

      registry.wifi = (
        ssid: 'Home WiFi',
        ssidChangedAt: opened.add(const Duration(minutes: 2)),
        lastSeenAt: opened.add(const Duration(minutes: 2)),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Device connected to WiFi'), findsOneWidget);
      expect(find.textContaining('"Home WiFi"'), findsOneWidget);
    });
  });
}
