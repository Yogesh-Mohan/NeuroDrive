import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Check if location services are enabled and request permissions if needed.
  Future<bool> handlePermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return false;
    } 

    return true;
  }

  /// Get location settings optimized for navigation & high frequency updates.
  LocationSettings _getLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 1),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.automotiveNavigation,
      );
    } else {
      return const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
    }
  }

  /// Get current position once.
  Future<Position?> getCurrentLocation() async {
    final hasPermission = await handlePermissions();
    if (!hasPermission) return null;

    return await Geolocator.getCurrentPosition(
      locationSettings: _getLocationSettings(),
    );
  }

  /// Stream high-accuracy location updates for driving.
  Stream<Position>? getLocationStream() {
    return Geolocator.getPositionStream(
      locationSettings: _getLocationSettings(),
    );
  }

  /// Accurately calculate speed in km/h.
  /// Uses raw GPS speed if valid (>0), otherwise fallback to distance-over-time delta.
  /// Filters out stationary GPS jitter/drift.
  double calculateSpeedKmh(Position currentPosition, Position? previousPosition) {
    // If GPS accuracy is very poor (> 35m), report 0 for safety/noise control
    if (currentPosition.accuracy > 35) {
      return 0.0;
    }

    double speedMps = currentPosition.speed;

    // If device hardware doesn't provide valid speed (negative value), calculate from delta
    if (speedMps < 0 && previousPosition != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        previousPosition.latitude,
        previousPosition.longitude,
        currentPosition.latitude,
        currentPosition.longitude,
      );

      final timeDiffInSeconds = currentPosition.timestamp
          .difference(previousPosition.timestamp)
          .inMilliseconds / 1000.0;

      if (timeDiffInSeconds > 0) {
        speedMps = distanceInMeters / timeDiffInSeconds;
      } else {
        speedMps = 0.0;
      }
    }

    // Convert m/s to km/h
    double speedKmh = speedMps > 0 ? speedMps * 3.6 : 0.0;

    // Noise threshold: ignore small movement drift under 1.0 km/h
    if (speedKmh < 1.0) {
      speedKmh = 0.0;
    }

    return speedKmh;
  }

  /// Helper to open app settings.
  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }
}
