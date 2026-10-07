import 'dart:typed_data';

/// How a pond's existence is established when it is added.
enum VerificationMethod {
  /// The pinned spot is analysed on Google Maps satellite imagery.
  satellite,

  /// "In-house pond": not visible from above (covered, indoor, tank), so the
  /// owner supplies a photo instead.
  photo;

  /// Value stored in `ponds.verification_method`.
  String get wireName => name;

  static VerificationMethod? fromWire(Object? value) {
    for (final method in values) {
      if (method.wireName == value) return method;
    }
    return null;
  }
}

/// Photos required when buildings hide a pond from the satellite check. The
/// `verify-pond` function enforces the same limits.
const kMinEvidencePhotos = 3;
const kMaxEvidencePhotos = 6;

/// Where a pond is in the (background) verification process. Only the
/// `verify-pond` edge function sets this; the app just displays it.
enum VerificationStatus {
  pending('pending'),
  verified('verified'),
  rejected('rejected'),

  /// The check itself couldn't finish (technical problem) — can be retried.
  error('error'),

  /// Satellite imagery shows buildings over the pin, so the pond may be hidden:
  /// the owner must send [kMinEvidencePhotos]+ photos to compare with it.
  needsPhotos('needs_photos');

  const VerificationStatus(this.wireName);

  /// Value stored in `ponds.verification_status`.
  final String wireName;

  /// Ponds from before verification existed have no stored status and count as
  /// verified.
  static VerificationStatus fromWire(Object? value) {
    for (final status in values) {
      if (status.wireName == value) return status;
    }
    return VerificationStatus.verified;
  }
}

/// A photo picked for in-house verification.
class PondPhoto {
  const PondPhoto({required this.bytes, required this.mediaType});

  final Uint8List bytes;

  /// e.g. `image/jpeg`.
  final String mediaType;
}

/// What the add-pond dialog hands back alongside the name and coordinates: how
/// the pond is to be verified and, for in-house ponds, the photo to upload.
class PondVerification {
  const PondVerification({
    required this.method,
    this.photo,
    this.evidencePhotos = const [],
  });

  final VerificationMethod method;

  /// The single photo of an in-house pond.
  final PondPhoto? photo;

  /// Photos (at least [kMinEvidencePhotos]) sent up front with a satellite-
  /// verified pond, for the server to compare with the satellite image if
  /// buildings turn out to hide the pond. Empty if the user added fewer.
  final List<PondPhoto> evidencePhotos;
}
