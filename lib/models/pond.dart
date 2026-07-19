class Pond {
  Pond({required this.id, required this.name, this.latitude, this.longitude}) : seed = id.hashCode;

  final String id;
  String name;

  /// Manually pinned on a map at creation (or later via "Edit location").
  /// Nullable so the type stays honest about ponds that somehow lack one,
  /// but in practice every pond created through the app has both set.
  double? latitude;
  double? longitude;

  /// Stable per-pond seed used to derive consistent mock sensor baselines.
  final int seed;

  bool get hasLocation => latitude != null && longitude != null;
}
