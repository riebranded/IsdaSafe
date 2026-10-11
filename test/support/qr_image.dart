import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// A QR code for [text] as image bytes, like a label from
/// tools/provision_device.py or a photo of one.
Uint8List qrImage(
  String text, {
  int scale = 8,
  bool jpeg = false,
  int extraWidth = 0,
}) {
  final matrix = Encoder.encode(text, ErrorCorrectionLevel.m).matrix!;
  const quiet = 4; // White border QR readers need around the code.
  final size = (matrix.width + 2 * quiet) * scale;
  final image = img.Image(width: size + extraWidth, height: size)
    ..clear(img.ColorRgb8(255, 255, 255));
  for (var x = 0; x < matrix.width; x++) {
    for (var y = 0; y < matrix.height; y++) {
      if (matrix.get(x, y) != 1) continue;
      img.fillRect(
        image,
        x1: (x + quiet) * scale,
        y1: (y + quiet) * scale,
        x2: (x + quiet + 1) * scale - 1,
        y2: (y + quiet + 1) * scale - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return jpeg ? img.encodeJpg(image, quality: 85) : img.encodePng(image);
}

/// A plain white image: no QR code in it.
Uint8List blankImage() => img.encodePng(
  img.Image(width: 300, height: 300)..clear(img.ColorRgb8(255, 255, 255)),
);
