import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Resolves one foreground location for initializing the pond picker.
///
/// Permission is checked on every call because only the operating system or
/// browser can persist that choice. Once permission is confirmed, an in-memory
/// or platform last-known fix is returned immediately when available.
abstract final class CurrentLocationService {
  // Only used to center the map initially — the user can still drag the pin
  // afterward, so a fast network-based fix beats a slow, GPS-grade one that
  // can time out on desktop/web browsers without real GPS hardware.
  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.medium,
    timeLimit: Duration(seconds: 8),
  );

  static LatLng? _sessionLocation;

  static Future<LatLng?> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        debugPrint('CurrentLocationService: location services disabled');
        return null;
      }

      if (_sessionLocation case final location?) {
        debugPrint('CurrentLocationService: using cached $location');
        return location;
      }

      if (kIsWeb) {
        // The browser's permission prompt and its position fetch are the
        // same underlying call; requesting permission separately first
        // would just make the user wait through two round trips instead
        // of one before the map recenters.
        debugPrint('CurrentLocationService: web, requesting position');
        final position = await Geolocator.getCurrentPosition(
          locationSettings: _settings,
        );
        debugPrint('CurrentLocationService: web position=$position');
        return _remember(position);
      }

      var permission = await Geolocator.checkPermission();
      debugPrint('CurrentLocationService: checkPermission=$permission');
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        debugPrint('CurrentLocationService: requestPermission=$permission');
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever ||
          permission == LocationPermission.unableToDetermine) {
        debugPrint('CurrentLocationService: permission not granted, bailing');
        return null;
      }

      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null) {
        debugPrint('CurrentLocationService: using last-known $cached');
        return _remember(cached);
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: _settings,
      );
      debugPrint('CurrentLocationService: position=$position');
      return _remember(position);
    } on TimeoutException catch (e) {
      debugPrint('CurrentLocationService: TimeoutException $e');
      return null;
    } catch (e) {
      debugPrint('CurrentLocationService: error $e');
      return null;
    }
  }

  static LatLng _remember(Position position) {
    return _sessionLocation = LatLng(position.latitude, position.longitude);
  }
}
