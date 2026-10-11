import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum ClaimStatus {
  /// The device now belongs to this account and files readings under the
  /// pond.
  claimed,

  /// This account's device, but on another pond ([ClaimResult.pondName]); it
  /// must be removed from there first.
  inUse,

  /// Another account owns it; only a transfer request can change that.
  ownedByOther,

  /// The pond already has a different device.
  pondHasDevice,

  /// Wrong device ID or claim code (or the device was never provisioned).
  invalid,

  /// Too many tries in the last hour.
  rateLimited,

  /// Network/server error; try again.
  failed,
}

typedef ClaimResult = ({
  ClaimStatus status,
  String? pondName,

  /// For [ClaimStatus.ownedByOther]: this account already asked for it.
  bool transferPending,
});

enum TransferRequestStatus {
  requested,
  alreadyRequested,

  /// Nobody owns it any more: claim it instead.
  unclaimed,
  alreadyYours,
  invalid,
  rateLimited,
  failed,
}

/// Someone asking this account (the owner) to hand over a device.
typedef TransferRequest = ({String id, String deviceId, DateTime createdAt});

/// Which WiFi network a device last uploaded from, when that last changed,
/// and when it last uploaded at all (server times). [ssid] is null with
/// firmware that doesn't report it.
typedef DeviceWifiStatus = ({
  String? ssid,
  DateTime? ssidChangedAt,
  DateTime? lastSeenAt,
});

/// Device ownership in Supabase (see
/// `supabase/migrations/20261009111614_device_qr_claim.sql`). A device is
/// paired by claiming it with the code on its QR label; it then sends its own
/// secret with every reading, and the database files those readings under
/// this account only.
abstract class DeviceRegistry {
  /// App-wide registry; tests swap in a fake.
  static DeviceRegistry get instance => _instance ??= SupabaseDeviceRegistry();
  static set instance(DeviceRegistry registry) => _instance = registry;
  static DeviceRegistry? _instance;

  /// Claims a provisioned device with the claim code from its QR label and
  /// files its readings under the current user's [pondId]. No USB needed: the
  /// device already holds its own secret.
  Future<ClaimResult> claim(String deviceId, String claimCode, String pondId);

  /// Asks the owner of a device someone else has claimed to transfer it to
  /// this account (needs the label's claim code too).
  Future<TransferRequestStatus> requestTransfer(
    String deviceId,
    String claimCode,
  );

  /// Pending requests from other users for this account's devices.
  Future<List<TransferRequest>> pendingTransferRequests();

  /// Approves or declines a [TransferRequest]. Returns false on failure.
  Future<bool> respondToTransfer(String requestId, {required bool approve});

  /// Files an already-owned device without a pond (e.g. one just transferred)
  /// under [pondId]. Returns false on failure (e.g. the pond has a device).
  Future<bool> assignPond(String deviceId, String pondId);

  /// Releases [deviceId] and revokes its token. Returns false on failure.
  Future<bool> unpair(String deviceId);

  /// The ID of the device filing readings under [pondId], if any.
  Future<String?> deviceForPond(String pondId);

  /// Asks this account's online [deviceId] to open its WiFi setup hotspot;
  /// it does so after its next upload (within about a minute). Returns false
  /// on failure.
  Future<bool> requestWifiSetup(String deviceId);

  /// [deviceId]'s WiFi network and last upload, or null if it can't be
  /// loaded.
  Future<DeviceWifiStatus?> wifiStatus(String deviceId);
}

class SupabaseDeviceRegistry implements DeviceRegistry {
  SupabaseDeviceRegistry({SupabaseClient? client}) : _injected = client;

  final SupabaseClient? _injected;

  // Resolved per call (inside each method's try) so screens that use the
  // registry still build when Supabase isn't initialized, e.g. in tests.
  SupabaseClient get _client => _injected ?? Supabase.instance.client;

  @override
  Future<ClaimResult> claim(
    String deviceId,
    String claimCode,
    String pondId,
  ) async {
    ClaimResult result(
      ClaimStatus status, {
      String? pondName,
      bool transferPending = false,
    }) =>
        (status: status, pondName: pondName, transferPending: transferPending);
    try {
      final response = await _client.rpc(
        'claim_device',
        params: {
          'p_device_id': deviceId,
          'p_claim_code': claimCode,
          'p_pond_id': pondId,
        },
      );
      final map = response as Map;
      // Never log the claim code.
      debugPrint('[USB] claim_device($deviceId, $pondId) -> ${map['status']}');
      switch (map['status']) {
        case 'claimed':
          return result(ClaimStatus.claimed);
        case 'already_yours':
          // Already this account's: fine if it's on this pond; file it here
          // if it has no pond (e.g. just transferred); otherwise it's in use.
          final currentPond = map['pond_id'] as String?;
          if (currentPond == pondId) return result(ClaimStatus.claimed);
          if (currentPond != null) {
            return result(
              ClaimStatus.inUse,
              pondName: map['pond_name'] as String?,
            );
          }
          return await assignPond(deviceId, pondId)
              ? result(ClaimStatus.claimed)
              : result(ClaimStatus.pondHasDevice);
        case 'owned_by_other':
          return result(
            ClaimStatus.ownedByOther,
            transferPending: map['transfer_pending'] == true,
          );
        case 'pond_has_device':
          return result(ClaimStatus.pondHasDevice);
        case 'invalid':
          return result(ClaimStatus.invalid);
        case 'rate_limited':
          return result(ClaimStatus.rateLimited);
      }
      return result(ClaimStatus.failed);
    } catch (e) {
      debugPrint('[USB] claim_device($deviceId) failed: $e');
      return result(ClaimStatus.failed);
    }
  }

  @override
  Future<TransferRequestStatus> requestTransfer(
    String deviceId,
    String claimCode,
  ) async {
    try {
      final response = await _client.rpc(
        'request_device_transfer',
        params: {'p_device_id': deviceId, 'p_claim_code': claimCode},
      );
      final status = (response as Map)['status'];
      debugPrint('[USB] request_device_transfer($deviceId) -> $status');
      return switch (status) {
        'requested' => TransferRequestStatus.requested,
        'already_requested' => TransferRequestStatus.alreadyRequested,
        'unclaimed' => TransferRequestStatus.unclaimed,
        'already_yours' => TransferRequestStatus.alreadyYours,
        'invalid' => TransferRequestStatus.invalid,
        'rate_limited' => TransferRequestStatus.rateLimited,
        _ => TransferRequestStatus.failed,
      };
    } catch (e) {
      debugPrint('[USB] request_device_transfer($deviceId) failed: $e');
      return TransferRequestStatus.failed;
    }
  }

  @override
  Future<List<TransferRequest>> pendingTransferRequests() async {
    try {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) return const [];
      final rows = await _client
          .from('device_transfer_requests')
          .select('id, device_id, created_at')
          .eq('owner_id', uid)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      return [
        for (final row in rows)
          (
            id: row['id'] as String,
            deviceId: row['device_id'] as String,
            createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          ),
      ];
    } catch (e) {
      debugPrint('[USB] loading transfer requests failed: $e');
      return const [];
    }
  }

  @override
  Future<bool> respondToTransfer(
    String requestId, {
    required bool approve,
  }) async {
    try {
      final response = await _client.rpc(
        'respond_device_transfer',
        params: {'p_request_id': requestId, 'p_approve': approve},
      );
      debugPrint(
        '[USB] respond_device_transfer($requestId, $approve) -> '
        '${(response as Map)['status']}',
      );
      return true;
    } catch (e) {
      debugPrint('[USB] respond_device_transfer($requestId) failed: $e');
      return false;
    }
  }

  @override
  Future<bool> assignPond(String deviceId, String pondId) async {
    try {
      await _client.rpc(
        'assign_device_pond',
        params: {'p_device_id': deviceId, 'p_pond_id': pondId},
      );
      debugPrint('[USB] assign_device_pond($deviceId, $pondId) ok');
      return true;
    } catch (e) {
      debugPrint('[USB] assign_device_pond($deviceId, $pondId) failed: $e');
      return false;
    }
  }

  @override
  Future<bool> unpair(String deviceId) async {
    try {
      await _client.rpc('unpair_device', params: {'p_device_id': deviceId});
      debugPrint('[USB] unpair_device($deviceId) ok');
      return true;
    } catch (e) {
      debugPrint('[USB] unpair_device($deviceId) failed: $e');
      return false;
    }
  }

  @override
  Future<DeviceWifiStatus?> wifiStatus(String deviceId) async {
    try {
      final row = await _client
          .from('devices')
          .select('wifi_ssid, wifi_ssid_changed_at, last_seen_at')
          .eq('id', deviceId)
          .maybeSingle();
      if (row == null) return null;
      DateTime? time(Object? value) =>
          value is String ? DateTime.parse(value) : null;
      return (
        ssid: row['wifi_ssid'] as String?,
        ssidChangedAt: time(row['wifi_ssid_changed_at']),
        lastSeenAt: time(row['last_seen_at']),
      );
    } catch (e) {
      debugPrint('[USB] wifi status of $deviceId failed: $e');
      return null;
    }
  }

  @override
  Future<bool> requestWifiSetup(String deviceId) async {
    try {
      final ok = await _client.rpc(
        'request_device_wifi_setup',
        params: {'p_device_id': deviceId},
      );
      debugPrint('[USB] request_device_wifi_setup($deviceId) -> $ok');
      return ok == true;
    } catch (e) {
      debugPrint('[USB] request_device_wifi_setup($deviceId) failed: $e');
      return false;
    }
  }

  @override
  Future<String?> deviceForPond(String pondId) async {
    try {
      final row = await _client
          .from('devices')
          .select('id')
          .eq('pond_id', pondId)
          .limit(1)
          .maybeSingle();
      return row?['id'] as String?;
    } catch (e) {
      debugPrint('[USB] devices lookup for pond $pondId failed: $e');
      return null;
    }
  }
}
