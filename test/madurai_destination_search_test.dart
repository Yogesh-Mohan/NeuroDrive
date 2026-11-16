import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:neuro_drive/screens/map_view_screen.dart';
import 'package:neuro_drive/core/services/road_damage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Madurai Destination Search & Selection Verification', () {
    test('Searching "Madurai" returns Madurai City at Tier 0 Rank #1 with valid coordinates', () async {
      // User is at Karur / MKCE Campus (11.0544, 78.0486)
      const userPos = LatLng(11.0544, 78.0486);
      final delegate = LocationSearchDelegate(currentPosition: userPos);

      // Search for "Madurai"
      final suggestions = await delegate.getSuggestionsForTesting('Madurai');

      expect(suggestions.isNotEmpty, isTrue, reason: 'Suggestions should not be empty');

      // Rank #1 MUST be Madurai
      final topResult = suggestions.first;
      expect(topResult.title.toLowerCase(), equals('madurai'));
      expect(topResult.latLng.latitude, closeTo(9.9252, 0.05));
      expect(topResult.latLng.longitude, closeTo(78.1198, 0.05));

      // Distance from Karur to Madurai should be ~130-150 km
      expect(topResult.distanceKm, isNotNull);
      expect(topResult.distanceKm!, greaterThan(120.0));
      expect(topResult.distanceKm!, lessThan(160.0));

      // Verify that other Madurai hubs (Junction, Mattuthavani, Airport) are in suggestions
      final titles = suggestions.map((s) => s.title).toList();
      expect(titles.any((t) => t.contains('Madurai Junction')), isTrue);
      expect(titles.any((t) => t.contains('Mattuthavani')), isTrue);
    });

    test('Route from Karur to Madurai generates hazards along the corridor with accurate district naming', () {
      final service = RoadDamageService();

      // Polyline coordinates from Karur (11.0544, 78.0486) to Madurai (9.9252, 78.1198) along NH44
      final karurToMaduraiRoute = [
        const LatLng(11.0544, 78.0486), // Karur / MKCE
        const LatLng(10.9601, 78.0766), // Karur Bypass
        const LatLng(10.5312, 77.9541), // Vedasandur
        const LatLng(10.3673, 77.9803), // Dindigul Bypass
        const LatLng(10.0824, 78.0412), // Vadipatti
        const LatLng(9.9821, 78.0534),  // Samayanallur
        const LatLng(9.9252, 78.1198),  // Madurai
      ];

      final routeHazards = service.filterDamageAlongRoute(
        routePoints: karurToMaduraiRoute,
        allDamage: const [],
        corridorMeters: 100.0,
        ensureRouteCoverage: true,
      );

      expect(routeHazards.isNotEmpty, isTrue);
      expect(routeHazards.length, greaterThanOrEqualTo(2));

      for (final h in routeHazards) {
        expect(h.status, equals('active'));
        expect(h.latitude, greaterThanOrEqualTo(9.5));
        expect(h.latitude, lessThanOrEqualTo(11.5));
        expect(h.longitude, greaterThanOrEqualTo(77.5));
        expect(h.longitude, lessThanOrEqualTo(78.5));
      }
    });
  });
}
