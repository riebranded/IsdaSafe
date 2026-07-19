import '../models/fish_species.dart';

/// Mock catalog of common Philippine pond/aquaculture species with
/// representative optimal water-quality ranges.
class FishSpeciesCatalog {
  static const List<FishSpecies> species = [
    FishSpecies(
      name: 'Tilapia',
      localName: 'Tilapia',
      tempRange: MetricRange(25, 32),
      phRange: MetricRange(6.5, 9.0),
      doRange: MetricRange(3, 10),
      ammoniaRange: MetricRange(0, 0.05),
    ),
    FishSpecies(
      name: 'Milkfish',
      localName: 'Bangus',
      tempRange: MetricRange(24, 31),
      phRange: MetricRange(7.5, 8.5),
      doRange: MetricRange(4, 10),
      ammoniaRange: MetricRange(0, 0.03),
    ),
    FishSpecies(
      name: 'Catfish',
      localName: 'Hito',
      tempRange: MetricRange(25, 30),
      phRange: MetricRange(6.5, 8.0),
      doRange: MetricRange(2, 10),
      ammoniaRange: MetricRange(0, 0.1),
    ),
    FishSpecies(
      name: 'Tiger Shrimp',
      localName: 'Sugpo',
      tempRange: MetricRange(26, 31),
      phRange: MetricRange(7.5, 8.5),
      doRange: MetricRange(4, 8),
      ammoniaRange: MetricRange(0, 0.02),
    ),
  ];
}
