import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/free_ammonia.dart';
import '../../models/metric_type.dart';
import '../../models/pond.dart';
import '../../models/sensor_reading.dart';
import 'sensor_line_parser.dart';
import 'serial_link.dart';

enum UsbSensorStatus {
  /// This browser/platform can't reach USB devices.
  unsupported,
  disconnected,
  connecting,

  /// Port open, but no reading with every metric has arrived yet.
  waiting,

  /// Receiving complete readings.
  live,
}

/// A WiFi network the device can see (its `WIFI NET` line).
class WifiNetwork {
  const WifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.secured,
  });

  final String ssid;

  /// Signal strength in dBm (about -30 excellent, -90 barely usable).
  final int rssi;
  final bool secured;

  /// Signal strength as 0-100 %.
  int get signalPercent => (2 * (rssi + 100)).clamp(0, 100);

  static final _line = RegExp(r'^WIFI NET (-?\d+) (open|secured) (.+)$');

  /// Parses `WIFI NET <rssi> <open|secured> <ssid>`, or null for other lines.
  static WifiNetwork? parse(String line) {
    final match = _line.firstMatch(line);
    if (match == null) return null;
    return WifiNetwork(
      ssid: match.group(3)!,
      rssi: int.parse(match.group(1)!),
      secured: match.group(2) == 'secured',
    );
  }
}

/// How [UsbSensorHub.connectWifi] went.
class WifiConnectResult {
  const WifiConnectResult._({required this.ok, this.reason});

  /// The device didn't take the network name or password ([reply] is its
  /// error line, or null if it didn't answer at all).
  const WifiConnectResult._noAnswer(String? reply)
    : ok = false,
      reason = reply == null ? null : 'the device rejected the network details';

  final bool ok;

  /// Why it failed, from the device (e.g. "wrong password", "network not
  /// found", "signal too weak"; see the firmware's wifiFailText()).
  /// Null when the device didn't answer.
  final String? reason;
}

/// The IsdaSafe device plugged into this laptop over USB, and the readings
/// it has sent this session.
///
/// App-wide singleton: the add-pond flow connects it, then links it to the
/// new pond; from then on that pond's dashboard shows the device's real
/// readings (see [liveSnapshotFor]) instead of mock data. The link is
/// remembered, and [reconnect] reopens the port on the next visit without
/// prompting.
class UsbSensorHub extends ChangeNotifier {
  UsbSensorHub({SerialLink? link}) : _link = link ?? SerialLink() {
    _status = _link.isSupported
        ? UsbSensorStatus.disconnected
        : UsbSensorStatus.unsupported;
  }

  static UsbSensorHub instance = UsbSensorHub();

  /// The metrics a reading must include to count as complete (unlocking
  /// "Continue" when adding a pond, and going live). pH, ammonia and water
  /// temperature all come from the RS485 probe, which is left out FOR NOW
  /// while it isn't working; until it's added back, the dashboard shows "No
  /// reading yet" for those three. To require them again, set this to
  /// `MetricType.values.toSet()`.
  static const Set<MetricType> requiredMetrics = {
    MetricType.dissolvedOxygen,
    MetricType.humidity,
  };

  static const _prefsKey = 'usb_sensor_pond_id';

  /// Keeps a few hours of readings at the firmware's ~25 s test cadence.
  static const _maxHistory = 500;

  final SerialLink _link;
  StreamSubscription<String>? _sub;

  late UsbSensorStatus _status;
  String? _linkedPondId;
  Map<MetricType, double> _latest = {};
  DateTime? _latestAt;
  String? _deviceId;
  final Map<MetricType, List<SensorReading>> _history = {
    for (final type in MetricType.values) type: [],
  };

  UsbSensorStatus get status => _status;
  bool get isSupported => _status != UsbSensorStatus.unsupported;
  bool get isConnected =>
      _status == UsbSensorStatus.waiting || _status == UsbSensorStatus.live;

  /// The most recent summary line's values. During [UsbSensorStatus.waiting]
  /// this may be missing metrics whose sensor printed `nan`.
  Map<MetricType, double> get latest => _latest;
  DateTime? get latestAt => _latestAt;

  /// The connected device's chip ID (see `supabase/migrations/*_devices.sql`),
  /// or null until a reading arrives or with firmware that doesn't send one.
  String? get deviceId => _deviceId;
  bool get hasCompleteReading =>
      requiredMetrics.every((type) => _latest.containsKey(type));

  /// The pond whose dashboard shows this device's readings.
  String? get linkedPondId => _linkedPondId;

  /// Opens the browser's port chooser. Returns false if the user cancels or
  /// the port can't be opened.
  Future<bool> connect() => _open(_link.requestAndOpen);

  /// Reopens the port granted on an earlier visit, if the device is plugged
  /// in. Safe to call at startup: never prompts.
  Future<void> reconnect() async {
    if (!isSupported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _linkedPondId = prefs.getString(_prefsKey);
    } catch (_) {}
    debugPrint('[USB] reconnect: linked pond = $_linkedPondId');
    if (_linkedPondId == null || isConnected) return;
    await _open(_link.openGranted);
  }

  Future<bool> _open(Future<bool> Function() open) async {
    if (!isSupported) return false;
    await _sub?.cancel();
    _setStatus(UsbSensorStatus.connecting);
    final ok = await open();
    if (!ok) {
      debugPrint('[USB] could not open the device');
      _setStatus(UsbSensorStatus.disconnected);
      return false;
    }
    _latest = {};
    _latestAt = null;
    _deviceId = null;
    _setStatus(UsbSensorStatus.waiting);
    _sub = _link.lines.listen(
      _onLine,
      onDone: () {
        debugPrint('[USB] connection closed (unplugged or port closed)');
        _setStatus(UsbSensorStatus.disconnected);
      },
    );
    return true;
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _link.close();
    if (isSupported) _setStatus(UsbSensorStatus.disconnected);
  }

  /// Makes [pondId]'s dashboard show this device's readings.
  Future<void> linkTo(String pondId) async {
    debugPrint('[USB] linked to pond $pondId');
    _linkedPondId = pondId;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, pondId);
    } catch (_) {}
  }

  /// Forgets the pond link on this browser (after removing the device).
  Future<void> unlink() async {
    debugPrint('[USB] unlinked');
    _linkedPondId = null;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  /// How long the device gets to answer a command. The firmware checks for
  /// commands between readings, so the first answer after it boots (WiFi +
  /// sensor checks) can take a while.
  static const commandTimeout = Duration(seconds: 60);

  Completer<bool>? _pendingCommand;
  String? _pendingOk;
  String? _pendingError;

  /// Asks the device to forget its token (`UNPAIR`). Best effort: the token
  /// is already revoked server-side by then.
  Future<bool> sendUnpair() =>
      _command('UNPAIR', ok: 'UNPAIRED OK', error: 'UNPAIR ERROR');

  Future<bool> _command(
    String line, {
    required String ok,
    required String error,
  }) async {
    if (!isConnected) return false;
    _pendingCommand?.complete(false);
    final completer = _pendingCommand = Completer<bool>();
    _pendingOk = ok;
    _pendingError = error;
    // Don't log the token.
    debugPrint('[USB] >> ${line.split(' ').first}');
    if (!await _link.writeLine(line)) {
      _pendingCommand = null;
      return false;
    }
    final result = await completer.future.timeout(
      commandTimeout,
      onTimeout: () {
        debugPrint('[USB] no answer to ${line.split(' ').first}');
        return false;
      },
    );
    if (identical(_pendingCommand, completer)) _pendingCommand = null;
    return result;
  }

  /// Sees every line while a [_request] is waiting for its answer.
  void Function(String line)? _lineTap;

  /// Sends [line] and returns the first reply [isAnswer] accepts, or null if
  /// the port isn't open or the device doesn't answer in time. [onLine] sees
  /// every line until then (e.g. to collect a list).
  Future<String?> _request(
    String line, {
    required bool Function(String reply) isAnswer,
    void Function(String reply)? onLine,
  }) async {
    if (!isConnected) return null;
    final answer = Completer<String?>();
    final tap = _lineTap = (reply) {
      onLine?.call(reply);
      if (!answer.isCompleted && isAnswer(reply)) answer.complete(reply);
    };
    // Only the first two words: never log a WiFi password.
    debugPrint('[USB] >> ${line.split(' ').take(2).join(' ')}');
    try {
      if (!await _link.writeLine(line)) return null;
      return await answer.future.timeout(commandTimeout, onTimeout: () => null);
    } finally {
      if (identical(_lineTap, tap)) _lineTap = null;
    }
  }

  /// The WiFi networks the device can see, strongest first, or null if it
  /// didn't answer (not plugged in, or firmware without WiFi setup).
  Future<List<WifiNetwork>?> scanWifi() async {
    final networks = <WifiNetwork>[];
    final done = await _request(
      'WIFI SCAN',
      isAnswer: (reply) => reply.startsWith('WIFI SCAN DONE'),
      onLine: (reply) {
        final network = WifiNetwork.parse(reply);
        if (network != null) networks.add(network);
      },
    );
    return done == null ? null : networks;
  }

  /// Has the device join [ssid] and, once it has connected, keep it as its
  /// network. Leave [password] empty for an open network.
  Future<WifiConnectResult> connectWifi(String ssid, String password) async {
    final name = await _request(
      'WIFI SSID $ssid',
      isAnswer: (reply) => reply.startsWith('WIFI SSID '),
    );
    if (name != 'WIFI SSID OK') return WifiConnectResult._noAnswer(name);
    final pass = await _request(
      password.isEmpty ? 'WIFI PASS' : 'WIFI PASS $password',
      isAnswer: (reply) => reply.startsWith('WIFI PASS '),
    );
    if (pass != 'WIFI PASS OK') return WifiConnectResult._noAnswer(pass);
    final result = await _request(
      'WIFI CONNECT',
      isAnswer: (reply) =>
          reply.startsWith('WIFI OK') || reply.startsWith('WIFI FAIL'),
    );
    if (result == null) return const WifiConnectResult._(ok: false);
    return result.startsWith('WIFI OK')
        ? const WifiConnectResult._(ok: true)
        : WifiConnectResult._(ok: false, reason: result.substring(9).trim());
  }

  void _onLine(String line) {
    _lineTap?.call(line.trim());
    final pending = _pendingCommand;
    if (pending != null && !pending.isCompleted) {
      final trimmed = line.trim();
      if (trimmed == _pendingOk) pending.complete(true);
      if (trimmed.startsWith(_pendingError!)) pending.complete(false);
    }
    debugPrint('[USB] << $line');
    final parsed = parseSensorLine(line);
    if (parsed == null) return; // Not a reading (WiFi/debug output, ...).
    // Free ammonia is worked out the same way as for uploaded readings.
    final values = withFreeAmmonia(parsed.values);
    final missing = [
      for (final type in requiredMetrics)
        if (!values.containsKey(type)) type.name,
    ];
    debugPrint(
      '[USB] parsed: ${{for (final e in values.entries) e.key.name: e.value}}'
      '${missing.isEmpty ? '' : '  missing: $missing'}'
      '  id: ${parsed.deviceId ?? 'none'}',
    );
    final now = DateTime.now();
    _deviceId = parsed.deviceId ?? _deviceId;
    _latest = values;
    _latestAt = now;
    if (hasCompleteReading) {
      for (final entry in values.entries) {
        final list = _history[entry.key]!
          ..add(
            SensorReading(type: entry.key, value: entry.value, timestamp: now),
          );
        if (list.length > _maxHistory) list.removeAt(0);
      }
      if (_status != UsbSensorStatus.live) {
        debugPrint('[USB] status: ${_status.name} -> live');
      }
      _status = UsbSensorStatus.live;
    } else {
      _status = UsbSensorStatus.waiting;
    }
    notifyListeners();
  }

  void _setStatus(UsbSensorStatus status) {
    if (_status == status) return;
    debugPrint('[USB] status: ${_status.name} -> ${status.name}');
    _status = status;
    notifyListeners();
  }

  /// Whether the device has sent [type] over USB this session.
  bool isLive(MetricType type) => _history[type]!.isNotEmpty;

  /// [pond]'s readings from the device, or null when [pond] isn't the
  /// linked pond or no complete reading has arrived this session. Metrics
  /// the device hasn't sent over USB are taken from [fallback] (its uploaded
  /// readings) when it has them, and left out otherwise. Kept after
  /// unplugging, so the dashboard keeps showing the last real values.
  PondSnapshot? liveSnapshotFor(Pond pond, {PondSnapshot? fallback}) {
    if (pond.id != _linkedPondId) return null;
    if (!requiredMetrics.every(isLive)) return null;

    return PondSnapshot(
      pond: pond,
      readings: {
        for (final type in MetricType.values)
          if (isLive(type))
            type: _history[type]!.last
          else
            type: ?fallback?.readings[type],
      },
      history: {
        for (final type in MetricType.values)
          if (isLive(type))
            // Trend widgets need two points to draw a line.
            type: _history[type]!.length == 1
                ? [_history[type]!.first, _history[type]!.first]
                : List.unmodifiable(_history[type]!)
          else
            type: ?fallback?.history[type],
      },
    );
  }
}
