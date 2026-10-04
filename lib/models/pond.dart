import 'pond_verification.dart';

class Pond {
  Pond({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
    List<String>? speciesNames,
    this.verificationMethod,
    this.verificationStatus = VerificationStatus.verified,
    this.verificationMessage,
  }) : speciesNames = speciesNames ?? [],
       seed = id.hashCode;

  final String id;
  String name;

  /// Manually pinned on a map at creation (or later via "Edit location").
  /// Nullable so the type stays honest about ponds that somehow lack one,
  /// but in practice every pond created through the app has both set.
  double? latitude;
  double? longitude;

  /// Fish/shrimp species the user says this pond actually holds, by
  /// [FishSpecies.name] — picked at creation (or later, via "Edit species")
  /// rather than inferred from readings. Drives the feeding-time suggestions
  /// shown on the pond's dashboard; unrelated to the AI species
  /// recommendation, which is driven by live readings instead.
  List<String> speciesNames;

  /// How the pond was verified when added (null for ponds created before
  /// verification existed).
  final VerificationMethod? verificationMethod;

  /// Background verification progress; set by the server (see
  /// `verify-pond`). Ponds from before verification count as verified.
  VerificationStatus verificationStatus;

  /// Why the pond was rejected, or what went wrong (null otherwise).
  String? verificationMessage;

  /// Stable per-pond seed used to derive consistent mock sensor baselines.
  final int seed;

  bool get isVerified => verificationStatus == VerificationStatus.verified;

  bool get hasLocation => latitude != null && longitude != null;
}
