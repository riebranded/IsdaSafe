import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/services/mock_sensor_service.dart';
import 'package:isdasafev2/services/usb_sensor/usb_sensor_hub.dart';

import '../../support/fake_serial_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/shared_preferences'),
        (call) async => call.method == 'getAll' ? <String, Object>{} : null,
      );

  test('is unsupported without USB access', () {
    final hub = UsbSensorHub(link: FakeSerialLink(isSupported: false));
    expect(hub.status, UsbSensorStatus.unsupported);
  });

  test('goes live once the required metrics arrive', () async {
    final link = FakeSerialLink();
    final hub = UsbSensorHub(link: link);
    expect(await hub.connect(), isTrue);
    expect(hub.status, UsbSensorStatus.waiting);

    link.send('WiFi connected, IP: 192.168.1.5');
    // Dissolved oxygen (required) failed to read.
    link.send(
      'DO=nan mg/L  pH=nan  NH3=nan mg/L  WaterT=nanC  AirT=29.1C  Hum=78%  ID=A1B2C3D4E5F6',
    );
    await pumpEventQueue();
    expect(hub.status, UsbSensorStatus.waiting);
    expect(hub.hasCompleteReading, isFalse);
    expect(hub.deviceId, 'A1B2C3D4E5F6');

    // pH/ammonia/water temperature (the RS485 probe) aren't required.
    link.send(
      'DO=5.80 mg/L  pH=nan  NH3=nan mg/L  WaterT=nanC  AirT=29.1C  Hum=78%  ID=A1B2C3D4E5F6',
    );
    await pumpEventQueue();
    expect(hub.status, UsbSensorStatus.live);

    final pond = Pond(id: 'p1', name: 'Pond A');
    final other = Pond(id: 'p2', name: 'Pond B');
    final mock = MockSensorService().generateSnapshot(pond);
    expect(hub.liveSnapshotFor(pond, fallback: mock), isNull); // not linked

    await hub.linkTo('p1');
    var snapshot = hub.liveSnapshotFor(pond, fallback: mock)!;
    expect(snapshot.readings[MetricType.dissolvedOxygen]!.value, 5.8);
    expect(snapshot.readings[MetricType.humidity]!.value, 78);
    expect(snapshot.history[MetricType.humidity]!.length, 2); // padded
    // Not sent by the device: mock data.
    expect(
      snapshot.readings[MetricType.ph],
      same(mock.readings[MetricType.ph]),
    );
    expect(hub.isLive(MetricType.ph), isFalse);
    expect(hub.liveSnapshotFor(other, fallback: mock), isNull);

    // Once the probe works, its values are used too.
    link.send(kSampleSensorLine);
    await pumpEventQueue();
    snapshot = hub.liveSnapshotFor(pond, fallback: mock)!;
    expect(snapshot.readings[MetricType.temperature]!.value, 27.4);

    await link.unplug();
    await pumpEventQueue();
    expect(hub.status, UsbSensorStatus.disconnected);
    // The last real values stay on the dashboard after unplugging.
    expect(hub.liveSnapshotFor(pond, fallback: mock), isNotNull);
  });

  test('stays disconnected when the user cancels the port chooser', () async {
    final hub = UsbSensorHub(link: FakeSerialLink(grantsPort: false));
    expect(await hub.connect(), isFalse);
    expect(hub.status, UsbSensorStatus.disconnected);
  });

  test('unpairing sends UNPAIR and waits for the device to confirm', () async {
    final link = FakeSerialLink();
    final hub = UsbSensorHub(link: link);
    await hub.connect();
    expect(await hub.sendUnpair(), isTrue);
    expect(link.written, ['UNPAIR']);

    link.answersCommands = false;
    final pending = hub.sendUnpair();
    link.send('UNPAIR ERROR');
    expect(await pending, isFalse);
  });

  test('scans the WiFi networks the device can see', () async {
    final link = FakeSerialLink()
      ..replyTo = (line) => line == 'WIFI SCAN'
          ? [
              '[WiFi] scanning...',
              'WIFI NET -48 secured Home WiFi 2.4G',
              'WIFI NET -95 open Cafe',
              'WIFI SCAN DONE 2',
            ]
          : [];
    final hub = UsbSensorHub(link: link);
    await hub.connect();

    final networks = (await hub.scanWifi())!;
    expect(networks.map((n) => n.ssid), ['Home WiFi 2.4G', 'Cafe']);
    expect(networks.first.secured, isTrue);
    expect(networks.first.signalPercent, 100);
    expect(networks.last.secured, isFalse);
    expect(networks.last.signalPercent, 10);
  });

  test('connects the device to a network and reports failures', () async {
    var connectReply = 'WIFI OK 192.168.1.20';
    final link = FakeSerialLink()
      ..replyTo = (line) {
        if (line.startsWith('WIFI SSID ')) return ['WIFI SSID OK'];
        if (line.startsWith('WIFI PASS')) return ['WIFI PASS OK'];
        if (line == 'WIFI CONNECT') return ['WIFI CONNECTING', connectReply];
        return [];
      };
    final hub = UsbSensorHub(link: link);
    await hub.connect();

    expect((await hub.connectWifi('Home WiFi', 's3cret pw')).ok, isTrue);
    expect(link.written, [
      'WIFI SSID Home WiFi',
      'WIFI PASS s3cret pw',
      'WIFI CONNECT',
    ]);

    connectReply = 'WIFI FAIL wrong password or weak signal';
    link.written.clear();
    final failed = await hub.connectWifi('Cafe', '');
    expect(failed.ok, isFalse);
    expect(failed.reason, 'wrong password or weak signal');
    expect(link.written[1], 'WIFI PASS'); // open network
  });

  test('unpairing fails when the device is not connected', () async {
    final link = FakeSerialLink();
    final hub = UsbSensorHub(link: link);
    expect(await hub.sendUnpair(), isFalse);
    expect(link.written, isEmpty);
  });
}
