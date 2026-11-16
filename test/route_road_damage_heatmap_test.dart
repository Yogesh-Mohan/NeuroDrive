import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:neuro_drive/core/models/road_damage_model.dart';
import 'package:neuro_drive/core/services/road_damage_service.dart';

void main() {
  group('Tamil Nadu Global Potholes Dataset Asset Tests', () {
    test('tamilnadu_road_damage.json exists and contains valid Tamil Nadu records across state corridors', () {
      final file = File('assets/data/tamilnadu_road_damage.json');
      expect(file.existsSync(), isTrue, reason: 'Dataset asset JSON must be present');

      final content = file.readAsStringSync();
      final Map<String, dynamic> root = jsonDecode(content);
      final List<dynamic> list = root['records'] as List<dynamic>;
      expect(list.length, greaterThanOrEqualTo(60), reason: 'Must contain comprehensive Tamil Nadu damage records');

      int highCount = 0;
      int medCount = 0;
      int lowCount = 0;
      final Map<String, int> districtCounts = {};

      for (final item in list) {
        final record = RoadDamageModel.fromMap(item as Map<String, dynamic>);

        // Verify GPS strictly inside Tamil Nadu corridor boundaries (excluding Bangalore)
        expect(record.latitude, greaterThanOrEqualTo(8.05));
        expect(record.latitude, lessThanOrEqualTo(13.55));
        expect(record.longitude, greaterThanOrEqualTo(76.20));
        expect(record.longitude, lessThanOrEqualTo(80.35));

        // Ensure zero records are placed in Bangalore
        final isBangalore = (record.latitude >= 12.80 && record.latitude <= 13.20 &&
            record.longitude >= 77.40 && record.longitude <= 77.80);
        expect(isBangalore, isFalse, reason: 'No road damage records should be in Bengaluru');

        // Verify severity
        final sev = record.severity.toLowerCase();
        expect(['high', 'medium', 'low', 'moderate'].contains(sev), isTrue);
        if (sev == 'high') highCount++;
        if (sev == 'medium' || sev == 'moderate') medCount++;
        if (sev == 'low') lowCount++;

        // Verify district
        expect(record.district.isNotEmpty, isTrue);
        districtCounts[record.district] = (districtCounts[record.district] ?? 0) + 1;
      }

      expect(highCount, greaterThan(0));
      expect(medCount, greaterThan(0));
      expect(lowCount, greaterThanOrEqualTo(0));
      expect(districtCounts.isNotEmpty, isTrue);
    });
  });

  group('RoadDamageModel Tests', () {
    test('RoadDamageModel.fromMap correctly parses Firestore document fields', () {
      final map = {
        'damage_id': 'tn_pothole_101',
        'latitude': 12.7409,
        'longitude': 77.8253,
        'damage_type': 'pothole',
        'severity': 'high',
        'source': 'Global_Potholes_Dataset.csv',
        'district': 'Krishnagiri / Hosur Corridor',
        'status': 'active',
      };

      final model = RoadDamageModel.fromMap(map);
      expect(model.damageId, equals('tn_pothole_101'));
      expect(model.latitude, closeTo(12.7409, 0.0001));
      expect(model.longitude, closeTo(77.8253, 0.0001));
      expect(model.severity, equals('high'));
      expect(model.damageType, equals('pothole'));
      expect(model.district, equals('Krishnagiri / Hosur Corridor'));
      expect(model.isActive, isTrue);
      expect(model.toMap()['latitude'], equals(12.7409));
    });

    test('RoadDamageModel infers district and severity if not explicitly provided', () {
      final map = {
        'damage_id': 'auto_inf_1',
        'latitude': 13.0827,
        'longitude': 80.2707,
      };

      final model = RoadDamageModel.fromMap(map);
      expect(model.district, equals('Tamil Nadu'));
      expect(model.severity, equals('medium'));
      expect(model.isActive, isTrue);
    });
  });

  group('RoadDamageService - 50m Route Corridor Filtering Tests', () {
    late RoadDamageService service;

    setUp(() {
      service = RoadDamageService();
    });

    test('Filters damage locations within 50-metre corridor and excludes outside locations', () {
      // Create a test polyline segment in Hosur (from 12.74000, 77.82000 to 12.74000, 77.83000)
      final polylineCoordinates = [
        const LatLng(12.74000, 77.82000),
        const LatLng(12.74000, 77.83000),
      ];

      // 1 degree latitude ~= 111,320m
      // 0.00018 degrees latitude ~= 20.0m (Inside 50m corridor)
      // 0.00072 degrees latitude ~= 80.0m (Outside 50m corridor)
      final damageRecords = [
        const RoadDamageModel(
          damageId: 'inside_corridor_1',
          latitude: 12.74018, // ~20m north of route polyline
          longitude: 77.82500,
          severity: 'high',
          district: 'Hosur',
        ),
        const RoadDamageModel(
          damageId: 'inside_corridor_2',
          latitude: 12.73970, // ~33m south of route polyline
          longitude: 77.82200,
          severity: 'medium',
          district: 'Hosur',
        ),
        const RoadDamageModel(
          damageId: 'outside_corridor_1',
          latitude: 12.74080, // ~89m north of route polyline
          longitude: 77.82500,
          severity: 'high',
          district: 'Hosur',
        ),
        const RoadDamageModel(
          damageId: 'distant_chennai',
          latitude: 13.0827,
          longitude: 80.2707,
          severity: 'high',
          district: 'Chennai',
        ),
      ];

      final filtered = service.filterDamageAlongRoute(
        routePoints: polylineCoordinates,
        allDamage: damageRecords,
        corridorMeters: 50.0,
      );

      // Verify only inside_corridor_1 and inside_corridor_2 are returned
      expect(filtered.length, equals(2));
      final ids = filtered.map((d) => d.damageId).toList();
      expect(ids.contains('inside_corridor_1'), isTrue);
      expect(ids.contains('inside_corridor_2'), isTrue);
      expect(ids.contains('outside_corridor_1'), isFalse);
      expect(ids.contains('distant_chennai'), isFalse);

      // Check corridor distance annotation
      for (final h in filtered) {
        expect(h.distanceToRouteCorridorMeters, isNotNull);
        expect(h.distanceToRouteCorridorMeters!, lessThanOrEqualTo(50.0));
      }
    });

    test('Excludes inactive/repaired road damage records even if on route', () {
      final polylineCoordinates = [
        const LatLng(12.74000, 77.82000),
        const LatLng(12.74000, 77.83000),
      ];

      final damageRecords = [
        const RoadDamageModel(
          damageId: 'active_hazard',
          latitude: 12.74010,
          longitude: 77.82500,
          severity: 'high',
          district: 'Hosur',
          status: 'active',
        ),
        const RoadDamageModel(
          damageId: 'repaired_hazard',
          latitude: 12.74010,
          longitude: 77.82500,
          severity: 'high',
          district: 'Hosur',
          status: 'repaired',
        ),
        const RoadDamageModel(
          damageId: 'resolved_hazard',
          latitude: 12.74010,
          longitude: 77.82500,
          severity: 'high',
          district: 'Hosur',
          status: 'resolved',
        ),
      ];

      final filtered = service.filterDamageAlongRoute(
        routePoints: polylineCoordinates,
        allDamage: damageRecords,
        corridorMeters: 50.0,
      );

      expect(filtered.length, equals(1));
      expect(filtered.first.damageId, equals('active_hazard'));
    });

    test('ensureRouteCoverage guarantees damage hazards along active user route from start to destination', () {
      // Simulating a route from Karur (10.9601, 78.0766) to Madurai (9.9252, 78.1198)
      final karurToMaduraiRoute = [
        const LatLng(10.9601, 78.0766), // Karur
        const LatLng(10.5312, 77.9541), // Vedasandur
        const LatLng(10.3673, 77.9803), // Dindigul
        const LatLng(10.0824, 78.0412), // Vadipatti
        const LatLng(9.9252, 78.1198),  // Madurai
      ];

      final filteredWithCoverage = service.filterDamageAlongRoute(
        routePoints: karurToMaduraiRoute,
        allDamage: const [], // No pre-existing hazards matched
        corridorMeters: 100.0,
        ensureRouteCoverage: true,
      );

      // Verify that hazards are synthesized along the trip
      expect(filteredWithCoverage.isNotEmpty, isTrue);
      expect(filteredWithCoverage.length, greaterThanOrEqualTo(2));

      for (final h in filteredWithCoverage) {
        expect(h.status, equals('active'));
        expect(h.district.contains('District'), isTrue);
        expect(h.latitude, greaterThanOrEqualTo(8.05));
        expect(h.latitude, lessThanOrEqualTo(13.55));
        expect(h.longitude, greaterThanOrEqualTo(76.50));
        expect(h.longitude, lessThanOrEqualTo(80.35));
      }
    });
  });

  group('RoadDamageService - Advance Alerting Tests', () {
    late RoadDamageService service;

    setUp(() {
      service = RoadDamageService();
    });

    test('Triggers advance alert when vehicle is within 250m and not previously alerted', () {
      final routeHazards = [
        const RoadDamageModel(
          damageId: 'hazard_150m_ahead',
          latitude: 12.74135, // ~150m north
          longitude: 77.82500,
          severity: 'high',
          district: 'Hosur',
        ),
        const RoadDamageModel(
          damageId: 'hazard_600m_ahead',
          latitude: 12.74540, // ~600m north
          longitude: 77.82500,
          severity: 'medium',
          district: 'Hosur',
        ),
      ];

      final vehiclePos = const LatLng(12.74000, 77.82500);
      final alertedIds = <String>{};

      // Check upcoming hazard
      final alert = service.checkUpcomingHazard(
        vehiclePos: vehiclePos,
        routeHazards: routeHazards,
        alreadyAlertedIds: alertedIds,
        warningDistanceMeters: 250.0,
      );

      expect(alert, isNotNull);
      expect(alert!.damageId, equals('hazard_150m_ahead'));
      expect(alert.distanceToVehicleMeters, isNotNull);
      expect(alert.distanceToVehicleMeters!, lessThanOrEqualTo(250.0));
    });

    test('Does not alert for already alerted damage locations in the same session', () {
      final routeHazards = [
        const RoadDamageModel(
          damageId: 'hazard_150m_ahead',
          latitude: 12.74135,
          longitude: 77.82500,
          severity: 'high',
          district: 'Hosur',
        ),
      ];

      final vehiclePos = const LatLng(12.74000, 77.82500);
      final alertedIds = <String>{'hazard_150m_ahead'};

      final alert = service.checkUpcomingHazard(
        vehiclePos: vehiclePos,
        routeHazards: routeHazards,
        alreadyAlertedIds: alertedIds,
        warningDistanceMeters: 250.0,
      );

      expect(alert, isNull);
    });
  });
}
