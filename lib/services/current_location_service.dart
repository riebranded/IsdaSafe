import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Resolves one foreground location for initializing the pond picker.
///
/// Permission is checked on every call because only the operating system or
/// browser can persist that choice. Once permission is confirmed, an in-memory
/// or platform last-known fix is returned immediately when available.
abstract final class CurrentLocationService {
  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.high,
    timeLimit: Duration(seconds: 4),
  );

  static LatLng? _sessionLocation;

  static Future<LatLng?> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        return null;
      }

      if (_sessionLocation case final location?) return location;

      // The web implementation does not support last-known positions.
      if (!kIsWeb) {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null) return _remember(cached);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: _settings,
      );
      return _remember(position);
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static LatLng _remember(Position position) {
    return _sessionLocation = LatLng(position.latitude, position.longitude);
  }
}
