import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/providers/pond_provider.dart';

void main() {
  test('seeds with 3 mock ponds', () {
    final provider = PondProvider();
    expect(provider.ponds.length, 3);
  });

  test('addPond appends a pond and notifies listeners', () {
    final provider = PondProvider();
    var notified = false;
    provider.addListener(() => notified = true);

    provider.addPond('Pond D', latitude: 14.35, longitude: 121.25);

    expect(provider.ponds.length, 4);
    expect(provider.ponds.last.name, 'Pond D');
    expect(provider.ponds.last.latitude, 14.35);
    expect(provider.ponds.last.longitude, 121.25);
    expect(notified, isTrue);
  });

  test('addPond ignores blank names', () {
    final provider = PondProvider();
    provider.addPond('   ', latitude: 14.35, longitude: 121.25);
    expect(provider.ponds.length, 3);
  });

  test('renamePond updates the matching pond and notifies listeners', () {
    final provider = PondProvider();
    var notified = false;
    provider.addListener(() => notified = true);

    final id = provider.ponds.first.id;
    provider.renamePond(id, 'Renamed Pond');

    expect(provider.ponds.first.name, 'Renamed Pond');
    expect(notified, isTrue);
  });

  test('removePond removes the matching pond and notifies listeners', () {
    final provider = PondProvider();
    var notified = false;
    provider.addListener(() => notified = true);

    final id = provider.ponds.first.id;
    provider.removePond(id);

    expect(provider.ponds.length, 2);
    expect(provider.ponds.any((p) => p.id == id), isFalse);
    expect(notified, isTrue);
  });
}
