import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:isdasafev2/models/pond.dart';
import 'package:isdasafev2/services/usb_sensor/device_registry.dart';
import 'package:isdasafev2/widgets/qr_claim_dialog.dart';

import '../support/fake_serial_link.dart';
import '../support/qr_image.dart';

void main() {
  final pond = Pond(id: 'pond-a', name: 'Pond A');
  const label = (deviceId: '6C383B124B00', code: 'ABCD2345EFGH');

  /// Opens the dialog for a label that was already scanned (so the camera,
  /// which tests don't have, never starts) and records what it returns.
  Future<List<String?>> open(
    WidgetTester tester,
    FakeDeviceRegistry registry,
  ) async {
    final results = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => results.add(
                await showQrClaimDialog(
                  context,
                  pond: pond,
                  initial: label,
                  registry: registry,
                ),
              ),
              child: const Text('Pair'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pair'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('a scanned label pairs the device with the pond', (tester) async {
    final registry = FakeDeviceRegistry();
    final results = await open(tester, registry);

    expect(registry.claims, [('6C383B124B00', 'ABCD2345EFGH', 'pond-a')]);
    expect(results, ['6C383B124B00']);
  });

  testWidgets('someone else\'s device can be requested from its owner', (
    tester,
  ) async {
    final registry = FakeDeviceRegistry()
      ..claimStatus = ClaimStatus.ownedByOther;
    final results = await open(tester, registry);

    expect(find.text('This device belongs to someone else'), findsOneWidget);
    await tester.tap(find.text('Request transfer'));
    await tester.pumpAndSettle();

    expect(registry.transferRequestsSent, ['6C383B124B00']);
    expect(find.text('Transfer requested'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  testWidgets('a wrong code says so and nothing is paired', (tester) async {
    final registry = FakeDeviceRegistry()..claimStatus = ClaimStatus.invalid;
    await open(tester, registry);

    expect(find.text("Couldn't pair the device"), findsOneWidget);
    expect(find.textContaining("doesn't match"), findsOneWidget);
    expect(registry.devicesByPond, isEmpty);
  });

  group('uploading a photo of the label', () {
    /// Opens the scan step with [photo] as the picked image, taps "Upload a
    /// photo of the label", and waits for the photo to be read (that runs
    /// outside the test's fake clock).
    Future<List<String?>> upload(
      WidgetTester tester,
      FakeDeviceRegistry registry,
      Uint8List? photo,
    ) async {
      final results = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => results.add(
                  await showQrClaimDialog(
                    context,
                    pond: pond,
                    registry: registry,
                    pickImage: () async => photo,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Below the camera view: the dialog scrolls on short screens.
      await tester.ensureVisible(find.text('Upload a photo of the label'));
      await tester.pump();
      await tester.tap(find.text('Upload a photo of the label'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return results;
    }

    testWidgets('pairs the device in the photo', (tester) async {
      final registry = FakeDeviceRegistry();
      final results = await upload(
        tester,
        registry,
        qrImage('https://isdasafe.vercel.app/?claim=6C383B124B00.ABCD2345EFGH'),
      );

      expect(registry.claims, [('6C383B124B00', 'ABCD2345EFGH', 'pond-a')]);
      expect(results, ['6C383B124B00']);
    });

    testWidgets('a photo without a QR code asks for a better one', (
      tester,
    ) async {
      final registry = FakeDeviceRegistry();
      await upload(tester, registry, blankImage());

      expect(find.textContaining("Couldn't find a QR code"), findsOneWidget);
      expect(registry.claims, isEmpty);
    });

    testWidgets('some other QR code is not taken for a label', (tester) async {
      final registry = FakeDeviceRegistry();
      await upload(tester, registry, qrImage('https://example.com/menu'));

      expect(find.textContaining("isn't an IsdaSafe label"), findsOneWidget);
      expect(registry.claims, isEmpty);
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final registry = FakeDeviceRegistry();
      await upload(tester, registry, null);

      expect(find.text("Scan the device's QR label"), findsOneWidget);
      expect(registry.claims, isEmpty);
    });
  });
}
