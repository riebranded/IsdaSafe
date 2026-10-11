import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// Photos are shrunk to this many pixels on their longer side before
/// decoding: a phone photo is far bigger than a QR code needs, and decoding
/// it full size takes seconds.
const _maxSide = 1600;

/// Reads the QR code in an image file (PNG, JPEG, ...), e.g. a photo of a
/// device's label. Returns its text, or null when the image can't be read or
/// has no QR code in it. Pure Dart, so it works in every browser and on every
/// platform; it runs in a background isolate where there is one.
Future<String?> decodeQrFromImage(Uint8List bytes) => compute(_decodeQr, bytes);

String? _decodeQr(Uint8List bytes) {
  img.Image? image;
  try {
    image = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (image == null) return null;
  // Photos from phones are often stored sideways with an EXIF rotation.
  image = img.bakeOrientation(image);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > _maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _maxSide)
        : img.copyResize(image, height: _maxSide);
  }

  final source = RGBLuminanceSource(
    image.width,
    image.height,
    image
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.abgr)
        .buffer
        .asInt32List(),
  );
  final hints = DecodeHints()..put(DecodeHintType.tryHarder);
  // Hybrid copes with uneven lighting (photos); global histogram with flat,
  // printed or on-screen labels.
  for (final binarizer in [
    HybridBinarizer(source),
    GlobalHistogramBinarizer(source),
  ]) {
    try {
      return QRCodeReader().decode(BinaryBitmap(binarizer), hints: hints).text;
    } catch (_) {
      // Not found with this binarizer; try the next one.
    }
  }
  return null;
}
