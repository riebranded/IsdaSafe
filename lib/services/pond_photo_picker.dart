import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/pond_verification.dart';

/// Thrown when a photo can't be used; [message] is safe to show.
class PondPhotoException implements Exception {
  const PondPhotoException(this.message);
  final String message;

  @override
  String toString() => 'PondPhotoException: $message';
}

/// Photos above this are rejected before upload; the verifier accepts at most
/// the same size.
const kMaxPondPhotoBytes = 3 * 1024 * 1024;

/// Lets the user take (phones) or choose (web/desktop) an in-house pond photo.
/// Abstract so the add-pond dialog can be tested without a camera.
abstract class PondPhotoPicker {
  /// Returns null if the user backed out; throws [PondPhotoException] if the
  /// chosen photo is unusable.
  Future<PondPhoto?> pickPhoto();

  /// Lets the user choose several existing pictures at once (the gallery on
  /// phones, a file chooser on web/desktop). Returns at most [maxCount]
  /// usable photos — pictures of an unsupported type or size are skipped —
  /// and throws [PondPhotoException] only if every chosen picture was unusable.
  Future<List<PondPhoto>> pickPhotos({required int maxCount});

  /// Whether [pickPhoto] opens the live camera (phones) rather than a file
  /// chooser.
  bool get usesCamera;
}

class ImagePickerPondPhotoPicker implements PondPhotoPicker {
  ImagePickerPondPhotoPicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const _allowedMediaTypes = {'image/jpeg', 'image/png', 'image/webp'};

  // Live camera on phones so a pond photo can't be a saved or downloaded
  // image; web and desktop have no reliable camera source, so they pick a file
  // instead.
  @override
  bool get usesCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Future<PondPhoto?> pickPhoto() async {
    final file = await _picker.pickImage(
      source: usesCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return null;
    return _toPhoto(file);
  }

  @override
  Future<List<PondPhoto>> pickPhotos({required int maxCount}) async {
    if (maxCount <= 0) return const [];
    final files = await _picker.pickMultiImage(
      maxWidth: 1600,
      imageQuality: 80,
      limit: maxCount,
    );

    final photos = <PondPhoto>[];
    PondPhotoException? firstProblem;
    for (final file in files.take(maxCount)) {
      try {
        photos.add(await _toPhoto(file));
      } on PondPhotoException catch (e) {
        firstProblem ??= e;
      }
    }
    if (photos.isEmpty && firstProblem != null) throw firstProblem;
    return photos;
  }

  Future<PondPhoto> _toPhoto(XFile file) async {
    final bytes = await file.readAsBytes();
    final mediaType = _mediaTypeOf(file);
    if (!_allowedMediaTypes.contains(mediaType)) {
      throw const PondPhotoException('Please use a JPG, PNG or WebP photo.');
    }
    if (bytes.length > kMaxPondPhotoBytes) {
      throw const PondPhotoException(
        'That photo is too large. Please use one under 3 MB.',
      );
    }
    return PondPhoto(bytes: bytes, mediaType: mediaType);
  }

  static String _mediaTypeOf(XFile file) {
    final declared = file.mimeType;
    if (declared != null && declared.isNotEmpty) return declared;
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
