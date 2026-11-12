import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationService {
  static final Map<String, String> _reverseGeocodeCache = {};
  http.Client? customClient;

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
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'NeuroDrive Active Navigation',
          notificationText: 'Real-time GPS tracking & road safety monitoring active.',
          notificationChannelName: 'NeuroDrive Navigation Service',
          enableWakeLock: true,
          enableWifiLock: true,
          setOngoing: true,
          color: Color(0xFF00D2FF),
          notificationIcon: AndroidResource(
            name: 'ic_launcher',
            defType: 'mipmap',
          ),
        ),
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

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _getLocationSettings(),
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
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
  double calculateSpeedKmh(
    Position currentPosition,
    Position? previousPosition,
  ) {
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

      final timeDiffInSeconds =
          currentPosition.timestamp
              .difference(previousPosition.timestamp)
              .inMilliseconds /
          1000.0;

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

  /// Calculates distance in kilometers between two coordinates.
  double distanceBetweenKm(double startLat, double startLng, double endLat, double endLng) {
    final meters = Geolocator.distanceBetween(startLat, startLng, endLat, endLng);
    return meters / 1000.0;
  }

  /// Reverse geocodes latitude & longitude into a clean, human-readable place name.
  /// (e.g. "Anna Nagar, Chennai" or "Karur, Tamil Nadu") with in-memory caching.
  Future<String> reverseGeocode(double latitude, double longitude) async {
    // Round to 3 decimal places (~110m) for effective caching
    final cacheKey = '${latitude.toStringAsFixed(3)},${longitude.toStringAsFixed(3)}';
    if (_reverseGeocodeCache.containsKey(cacheKey)) {
      return _reverseGeocodeCache[cacheKey]!;
    }

    try {
      final client = customClient ?? http.Client();
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$latitude&lon=$longitude&zoom=16&addressdetails=1',
      );
      final response = await client.get(
        url,
        headers: {'User-Agent': 'NeuroDrive_Flutter_App/1.0 (contact: support@neurodrive.app)'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>? ?? {};

        // Extract most specific readable locality names
        final road = address['road'] ?? address['pedestrian'] ?? address['street'];
        final locality = address['suburb'] ??
            address['neighbourhood'] ??
            address['residential'] ??
            address['commercial'] ??
            address['city_district'];
        final city = address['city'] ?? address['town'] ?? address['municipality'] ?? address['village'] ?? address['county'];
        final state = address['state'];

        final parts = <String>[];
        if (road != null && road.toString().trim().isNotEmpty) {
          parts.add(road.toString().trim());
        }
        if (locality != null && locality.toString().trim().isNotEmpty) {
          parts.add(locality.toString().trim());
        }
        if (city != null && city.toString().trim().isNotEmpty && !parts.contains(city.toString().trim())) {
          parts.add(city.toString().trim());
        } else if (parts.isEmpty && state != null) {
          parts.add(state.toString().trim());
        }

        String readableName;
        if (parts.isNotEmpty) {
          readableName = parts.take(2).join(', ');
        } else {
          final displayName = data['display_name']?.toString() ?? '';
          readableName = displayName.split(',').take(2).join(', ').trim();
        }

        if (readableName.isNotEmpty) {
          _reverseGeocodeCache[cacheKey] = readableName;
          return readableName;
        }
      }
    } catch (e) {
      debugPrint('[LocationService] Reverse geocode error: $e');
    }

    // Default human-friendly fallback when offline
    return 'Current GPS Location';
  }
}

