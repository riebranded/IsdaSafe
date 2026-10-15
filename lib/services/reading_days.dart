import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateUtils;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The days a pond has readings (`pond_reading_days`), so a custom timeframe
/// can only be picked from days that have data. [deviceId] limits it to one
/// device and [completeOnly] to complete readings (the Devices tab).
class ReadingDays {
  const ReadingDays._();

  /// Replaces the database call in tests.
  @visibleForTesting
  static Future<Set<DateTime>> Function(
    String pondId,
    String? deviceId,
    bool completeOnly,
  )?
  debugLoad;

  static Future<Set<DateTime>> load(
    String pondId, {
    String? deviceId,
    bool completeOnly = false,
  }) async {
    if (debugLoad case final fake?) return fake(pondId, deviceId, completeOnly);
    final rows =
        await Supabase.instance.client.rpc(
              'pond_reading_days',
              params: {
                'p_pond_id': pondId,
                'p_device_id': ?deviceId,
                'p_complete_only': completeOnly,
                'p_utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
              },
            )
            as List<dynamic>;
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        DateUtils.dateOnly(DateTime.parse(row['day'] as String)),
    };
  }
}
