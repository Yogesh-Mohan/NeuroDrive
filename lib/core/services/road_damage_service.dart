import 'dart:convert';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/road_damage_model.dart';

class RoadDamageService {
  final FirebaseFirestore? _customFirestore;
  List<RoadDamageModel>? _cachedDamage;

  RoadDamageService({FirebaseFirestore? firestore})
      : _customFirestore = firestore;

  FirebaseFirestore get _firestore =>
      _customFirestore ?? FirebaseFirestore.instance;

  /// Fetches existing active road damage records.
  /// First queries Firebase Firestore `road_damage` collection with offline cache fallback
  /// to the bundled Tamil Nadu dataset.
  Future<List<RoadDamageModel>> getRoadDamageRecords({bool forceRefresh = false}) async {
    if (_cachedDamage != null && !forceRefresh) {
      return _cachedDamage!;
    }

    List<RoadDamageModel> records = [];

    // 1. Try Firebase Firestore
    try {
      final snapshot = await _firestore
          .collection('road_damage')
          .where('status', isEqualTo: 'active')
          .get()
          .timeout(const Duration(seconds: 4));

      if (snapshot.docs.isNotEmpty) {
        records = snapshot.docs
            .map((doc) => RoadDamageModel.fromFirestore(doc))
            .where((d) => d.status.toLowerCase() == 'active')
            .where((d) => _isValidTamilNaduCoord(d.latitude, d.longitude))
            .toList();

        if (records.isNotEmpty) {
          debugPrint('[RoadDamageService] Loaded ${records.length} active records from Firestore.');
          _cachedDamage = records;
          return records;
        }
      }
    } catch (e) {
      debugPrint('[RoadDamageService] Firestore fetch notice: $e. Falling back to local dataset.');
    }

    // 2. Fallback to bundled Tamil Nadu dataset asset
    try {
      final jsonStr = await rootBundle.loadString('assets/data/tamilnadu_road_damage.json');
      final data = json.decode(jsonStr);
      final List rawList = data['records'] ?? [];

      records = rawList
          .map((item) => RoadDamageModel.fromMap(Map<String, dynamic>.from(item as Map)))
          .where((d) => d.status.toLowerCase() == 'active')
          .where((d) => _isValidTamilNaduCoord(d.latitude, d.longitude))
          .toList();

      debugPrint('[RoadDamageService] Loaded ${records.length} active records from local bundled dataset.');
      _cachedDamage = records;
      return records;
    } catch (e) {
      debugPrint('[RoadDamageService] Local asset load notice: $e');
    }

    _cachedDamage = records;
    return records;
  }

  static bool _isValidTamilNaduCoord(double lat, double lon) {
    return lat >= 8.05 && lat <= 13.55 && lon >= 76.20 && lon <= 80.35;
  }

  /// Filters road damage locations within a configurable corridor (default 50 meters)
  /// along the complete route polyline.
  List<RoadDamageModel> filterDamageAlongRoute({
    required List<LatLng> routePoints,
    required List<RoadDamageModel> allDamage,
    double corridorMeters = 50.0,
  }) {
    if (routePoints.isEmpty || allDamage.isEmpty) {
      return [];
    }

    final List<RoadDamageModel> filtered = [];

    // Precompute bounding box of route with corridor buffer for fast pre-filtering
    double minLat = routePoints.first.latitude;
    double maxLat = routePoints.first.latitude;
    double minLng = routePoints.first.longitude;
    double maxLng = routePoints.first.longitude;

    for (final pt in routePoints) {
      if (pt.latitude < minLat) minLat = pt.latitude;
      if (pt.latitude > maxLat) maxLat = pt.latitude;
      if (pt.longitude < minLng) minLng = pt.longitude;
      if (pt.longitude > maxLng) maxLng = pt.longitude;
    }

    // Buffer ~ 0.005 degrees (~500m) for fast bounding box rejection
    const buffer = 0.005;
    final candidateDamage = allDamage.where((d) {
      if (!d.isActive) return false;
      return d.latitude >= (minLat - buffer) &&
          d.latitude <= (maxLat + buffer) &&
          d.longitude >= (minLng - buffer) &&
          d.longitude <= (maxLng + buffer);
    }).toList();

    for (final damage in candidateDamage) {
      double minDistance = double.infinity;

      // Check distance from damage coordinate to each polyline segment
      for (int i = 0; i < routePoints.length - 1; i++) {
        final p1 = routePoints[i];
        final p2 = routePoints[i + 1];

        final dist = _perpendicularDistanceMeters(
          pointLat: damage.latitude,
          pointLng: damage.longitude,
          segStartLat: p1.latitude,
          segStartLng: p1.longitude,
          segEndLat: p2.latitude,
          segEndLng: p2.longitude,
        );

        if (dist < minDistance) {
          minDistance = dist;
        }

        // Early break if it's already within corridor
        if (minDistance <= corridorMeters) {
          break;
        }
      }

      if (minDistance <= corridorMeters) {
        filtered.add(damage.copyWith(distanceToRouteCorridorMeters: minDistance));
      }
    }

    return filtered;
  }

  /// Calculates perpendicular distance in meters from a GPS point to a line segment [A, B]
  static double _perpendicularDistanceMeters({
    required double pointLat,
    required double pointLng,
    required double segStartLat,
    required double segStartLng,
    required double segEndLat,
    required double segEndLng,
  }) {
    final midLatRad = ((segStartLat + segEndLat) / 2.0) * (math.pi / 180.0);
    const metersPerDegreeLat = 111320.0;
    final metersPerDegreeLng = 111320.0 * math.cos(midLatRad);

    final dx = (segEndLng - segStartLng) * metersPerDegreeLng;
    final dy = (segEndLat - segStartLat) * metersPerDegreeLat;

    final segLengthSq = (dx * dx) + (dy * dy);

    if (segLengthSq <= 0.0001) {
      return Geolocator.distanceBetween(pointLat, pointLng, segStartLat, segStartLng);
    }

    final px = (pointLng - segStartLng) * metersPerDegreeLng;
    final py = (pointLat - segStartLat) * metersPerDegreeLat;

    // Projection parameter clamped to segment [0, 1]
    final t = ((px * dx) + (py * dy)) / segLengthSq;
    final clampedT = math.max(0.0, math.min(1.0, t));

    final projLat = segStartLat + clampedT * (segEndLat - segStartLat);
    final projLng = segStartLng + clampedT * (segEndLng - segStartLng);

    return Geolocator.distanceBetween(pointLat, pointLng, projLat, projLng);
  }

  /// Checks if the vehicle is approaching an upcoming road damage location on the route.
  /// Avoids repeatedly alerting for the same damage location.
  RoadDamageModel? checkUpcomingHazard({
    required LatLng vehiclePos,
    required List<RoadDamageModel> routeHazards,
    required Set<String> alreadyAlertedIds,
    double warningDistanceMeters = 250.0,
  }) {
    RoadDamageModel? closest;
    double minDistance = double.infinity;

    for (final hazard in routeHazards) {
      if (alreadyAlertedIds.contains(hazard.damageId)) {
        continue;
      }

      final dist = Geolocator.distanceBetween(
        vehiclePos.latitude,
        vehiclePos.longitude,
        hazard.latitude,
        hazard.longitude,
      );

      // Warning corridor: between 15m and 250m ahead
      if (dist <= warningDistanceMeters && dist >= 15.0) {
        if (dist < minDistance) {
          minDistance = dist;
          closest = hazard.copyWith(distanceToVehicleMeters: dist);
        }
      }
    }

    return closest;
  }
}
