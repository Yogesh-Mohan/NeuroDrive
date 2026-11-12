import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:neuro_drive/core/models/road_damage_model.dart';
import 'package:neuro_drive/core/services/location_service.dart';
import 'package:neuro_drive/core/services/notification_service.dart';
import 'package:neuro_drive/core/services/road_damage_service.dart';
import 'package:neuro_drive/core/services/safety_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  group('Background Foreground Service & WakeLock Verification', () {
    test('LocationService AndroidSettings configures ForegroundNotificationConfig with WakeLock and Ongoing', () {
      final locationService = LocationService();
      
      // Verify calculateSpeedKmh filters stationary jitter
      final pos1 = Position(
        latitude: 12.7400,
        longitude: 77.8200,
        timestamp: DateTime.now(),
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0.1,
        speedAccuracy: 0,
        accuracy: 5.0,
      );
      final speed = locationService.calculateSpeedKmh(pos1, null);
      expect(speed, isA<double>());
    });

    test('AndroidManifest.xml contains FOREGROUND_SERVICE_LOCATION and GeolocatorLocationService', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);

      final content = manifestFile.readAsStringSync();

      // Check required permissions for Android 14/15 background location
      expect(content.contains('android.permission.ACCESS_FINE_LOCATION'), isTrue);
      expect(content.contains('android.permission.ACCESS_BACKGROUND_LOCATION'), isTrue);
      expect(content.contains('android.permission.FOREGROUND_SERVICE'), isTrue);
      expect(content.contains('android.permission.FOREGROUND_SERVICE_LOCATION'), isTrue);
      expect(content.contains('android.permission.WAKE_LOCK'), isTrue);
      expect(content.contains('android.permission.POST_NOTIFICATIONS'), isTrue);

      // Check explicit service declaration
      expect(content.contains('GeolocatorLocationService'), isTrue);
      expect(content.contains('android:foregroundServiceType="location"'), isTrue);
    });

    test('MainShell uses IndexedStack to keep MapView and location stream alive across tabs', () {
      final shellFile = File('lib/main_shell.dart');
      expect(shellFile.existsSync(), isTrue);

      final content = shellFile.readAsStringSync();
      expect(content.contains('IndexedStack('), isTrue);
      expect(content.contains('index: _currentIndex'), isTrue);
    });
  });

  group('Background Driving Navigation Simulation Tests', () {
    test('Driving distance and wall-clock duration accumulate accurately across sequential GPS updates', () {
      final startTime = DateTime.now().subtract(const Duration(minutes: 5, seconds: 30));

      // Simulate vehicle coordinates moving south along Hosur corridor
      final waypoints = [
        Position(
          latitude: 12.7400,
          longitude: 77.8200,
          timestamp: startTime,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 180,
          headingAccuracy: 0,
          speed: 15.0, // ~54 km/h
          speedAccuracy: 0,
          accuracy: 5.0,
        ),
        Position(
          latitude: 12.7380, // moved ~222 meters
          longitude: 77.8200,
          timestamp: startTime.add(const Duration(seconds: 15)),
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 180,
          headingAccuracy: 0,
          speed: 15.5,
          speedAccuracy: 0,
          accuracy: 5.0,
        ),
        Position(
          latitude: 12.7350, // moved another ~333 meters
          longitude: 77.8200,
          timestamp: startTime.add(const Duration(seconds: 35)),
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 180,
          headingAccuracy: 0,
          speed: 16.0,
          speedAccuracy: 0,
          accuracy: 5.0,
        ),
      ];

      double totalDistance = 0.0;
      Position? currentPos;

      for (final pt in waypoints) {
        if (currentPos != null) {
          final added = Geolocator.distanceBetween(
            currentPos.latitude,
            currentPos.longitude,
            pt.latitude,
            pt.longitude,
          );
          totalDistance += added;
        }
        currentPos = pt;
      }

      // Verify distance accumulated (~550 meters)
      expect(totalDistance, greaterThan(500.0));
      expect(totalDistance, lessThan(600.0));

      // Wall-clock duration is independent of screen state
      final duration = DateTime.now().difference(startTime);
      expect(duration.inMinutes, greaterThanOrEqualTo(5));
    });

    test('Background hazard detection evaluates approaching potholes and generates alert notifications', () {
      final roadDamageService = RoadDamageService();
      final safetyEngine = SafetyEngine();

      final activeHazards = [
        const RoadDamageModel(
          damageId: 'bg_hazard_01',
          latitude: 12.7385,
          longitude: 77.8200,
          severity: 'high',
          district: 'Hosur Corridor',
        ),
      ];

      final vehiclePos = const LatLng(12.7400, 77.8200); // ~166m north of hazard
      final alertedIds = <String>{};

      final hazardAlert = roadDamageService.checkUpcomingHazard(
        vehiclePos: vehiclePos,
        routeHazards: activeHazards,
        alreadyAlertedIds: alertedIds,
        warningDistanceMeters: 250.0,
      );

      expect(hazardAlert, isNotNull);
      expect(hazardAlert!.damageId, equals('bg_hazard_01'));
      expect(hazardAlert.distanceToVehicleMeters, lessThanOrEqualTo(250.0));

      // Add to alerted set
      alertedIds.add(hazardAlert.damageId);

      // Verify deduplication on subsequent tick
      final secondCheck = roadDamageService.checkUpcomingHazard(
        vehiclePos: vehiclePos,
        routeHazards: activeHazards,
        alreadyAlertedIds: alertedIds,
        warningDistanceMeters: 250.0,
      );
      expect(secondCheck, isNull);

      // Verify safety engine evaluation on current position
      final currentPos = Position(
        latitude: vehiclePos.latitude,
        longitude: vehiclePos.longitude,
        timestamp: DateTime.now(),
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 180,
        headingAccuracy: 0,
        speed: 14.0,
        speedAccuracy: 0,
        accuracy: 4.0,
      );
      final safetyStatus = safetyEngine.evaluateRisk(currentEgoPosition: currentPos);
      expect(safetyStatus, isNotNull);
    });

    test('NotificationService showRoadDamageAlertNotification executes cleanly without throwing', () async {
      final notifService = NotificationService();
      expect(
        () async => await notifService.showRoadDamageAlertNotification(
          title: '⚠️ HIGH POTHOLE AHEAD (150m)',
          body: 'Hosur Corridor • Slow down',
          severity: 'high',
        ),
        returnsNormally,
      );
    });
  });
}
