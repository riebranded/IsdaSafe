import 'dart:async';

import 'package:isdasafev2/models/metric_type.dart';
import 'package:isdasafev2/services/usb_sensor/device_registry.dart';
import 'package:isdasafev2/services/usb_sensor/pond_readings_store.dart';
import 'package:isdasafev2/services/usb_sensor/serial_link.dart';

/// A USB device that's always "plugged in": [send] emits a line as if the
/// firmware printed it. With [answersCommands], it replies to `UNPAIR` like
/// the firmware does.
class FakeSerialLink implements SerialLink {
  FakeSerialLink({
    this.isSupported = true,
    this.grantsPort = true,
    this.answersCommands = true,
  });

  @override
  final bool isSupported;
  final bool grantsPort;
  bool answersCommands;

  /// The lines the device prints in answer to a written line (other than
  /// `UNPAIR`).
  List<String> Function(String line)? replyTo;
  final written = <String>[];
  StreamController<String>? _lines;

  void send(String line) => _lines!.add(line);
  Future<void> unplug() => _lines!.close();

  Future<bool> _open() async {
    if (!grantsPort) return false;
    _lines = StreamController<String>();
    return true;
  }

  @override
  Future<bool> requestAndOpen() => _open();

  @override
  Future<bool> openGranted() => _open();

  @override
  Stream<String> get lines => _lines!.stream;

  @override
  Future<bool> writeLine(String line) async {
    if (_lines == null) return false;
    written.add(line);
    if (answersCommands) {
      if (line == 'UNPAIR') scheduleMicrotask(() => send('UNPAIRED OK'));
      final replies = replyTo?.call(line) ?? const [];
      scheduleMicrotask(() => replies.forEach(send));
    }
    return true;
  }

  @override
  Future<void> close() async => _lines?.close();
}

class FakeDeviceRegistry implements DeviceRegistry {
  FakeDeviceRegistry({this.inUsePondName});

  /// For [ClaimStatus.inUse].
  String? inUsePondName;

  final unpairs = <String>[];
  final devicesByPond = <String, String>{};

  /// What [claim] answers.
  ClaimStatus claimStatus = ClaimStatus.claimed;
  bool transferPending = false;

  /// What [requestTransfer] answers.
  TransferRequestStatus transferStatus = TransferRequestStatus.requested;

  /// (device, code, pond) per [claim] call.
  final claims = <(String, String, String)>[];
  final transferRequestsSent = <String>[];
  final pendingRequests = <TransferRequest>[];

  /// (request id, approved) per [respondToTransfer] call.
  final responses = <(String, bool)>[];

  @override
  Future<ClaimResult> claim(
    String deviceId,
    String claimCode,
    String pondId,
  ) async {
    claims.add((deviceId, claimCode, pondId));
    if (claimStatus == ClaimStatus.claimed) devicesByPond[pondId] = deviceId;
    return (
      status: claimStatus,
      pondName: claimStatus == ClaimStatus.inUse ? inUsePondName : null,
      transferPending: transferPending,
    );
  }

  @override
  Future<TransferRequestStatus> requestTransfer(
    String deviceId,
    String claimCode,
  ) async {
    transferRequestsSent.add(deviceId);
    return transferStatus;
  }

  @override
  Future<List<TransferRequest>> pendingTransferRequests() async => [
    ...pendingRequests,
  ];

  @override
  Future<bool> respondToTransfer(
    String requestId, {
    required bool approve,
  }) async {
    responses.add((requestId, approve));
    pendingRequests.removeWhere((r) => r.id == requestId);
    return true;
  }

  @override
  Future<bool> assignPond(String deviceId, String pondId) async {
    if (devicesByPond.containsKey(pondId)) return false;
    devicesByPond[pondId] = deviceId;
    return true;
  }

  @override
  Future<bool> unpair(String deviceId) async {
    unpairs.add(deviceId);
    devicesByPond.removeWhere((_, id) => id == deviceId);
    return true;
  }

  @override
  Future<String?> deviceForPond(String pondId) async => devicesByPond[pondId];

  /// Devices asked to open their WiFi setup hotspot.
  final wifiSetupRequests = <String>[];

  /// What [wifiStatus] answers.
  DeviceWifiStatus? wifi;

  @override
  Future<DeviceWifiStatus?> wifiStatus(String deviceId) async => wifi;

  @override
  Future<bool> requestWifiSetup(String deviceId) async {
    wifiSetupRequests.add(deviceId);
    return true;
  }
}

/// Paired devices come from [registry] (so pairing in a test shows up), and
/// every paired pond has one uploaded reading matching [kSampleSensorLine].
class FakePondReadingsSource implements PondReadingsSource {
  FakePondReadingsSource(this.registry);

  final FakeDeviceRegistry registry;

  @override
  Future<Map<String, String>> devicesByPond() async => {
    ...registry.devicesByPond,
  };

  @override
  Future<List<StoredReading>> recentReadings(
    String pondId, {
    int limit = 200,
  }) async => [
    (
      time: DateTime.now(),
      values: {
        MetricType.dissolvedOxygen: 6.12,
        MetricType.ph: 7.05,
        MetricType.ammonia: 0.03,
        MetricType.temperature: 27.4,
        MetricType.humidity: 78,
      },
    ),
  ];
}

const kSampleSensorLine =
    'DO=6.12 mg/L  pH=7.05  NH3=0.03 mg/L  WaterT=27.4C  AirT=29.1C  Hum=78%  ID=A1B2C3D4E5F6';
