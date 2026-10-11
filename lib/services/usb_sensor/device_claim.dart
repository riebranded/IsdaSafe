/// What a device's QR label holds: its ID and claim code (see
/// `tools/provision_device.py` and `supabase/migrations/*_device_qr_claim.sql`).
typedef ClaimPayload = ({String deviceId, String code});

final _deviceIdPattern = RegExp(r'^[0-9A-F]{12}$');

/// The claim code as the database compares it: letters and digits only,
/// upper case (labels print it as `ABCD-EFGH-JKMN`).
String normalizeClaimCode(String code) =>
    code.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();

/// Builds a payload from a typed-in device ID and claim code, or null when
/// either can't be right.
ClaimPayload? claimPayloadFrom(String deviceId, String code) {
  final id = deviceId.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
  final normalized = normalizeClaimCode(code);
  if (!_deviceIdPattern.hasMatch(id) || normalized.length < 8) return null;
  return (deviceId: id, code: normalized);
}

/// Reads a scanned label: `https://<site>/?claim=<ID>.<CODE>`, or just
/// `<ID>.<CODE>`. Null for anything else (e.g. some other QR code).
ClaimPayload? parseClaimPayload(String raw) {
  final text = raw.trim();
  final uri = Uri.tryParse(text);
  final value = uri?.queryParameters['claim'] ?? text;
  final dot = value.indexOf('.');
  if (dot <= 0) return null;
  return claimPayloadFrom(value.substring(0, dot), value.substring(dot + 1));
}

/// A label scanned with the phone's own camera opens the website with
/// `?claim=...`; this keeps it until the signed-in app can offer to pair the
/// device (see `AppShell`).
abstract final class PendingClaimLink {
  static ClaimPayload? _pending;

  /// Call once at startup with the page's address ([Uri.base]).
  static void captureFrom(Uri uri) {
    final claim = uri.queryParameters['claim'];
    if (claim != null) _pending = parseClaimPayload(claim);
  }

  /// The pending claim, handed out once.
  static ClaimPayload? take() {
    final pending = _pending;
    _pending = null;
    return pending;
  }
}
