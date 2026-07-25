class Pond {
  Pond({required this.id, required this.name, this.latitude, this.longitude, List<String>? speciesNames})
      : speciesNames = speciesNames ?? [],
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
  /// shown on the pond's dashboard; unrelated to SuggestionEngine's
  /// water-quality-based "suitable species" matches.
  List<String> speciesNames;

  /// Stable per-pond seed used to derive consistent mock sensor baselines.
  final int seed;

  bool get hasLocation => latitude != null && longitude != null;
}
