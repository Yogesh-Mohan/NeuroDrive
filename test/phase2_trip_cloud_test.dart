import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_drive/core/models/trip_model.dart';

void main() {
  group('Phase 2 - TripModel Tests', () {
    test('TripModel initializes and calculates derived metrics correctly', () {
      final start = DateTime(2026, 10, 11, 10, 0, 0);
      final end = DateTime(2026, 10, 11, 10, 30, 0);

      final trip = TripModel(
        tripId: 'test_trip_001',
        uid: 'user_abc',
        startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707, address: 'Chennai Central'),
        endLocation: const TripLocation(latitude: 12.9815, longitude: 80.2180, address: 'Guindy'),
        startTime: start,
        endTime: end,
        distance: 15400.0, // 15.4 km
        duration: 1800, // 30 mins
        avgSpeed: 30.8,
        createdAt: start,
        isSynced: true,
      );

      expect(trip.tripId, 'test_trip_001');
      expect(trip.uid, 'user_abc');
      expect(trip.distanceKm, 15.4);
      expect(trip.formattedDuration, '30 min');
      expect(trip.avgSpeed, 30.8);
      expect(trip.isSynced, isTrue);
    });

    test('TripModel formattedDuration formats seconds, minutes and hours', () {
      final now = DateTime.now();
      
      final tripSecs = TripModel(
        tripId: 't1',
        uid: 'u1',
        startLocation: const TripLocation(latitude: 0, longitude: 0),
        endLocation: const TripLocation(latitude: 0, longitude: 0),
        startTime: now,
        endTime: now.add(const Duration(seconds: 45)),
        distance: 100,
        duration: 45,
        avgSpeed: 10,
      );
      expect(tripSecs.formattedDuration, '45 sec');

      final tripMins = TripModel(
        tripId: 't2',
        uid: 'u1',
        startLocation: const TripLocation(latitude: 0, longitude: 0),
        endLocation: const TripLocation(latitude: 0, longitude: 0),
        startTime: now,
        endTime: now.add(const Duration(minutes: 25)),
        distance: 5000,
        duration: 1500,
        avgSpeed: 12,
      );
      expect(tripMins.formattedDuration, '25 min');

      final tripHours = TripModel(
        tripId: 't3',
        uid: 'u1',
        startLocation: const TripLocation(latitude: 0, longitude: 0),
        endLocation: const TripLocation(latitude: 0, longitude: 0),
        startTime: now,
        endTime: now.add(const Duration(hours: 1, minutes: 15)),
        distance: 40000,
        duration: 4500,
        avgSpeed: 32,
      );
      expect(tripHours.formattedDuration, '1 hr 15 min');
    });

    test('TripModel toJsonMap and fromMap serialization roundtrip', () {
      final start = DateTime(2026, 10, 11, 8, 30, 0);
      final end = DateTime(2026, 10, 11, 9, 0, 0);

      final original = TripModel(
        tripId: 'roundtrip_trip_123',
        uid: 'driver_777',
        startLocation: const TripLocation(latitude: 13.05, longitude: 80.25),
        endLocation: const TripLocation(latitude: 13.10, longitude: 80.30),
        startTime: start,
        endTime: end,
        distance: 12500.0,
        duration: 1800,
        avgSpeed: 25.0,
        createdAt: start,
        isSynced: false,
      );

      final jsonMap = original.toJsonMap();
      expect(jsonMap['tripId'], 'roundtrip_trip_123');
      expect(jsonMap['id'], 'roundtrip_trip_123'); // backwards compatible
      expect(jsonMap['distanceMeters'], 12500.0); // backwards compatible
      expect(jsonMap['durationSeconds'], 1800); // backwards compatible
      expect(jsonMap['isSynced'], false);

      final reconstructed = TripModel.fromMap(jsonMap);
      expect(reconstructed.tripId, original.tripId);
      expect(reconstructed.uid, original.uid);
      expect(reconstructed.distance, original.distance);
      expect(reconstructed.duration, original.duration);
      expect(reconstructed.startLocation.latitude, original.startLocation.latitude);
      expect(reconstructed.endLocation.latitude, original.endLocation.latitude);
      expect(reconstructed.isSynced, isFalse);
    });

    test('TripModel fromMap supports legacy local storage format without breaking', () {
      final legacyMap = {
        'id': 'legacy_1697000000',
        'startTime': '2026-10-11T12:00:00.000',
        'endTime': '2026-10-11T12:15:00.000',
        'durationSeconds': 900,
        'distanceMeters': 7500.0,
        'startLat': 13.0827,
        'startLng': 80.2707,
        'endLat': 13.0500,
        'endLng': 80.2400,
      };

      final trip = TripModel.fromMap(legacyMap);
      expect(trip.tripId, 'legacy_1697000000');
      expect(trip.duration, 900);
      expect(trip.distance, 7500.0);
      expect(trip.startLocation.latitude, 13.0827);
      expect(trip.endLocation.latitude, 13.0500);
      expect(trip.avgSpeed, closeTo(30.0, 0.1)); // 7.5km / 15min = 30km/h
    });

    test('TripModel toFirestoreMap generates valid Firestore payload', () {
      final start = DateTime(2026, 10, 11, 14, 0, 0);
      final end = DateTime(2026, 10, 11, 14, 20, 0);

      final trip = TripModel(
        tripId: 'fs_trip_999',
        uid: 'user_fs_1',
        startLocation: const TripLocation(latitude: 12.9, longitude: 80.1),
        endLocation: const TripLocation(latitude: 12.95, longitude: 80.15),
        startTime: start,
        endTime: end,
        distance: 8200.0,
        duration: 1200,
        avgSpeed: 24.6,
      );

      final map = trip.toFirestoreMap(useServerTimestamp: false);
      expect(map['tripId'], 'fs_trip_999');
      expect(map['uid'], 'user_fs_1');
      expect(map['distance'], 8200.0);
      expect(map['duration'], 1200);
      expect(map['avgSpeed'], 24.6);
      expect(map['startLocation']['latitude'], 12.9);
      expect(map['endLocation']['latitude'], 12.95);
    });
  });

  group('Phase 2 - Trip Validation Logic Tests', () {
    test('Rejects incomplete trips with zero distance and duration', () {
      bool isTripValid({required double distanceMeters, required int durationSeconds}) {
        if (durationSeconds <= 0 && distanceMeters <= 0) return false;
        if (distanceMeters < 5 && durationSeconds < 5) return false;
        return true;
      }

      expect(isTripValid(distanceMeters: 0, durationSeconds: 0), isFalse);
      expect(isTripValid(distanceMeters: 2, durationSeconds: 2), isFalse);
      expect(isTripValid(distanceMeters: 100, durationSeconds: 60), isTrue);
      expect(isTripValid(distanceMeters: 2500, durationSeconds: 300), isTrue);
    });

    test('Sorts trips with newest first', () {
      final now = DateTime.now();
      final trips = [
        TripModel(
          tripId: 't1',
          uid: 'u',
          startLocation: const TripLocation(latitude: 0, longitude: 0),
          endLocation: const TripLocation(latitude: 0, longitude: 0),
          startTime: now.subtract(const Duration(days: 2)),
          endTime: now.subtract(const Duration(days: 2, minutes: -20)),
          distance: 1000,
          duration: 1200,
          avgSpeed: 20,
        ),
        TripModel(
          tripId: 't2',
          uid: 'u',
          startLocation: const TripLocation(latitude: 0, longitude: 0),
          endLocation: const TripLocation(latitude: 0, longitude: 0),
          startTime: now,
          endTime: now.add(const Duration(minutes: 15)),
          distance: 2000,
          duration: 900,
          avgSpeed: 25,
        ),
        TripModel(
          tripId: 't3',
          uid: 'u',
          startLocation: const TripLocation(latitude: 0, longitude: 0),
          endLocation: const TripLocation(latitude: 0, longitude: 0),
          startTime: now.subtract(const Duration(hours: 5)),
          endTime: now.subtract(const Duration(hours: 4)),
          distance: 1500,
          duration: 1000,
          avgSpeed: 22,
        ),
      ];

      trips.sort((a, b) => b.startTime.compareTo(a.startTime));

      expect(trips[0].tripId, 't2'); // Newest (today)
      expect(trips[1].tripId, 't3'); // 5 hours ago
      expect(trips[2].tripId, 't1'); // 2 days ago
    });
  });
}
