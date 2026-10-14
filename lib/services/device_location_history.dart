import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One stay of a device at a pond: where it was, from when until when, and
/// how many complete readings (every sensor reported) it sent from there. A
/// pond that was moved gives a new stay at its new spot. Stays without a
/// complete reading aren't listed.
class DeviceStay {
  const DeviceStay({
    required this.id,
    required this.deviceId,
    required this.pondId,
    required this.pondName,
    required this.latitude,
    required this.longitude,
    required this.startedAt,
    required this.endedAt,
    required this.readingCount,
  });

  final int id;
  final String deviceId;
  final String? pondId;

  /// The pond's current name.
  final String? pondName;
  final double? latitude;
  final double? longitude;
  final DateTime startedAt;

  /// Null while the device is still there.
  final DateTime? endedAt;
  final int readingCount;

  bool get isCurrent => endedAt == null;
  bool get hasLocation => latitude != null && longitude != null;
}

/// Where this account's devices have been (see
/// `supabase/migrations/20261014120000_device_location_history.sql` and
/// `20261014170000_device_history_own_ponds_only.sql`). The database records
/// every stay itself, whichever way a device was paired, moved, transferred
/// or removed. Each account sees only its own ponds: a device's stays under
/// other accounts aren't listed.
abstract class DeviceLocationHistory {
  /// App-wide instance; tests swap in a fake.
  static DeviceLocationHistory get instance =>
      _instance ??= SupabaseDeviceLocationHistory();
  static set instance(DeviceLocationHistory history) => _instance = history;
  static DeviceLocationHistory? _instance;

  /// IDs of the devices with a history of pairing to this account — it had
  /// the device on one of its (still existing) ponds, which got at least one
  /// complete reading — most recently placed first, including devices that
  /// have since been removed or handed on. Only these devices' histories can
  /// be opened.
  Future<List<String>> devices();

  /// [deviceId]'s stays at this account's (existing) ponds with complete
  /// readings, newest first.
  Future<List<DeviceStay>> stays(String deviceId);
}

class SupabaseDeviceLocationHistory implements DeviceLocationHistory {
  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<List<String>> devices() async {
    final rows = await _client.rpc('device_history_devices');
    return [for (final id in rows as List) id as String];
  }

  @override
  Future<List<DeviceStay>> stays(String deviceId) async {
    final rows = await _client.rpc(
      'device_location_history',
      params: {'p_device_id': deviceId},
    );
    debugPrint('device_location_history($deviceId): ${(rows as List).length}');
    DateTime? time(Object? value) =>
        value is String ? DateTime.parse(value).toLocal() : null;
    return [
      for (final row in rows)
        DeviceStay(
          id: (row['id'] as num).toInt(),
          deviceId: deviceId,
          pondId: row['pond_id'] as String?,
          pondName: row['pond_name'] as String?,
          latitude: (row['latitude'] as num?)?.toDouble(),
          longitude: (row['longitude'] as num?)?.toDouble(),
          startedAt: time(row['started_at'])!,
          endedAt: time(row['ended_at']),
          readingCount: (row['reading_count'] as num).toInt(),
        ),
    ];
  }
}
