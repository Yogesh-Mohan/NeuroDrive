import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:neuro_drive/screens/map_view_screen.dart';

void main() {
  group('MapViewScreen - Dynamic Route Polyline Trimming Tests', () {
    // 5-waypoint test route along a road segment (lat/lng coordinates ~100m apart)
    final List<LatLng> testRoute = [
      const LatLng(9.92500, 78.11900), // P0: Start
      const LatLng(9.92600, 78.11900), // P1: ~111m North
      const LatLng(9.92700, 78.11900), // P2: ~222m North
      const LatLng(9.92800, 78.11900), // P3: ~333m North
      const LatLng(9.92900, 78.11900), // P4: Destination (~444m North)
    ];

    test('Empty route returns empty points and hasArrived true', () {
      final result = MapViewScreen.computeRemainingRoutePoints(
        vehiclePos: const LatLng(9.92500, 78.11900),
        fullRoute: [],
      );

      expect(result.remainingPoints, isEmpty);
      expect(result.hasArrived, isTrue);
      expect(result.remainingDistanceMeters, equals(0.0));
    });

    test('At start position: retains full forward route with vehiclePos at head', () {
      final vehiclePos = const LatLng(9.92500, 78.11900);
      final result = MapViewScreen.computeRemainingRoutePoints(
        vehiclePos: vehiclePos,
        fullRoute: testRoute,
        currentProgressIndex: 0,
      );

      expect(result.hasArrived, isFalse);
      expect(result.remainingPoints.isNotEmpty, isTrue);
      // Head of remaining line is the vehicle position
      expect(result.remainingPoints.first, equals(vehiclePos));
      // Forward waypoints P1..P4 are preserved
      expect(result.remainingPoints.last, equals(testRoute.last));
      expect(result.remainingDistanceMeters, greaterThan(400.0));
      expect(result.newProgressIndex, equals(0));
    });

    test('Moving along segment P0->P1 trims start P0 and starts polyline right at vehicle', () {
      // Vehicle is halfway between P0 and P1
      final vehiclePos = const LatLng(9.92550, 78.11900);
      final result = MapViewScreen.computeRemainingRoutePoints(
        vehiclePos: vehiclePos,
        fullRoute: testRoute,
        currentProgressIndex: 0,
      );

      expect(result.hasArrived, isFalse);
      expect(result.remainingPoints.first, equals(vehiclePos));
      // Traversed start P0 (9.92500) is NOT in remaining points!
      expect(result.remainingPoints.contains(testRoute[0]), isFalse);
      // P1, P2, P3, P4 are retained
      expect(result.remainingPoints.contains(testRoute[1]), isTrue);
      expect(result.remainingPoints.contains(testRoute[4]), isTrue);
      expect(result.remainingDistanceMeters, closeTo(388.0, 10.0));
    });

    test('Passing P1 onto segment P1->P2 clears both P0 and P1 behind the vehicle', () {
      // Vehicle has passed P1 and is driving between P1 and P2
      final vehiclePos = const LatLng(9.92640, 78.11900);
      final result = MapViewScreen.computeRemainingRoutePoints(
        vehiclePos: vehiclePos,
        fullRoute: testRoute,
        currentProgressIndex: 0,
      );

      expect(result.hasArrived, isFalse);
      expect(result.newProgressIndex, greaterThanOrEqualTo(1));
      expect(result.remainingPoints.first, equals(vehiclePos));
      // P0 and P1 are cleared from the polyline
      expect(result.remainingPoints.contains(testRoute[0]), isFalse);
      expect(result.remainingPoints.contains(testRoute[1]), isFalse);
      // P2, P3, P4 remain ahead
      expect(result.remainingPoints.contains(testRoute[2]), isTrue);
      expect(result.remainingPoints.contains(testRoute[3]), isTrue);
      expect(result.remainingPoints.contains(testRoute[4]), isTrue);
      expect(result.remainingDistanceMeters, closeTo(288.0, 10.0));
    });

    test('Reaching within 35m of destination triggers arrival and clears polyline', () {
      // Destination is at 9.92900, 78.11900 (~15m away)
      final vehiclePos = const LatLng(9.92885, 78.11900);
      final result = MapViewScreen.computeRemainingRoutePoints(
        vehiclePos: vehiclePos,
        fullRoute: testRoute,
        currentProgressIndex: 3,
        arrivalThresholdMeters: 35.0,
      );

      expect(result.hasArrived, isTrue);
      expect(result.remainingPoints, isEmpty);
      expect(result.remainingDistanceMeters, equals(0.0));
    });

    test('Vehicle off-corridor by >150m retains progress index and remains stable', () {
      // 500m east of route (off-road)
      final vehiclePos = const LatLng(9.92600, 78.12500);
      final result = MapViewScreen.computeRemainingRoutePoints(
        vehiclePos: vehiclePos,
        fullRoute: testRoute,
        currentProgressIndex: 1,
        maxCorridorMeters: 150.0,
      );

      expect(result.hasArrived, isFalse);
      expect(result.newProgressIndex, equals(1));
      expect(result.remainingPoints.first, equals(vehiclePos));
    });

    test('Parallel route segments or hairpins do not skip ahead prematurely', () {
      // A route that loops back parallel to itself
      final List<LatLng> hairpinRoute = [
        const LatLng(10.0000, 78.0000), // 0: Start
        const LatLng(10.0010, 78.0000), // 1: Northbound
        const LatLng(10.0020, 78.0000), // 2: Northbound
        const LatLng(10.0021, 78.0002), // 3: Loop turn
        const LatLng(10.0010, 78.0002), // 4: Southbound parallel (~22m away)
        const LatLng(10.0000, 78.0002), // 5: Southbound Destination
      ];

      // Vehicle is at 10.0005, 78.0000 (driving north along segment 0->1)
      final vehiclePos = const LatLng(10.0005, 78.0000);
      final result = MapViewScreen.computeRemainingRoutePoints(
        vehiclePos: vehiclePos,
        fullRoute: hairpinRoute,
        currentProgressIndex: 0,
      );

      // Must NOT skip to southbound segment 4->5!
      expect(result.newProgressIndex, equals(0));
      expect(result.remainingPoints.contains(hairpinRoute[1]), isTrue);
      expect(result.remainingPoints.contains(hairpinRoute[2]), isTrue);
    });
  });
}
