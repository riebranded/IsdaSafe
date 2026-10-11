import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:isdasafev2/services/usb_sensor/qr_image_decoder.dart';

import '../support/qr_image.dart';

void main() {
  const label = 'https://isdasafe.vercel.app/?claim=6C383B124B00.ABCD2345EFGH';

  test('reads the QR code in a label PNG', () async {
    expect(await decodeQrFromImage(qrImage(label)), label);
  });

  test('reads a JPEG photo, shrinking a large one first', () async {
    // Wider than the 1600 px limit, so it gets resized before decoding.
    final photo = qrImage(label, scale: 20, jpeg: true, extraWidth: 1200);
    expect(img.decodeImage(photo)!.width, greaterThan(1600));
    expect(await decodeQrFromImage(photo), label);
  });

  test('null for an image without a QR code, or not an image', () async {
    expect(await decodeQrFromImage(blankImage()), isNull);
    expect(await decodeQrFromImage(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
