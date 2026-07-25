import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/providers/pond_provider.dart';

import '../support/fake_pond_repository.dart';

void main() {
  /// [PondProvider]'s constructor kicks off its initial load but doesn't
  /// expose a way to await it directly — a zero-duration delay flushes the
  /// microtask queue, which is all [FakePondRepository]'s in-memory futures
  /// ever need to resolve.
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  test('loads the signed-in user\'s ponds on construction', () async {
    final provider = PondProvider(repository: FakePondRepository());
    await flush();

    expect(provider.ponds.length, 3);
    expect(provider.isLoading, isFalse);
  });

  test('addPond appends a pond and notifies listeners', () async {
    final provider = PondProvider(repository: FakePondRepository());
    await flush();
    var notified = false;
    provider.addListener(() => notified = true);

    final pond = await provider.addPond('Pond D', latitude: 14.35, longitude: 121.25);

    expect(pond, isNotNull);
    expect(provider.ponds.length, 4);
    expect(provider.ponds.last.name, 'Pond D');
    expect(provider.ponds.last.latitude, 14.35);
    expect(provider.ponds.last.longitude, 121.25);
    expect(notified, isTrue);
  });

  test('addPond ignores blank names', () async {
    final provider = PondProvider(repository: FakePondRepository());
    await flush();

    final pond = await provider.addPond('   ', latitude: 14.35, longitude: 121.25);

    expect(pond, isNull);
    expect(provider.ponds.length, 3);
  });

  test('addPond returns null and leaves the list untouched when the write fails', () async {
    final repository = FakePondRepository()..failNextWrite = true;
    final provider = PondProvider(repository: repository);
    await flush();

    final pond = await provider.addPond('Pond D', latitude: 14.35, longitude: 121.25);

    expect(pond, isNull);
    expect(provider.ponds.length, 3);
  });

  test('renamePond updates the matching pond and notifies listeners', () async {
    final provider = PondProvider(repository: FakePondRepository());
    await flush();
    var notified = false;
    provider.addListener(() => notified = true);

    final id = provider.ponds.first.id;
    final ok = await provider.renamePond(id, 'Renamed Pond');

    expect(ok, isTrue);
    expect(provider.ponds.first.name, 'Renamed Pond');
    expect(notified, isTrue);
  });

  test('renamePond rolls back and returns false when the write fails', () async {
    final repository = FakePondRepository();
    final provider = PondProvider(repository: repository);
    await flush();

    final id = provider.ponds.first.id;
    final originalName = provider.ponds.first.name;
    repository.failNextWrite = true;
    final ok = await provider.renamePond(id, 'Renamed Pond');

    expect(ok, isFalse);
    expect(provider.ponds.first.name, originalName);
  });

  test('setSpecies replaces the matching pond\'s species and notifies listeners', () async {
    final provider = PondProvider(repository: FakePondRepository());
    await flush();
    var notified = false;
    provider.addListener(() => notified = true);

    final id = provider.ponds.first.id;
    final ok = await provider.setSpecies(id, ['Tilapia', 'Milkfish']);

    expect(ok, isTrue);
    expect(provider.ponds.first.speciesNames, ['Tilapia', 'Milkfish']);
    expect(notified, isTrue);
  });

  test('removePond removes the matching pond and notifies listeners', () async {
    final provider = PondProvider(repository: FakePondRepository());
    await flush();
    var notified = false;
    provider.addListener(() => notified = true);

    final id = provider.ponds.first.id;
    final ok = await provider.removePond(id);

    expect(ok, isTrue);
    expect(provider.ponds.length, 2);
    expect(provider.ponds.any((p) => p.id == id), isFalse);
    expect(notified, isTrue);
  });

  test('clears its ponds when the user signs out', () async {
    final repository = FakePondRepository();
    final provider = PondProvider(repository: repository);
    await flush();
    expect(provider.ponds.length, 3);

    repository.setUserId(null);
    await flush();

    expect(provider.ponds, isEmpty);
  });
}
