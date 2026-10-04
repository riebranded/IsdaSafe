import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/models/pond_verification.dart';
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

  test(
    'addPond adds the pond as pending, hidden from ponds, and notifies',
    () async {
      final provider = PondProvider(repository: FakePondRepository());
      await flush();
      var notified = false;
      provider.addListener(() => notified = true);

      final pond = await provider.addPond(
        'Pond D',
        latitude: 14.35,
        longitude: 121.25,
      );

      expect(pond, isNotNull);
      // Not verified yet, so it isn't on the dashboard...
      expect(provider.ponds.length, 3);
      expect(provider.ponds.any((p) => p.name == 'Pond D'), isFalse);
      // ...but it's tracked, waiting for its result.
      expect(provider.pendingPonds.single.name, 'Pond D');
      expect(provider.pendingPonds.single.latitude, 14.35);
      expect(provider.pendingPonds.single.longitude, 121.25);
      expect(notified, isTrue);
    },
  );

  test('addPond ignores blank names', () async {
    final provider = PondProvider(repository: FakePondRepository());
    await flush();

    final pond = await provider.addPond(
      '   ',
      latitude: 14.35,
      longitude: 121.25,
    );

    expect(pond, isNull);
    expect(provider.ponds.length, 3);
  });

  test(
    'addPond returns null and leaves the list untouched when the write fails',
    () async {
      final repository = FakePondRepository()..failNextWrite = true;
      final provider = PondProvider(repository: repository);
      await flush();

      final pond = await provider.addPond(
        'Pond D',
        latitude: 14.35,
        longitude: 121.25,
      );

      expect(pond, isNull);
      expect(provider.ponds.length, 3);
    },
  );

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

  test(
    'renamePond rolls back and returns false when the write fails',
    () async {
      final repository = FakePondRepository();
      final provider = PondProvider(repository: repository);
      await flush();

      final id = provider.ponds.first.id;
      final originalName = provider.ponds.first.name;
      repository.failNextWrite = true;
      final ok = await provider.renamePond(id, 'Renamed Pond');

      expect(ok, isFalse);
      expect(provider.ponds.first.name, originalName);
    },
  );

  test(
    'setSpecies replaces the matching pond\'s species and notifies listeners',
    () async {
      final provider = PondProvider(repository: FakePondRepository());
      await flush();
      var notified = false;
      provider.addListener(() => notified = true);

      final id = provider.ponds.first.id;
      final ok = await provider.setSpecies(id, ['Tilapia', 'Milkfish']);

      expect(ok, isTrue);
      expect(provider.ponds.first.speciesNames, ['Tilapia', 'Milkfish']);
      expect(notified, isTrue);
    },
  );

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

  test(
    'addPond saves the pond as pending and requests background verification',
    () async {
      final repository = FakePondRepository();
      final provider = PondProvider(repository: repository);
      await flush();

      final pond = await provider.addPond(
        'Pond D',
        latitude: 14.35,
        longitude: 121.25,
        verification: const PondVerification(
          method: VerificationMethod.satellite,
        ),
      );
      await flush();

      expect(pond!.verificationStatus, VerificationStatus.pending);
      expect(pond.verificationMethod, VerificationMethod.satellite);
      expect(repository.verificationRequests, [pond.id]);
    },
  );

  test(
    'a failed verification request leaves the pond saved and pending',
    () async {
      final repository = FakePondRepository()
        ..failNextVerificationRequest = true;
      final provider = PondProvider(repository: repository);
      await flush();

      final pond = await provider.addPond(
        'Pond D',
        latitude: 14.35,
        longitude: 121.25,
      );
      await flush();

      expect(pond, isNotNull);
      expect(
        provider.pendingPonds.single.verificationStatus,
        VerificationStatus.pending,
      );
      expect(repository.verificationRequests, isEmpty);
    },
  );

  test('retryVerification re-sends the request for a pending pond', () async {
    final repository = FakePondRepository()..failNextVerificationRequest = true;
    final provider = PondProvider(repository: repository);
    await flush();
    final pond = (await provider.addPond(
      'Pond D',
      latitude: 14.35,
      longitude: 121.25,
    ))!;
    await flush();
    expect(repository.verificationRequests, isEmpty);

    final ok = await provider.retryVerification(pond.id);

    expect(ok, isTrue);
    expect(repository.verificationRequests, [pond.id]);
  });

  test(
    'only verified ponds are exposed; pending and failed are listed apart',
    () async {
      final provider = PondProvider(
        repository: FakePondRepository(
          seed: [
            Pond(id: 'ok', name: 'Verified'),
            Pond(
              id: 'wait',
              name: 'Waiting',
              verificationStatus: VerificationStatus.pending,
            ),
            Pond(
              id: 'bad',
              name: 'Rejected',
              verificationStatus: VerificationStatus.rejected,
            ),
            Pond(
              id: 'err',
              name: 'Errored',
              verificationStatus: VerificationStatus.error,
            ),
          ],
        ),
      );
      await flush();

      expect(provider.ponds.map((p) => p.id), ['ok']);
      expect(provider.pendingPonds.map((p) => p.id), ['wait']);
      expect(provider.failedPonds.map((p) => p.id), ['err']);
    },
  );

  test('a pond appears once a refresh finds it verified', () async {
    final repository = FakePondRepository(
      seed: [
        Pond(
          id: 'wait',
          name: 'Waiting',
          verificationStatus: VerificationStatus.pending,
        ),
      ],
    );
    final provider = PondProvider(repository: repository);
    await flush();
    expect(provider.ponds, isEmpty);

    repository
        .fetchPonds('test-user')
        .then(
          (list) =>
              list.single.verificationStatus = VerificationStatus.verified,
        );
    await flush();
    await provider.refresh();

    expect(provider.ponds.map((p) => p.id), ['wait']);
    expect(provider.pendingPonds, isEmpty);
  });

  test('legacy ponds count as verified', () async {
    final provider = PondProvider(repository: FakePondRepository());
    await flush();

    expect(provider.ponds.first.isVerified, isTrue);
  });

  group('photos for ponds hidden by buildings', () {
    PondPhoto photo() => PondPhoto(
      bytes: Uint8List.fromList(const [1, 2, 3]),
      mediaType: 'image/jpeg',
    );

    test(
      'needs-photos ponds stay off the dashboard and are listed apart',
      () async {
        final provider = PondProvider(
          repository: FakePondRepository(
            seed: [
              Pond(id: 'ok', name: 'Verified'),
              Pond(
                id: 'bld',
                name: 'Under a roof',
                verificationStatus: VerificationStatus.needsPhotos,
              ),
            ],
          ),
        );
        await flush();

        expect(provider.ponds.map((p) => p.id), ['ok']);
        expect(provider.needsPhotosPonds.map((p) => p.id), ['bld']);
        expect(provider.pendingPonds, isEmpty);
      },
    );

    test(
      'submitting 3 photos uploads them, requests verification and goes pending',
      () async {
        final repository = FakePondRepository(
          seed: [
            Pond(
              id: 'bld',
              name: 'Under a roof',
              verificationStatus: VerificationStatus.needsPhotos,
            ),
          ],
        );
        final provider = PondProvider(repository: repository);
        await flush();

        final ok = await provider.submitEvidencePhotos('bld', [
          photo(),
          photo(),
          photo(),
        ]);

        expect(ok, isTrue);
        expect(repository.evidenceRequests['bld'], hasLength(3));
        expect(
          repository.evidenceRequests['bld']!.first,
          startsWith('test-user/bld/'),
        );
        expect(provider.needsPhotosPonds, isEmpty);
        expect(provider.pendingPonds.single.id, 'bld');
      },
    );

    test(
      'fewer than the required photos are refused without uploading',
      () async {
        final repository = FakePondRepository(
          seed: [
            Pond(
              id: 'bld',
              name: 'Under a roof',
              verificationStatus: VerificationStatus.needsPhotos,
            ),
          ],
        );
        final provider = PondProvider(repository: repository);
        await flush();

        expect(
          await provider.submitEvidencePhotos('bld', [photo(), photo()]),
          isFalse,
        );
        expect(repository.evidenceRequests, isEmpty);
        expect(provider.needsPhotosPonds.single.id, 'bld');
      },
    );

    test('a failed upload leaves the pond waiting for photos', () async {
      final repository = FakePondRepository(
        seed: [
          Pond(
            id: 'bld',
            name: 'Under a roof',
            verificationStatus: VerificationStatus.needsPhotos,
          ),
        ],
      )..failNextEvidenceUpload = true;
      final provider = PondProvider(repository: repository);
      await flush();

      expect(
        await provider.submitEvidencePhotos('bld', [photo(), photo(), photo()]),
        isFalse,
      );
      expect(provider.needsPhotosPonds.single.id, 'bld');
      expect(repository.evidenceRequests, isEmpty);
    });
  });

  test(
    'needs_photos maps to its own status and unknown values count as verified',
    () {
      expect(
        VerificationStatus.fromWire('needs_photos'),
        VerificationStatus.needsPhotos,
      );
      expect(VerificationStatus.needsPhotos.wireName, 'needs_photos');
      expect(VerificationStatus.fromWire(null), VerificationStatus.verified);
    },
  );

  group('photos sent up front with a new pond', () {
    PondPhoto photo() => PondPhoto(bytes: Uint8List.fromList(const [1, 2, 3]), mediaType: 'image/jpeg');

    test('3+ photos are uploaded and sent with the first verification request', () async {
      final repository = FakePondRepository();
      final provider = PondProvider(repository: repository);
      await flush();

      final pond = await provider.addPond(
        'Roof pond',
        latitude: 14.35,
        longitude: 121.25,
        verification: PondVerification(
          method: VerificationMethod.satellite,
          evidencePhotos: [photo(), photo(), photo()],
        ),
      );
      await flush();

      expect(repository.evidenceRequests[pond!.id], hasLength(3));
      expect(repository.evidenceRequests[pond.id]!.first, startsWith('test-user/${pond.id}/'));
      // One request carrying the photos, not a second plain one.
      expect(repository.verificationRequests, isEmpty);
    });

    test('fewer than 3 photos are ignored: a plain verification request is sent', () async {
      final repository = FakePondRepository();
      final provider = PondProvider(repository: repository);
      await flush();

      final pond = await provider.addPond(
        'Roof pond',
        latitude: 14.35,
        longitude: 121.25,
        verification: PondVerification(
          method: VerificationMethod.satellite,
          evidencePhotos: [photo(), photo()],
        ),
      );
      await flush();

      expect(repository.evidenceRequests, isEmpty);
      expect(repository.verificationRequests, [pond!.id]);
    });

    test('if the photos cannot be uploaded, verification still starts without them', () async {
      final repository = FakePondRepository()..failNextEvidenceUpload = true;
      final provider = PondProvider(repository: repository);
      await flush();

      final pond = await provider.addPond(
        'Roof pond',
        latitude: 14.35,
        longitude: 121.25,
        verification: PondVerification(
          method: VerificationMethod.satellite,
          evidencePhotos: [photo(), photo(), photo()],
        ),
      );
      await flush();

      expect(pond, isNotNull);
      expect(repository.evidenceRequests, isEmpty);
      expect(repository.verificationRequests, [pond!.id]);
    });
  });
}
