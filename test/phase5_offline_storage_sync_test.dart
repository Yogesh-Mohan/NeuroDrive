import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:neuro_drive/core/models/trip_model.dart';
import 'package:neuro_drive/core/models/alert_model.dart';
import 'package:neuro_drive/core/services/local_database_service.dart';
import 'package:neuro_drive/core/services/sync_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Phase 5: Offline Storage & Local SQLite Tests', () {
    late LocalDatabaseService localDb;
    late Database testDatabase;

    setUp(() async {
      // Create fresh in-memory SQLite database for each test
      testDatabase = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE trips (
                trip_id TEXT PRIMARY KEY,
                uid TEXT NOT NULL,
                start_lat REAL NOT NULL,
                start_lng REAL NOT NULL,
                start_address TEXT,
                end_lat REAL NOT NULL,
                end_lng REAL NOT NULL,
                end_address TEXT,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                distance REAL NOT NULL,
                duration INTEGER NOT NULL,
                avg_speed REAL NOT NULL,
                created_at TEXT NOT NULL,
                is_synced INTEGER NOT NULL DEFAULT 0,
                sync_error TEXT,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_sync_attempt TEXT
              )
            ''');

            await db.execute('''
              CREATE TABLE alerts (
                id TEXT PRIMARY KEY,
                uid TEXT NOT NULL,
                trip_id TEXT,
                alert_type TEXT NOT NULL,
                severity TEXT NOT NULL,
                message TEXT NOT NULL,
                source TEXT,
                distance REAL,
                relative_speed REAL,
                ttc REAL,
                latitude REAL,
                longitude REAL,
                timestamp TEXT NOT NULL,
                created_at TEXT NOT NULL,
                is_synced INTEGER NOT NULL DEFAULT 0,
                sync_error TEXT,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_sync_attempt TEXT
              )
            ''');

            await db.execute('''
              CREATE TABLE sync_queue (
                id TEXT PRIMARY KEY,
                entity_type TEXT NOT NULL,
                uid TEXT NOT NULL,
                status TEXT NOT NULL,
                retry_count INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
              )
            ''');
          },
        ),
      );

      localDb = LocalDatabaseService(customDb: testDatabase);
    });

    tearDown(() async {
      await testDatabase.close();
    });

    test('Scenario 1: Save Trip while online stores record with is_synced = true', () async {
      final trip = TripModel(
        tripId: 'trip_online_001',
        uid: 'user_123',
        startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
        endLocation: const TripLocation(latitude: 13.0850, longitude: 80.2750),
        startTime: DateTime(2026, 10, 13, 10, 0),
        endTime: DateTime(2026, 10, 13, 10, 30),
        distance: 12500.0,
        duration: 1800,
        avgSpeed: 25.0,
        createdAt: DateTime(2026, 10, 13, 10, 30),
        isSynced: true,
      );

      await localDb.insertTrip(trip);

      final trips = await localDb.getTrips(uid: 'user_123');
      expect(trips.length, 1);
      expect(trips.first.tripId, 'trip_online_001');
      expect(trips.first.isSynced, isTrue);
      expect(trips.first.distance, 12500.0);

      // Verify not in sync queue
      final pendingCount = await localDb.getPendingCount(uid: 'user_123');
      expect(pendingCount, 0);
    });

    test('Scenario 2: Save Trip while offline preserves data locally and queues for sync', () async {
      final trip = TripModel(
        tripId: 'trip_offline_002',
        uid: 'user_123',
        startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
        endLocation: const TripLocation(latitude: 13.0890, longitude: 80.2800),
        startTime: DateTime(2026, 10, 13, 11, 0),
        endTime: DateTime(2026, 10, 13, 11, 15),
        distance: 8200.0,
        duration: 900,
        avgSpeed: 32.8,
        createdAt: DateTime(2026, 10, 13, 11, 15),
        isSynced: false,
      );

      await localDb.insertTrip(trip);

      // Verify trip is accessible
      final trips = await localDb.getTrips(uid: 'user_123');
      expect(trips.length, 1);
      expect(trips.first.isSynced, isFalse);

      // Verify returned by getUnsyncedTrips
      final unsynced = await localDb.getUnsyncedTrips(uid: 'user_123');
      expect(unsynced.length, 1);
      expect(unsynced.first.tripId, 'trip_offline_002');

      // Verify item queued in sync_queue
      final pendingCount = await localDb.getPendingCount(uid: 'user_123');
      expect(pendingCount, 1);
    });

    test('Scenario 3: Save Alert while offline preserves severity, metrics, and queues for sync', () async {
      final alert = AlertModel(
        id: 'alert_offline_001',
        tripId: 'trip_offline_002',
        alertType: 'CRITICAL_COLLISION_ALERT',
        severity: 'critical',
        message: 'Collision Warning: Forward vehicle stopping abruptly',
        distance: 14.5,
        relativeSpeed: -18.2,
        ttc: 2.1,
        latitude: 13.0850,
        longitude: 80.2750,
        timestamp: DateTime(2026, 10, 13, 11, 10),
        createdAt: DateTime(2026, 10, 13, 11, 10),
        isSynced: false,
      );

      await localDb.insertAlert(alert, uid: 'user_123');

      final alerts = await localDb.getAlerts(uid: 'user_123');
      expect(alerts.length, 1);
      expect(alerts.first.id, 'alert_offline_001');
      expect(alerts.first.tripId, 'trip_offline_002');
      expect(alerts.first.severity, 'critical');
      expect(alerts.first.distance, 14.5);
      expect(alerts.first.ttc, 2.1);
      expect(alerts.first.isSynced, isFalse);

      // Verify in unsynced list
      final unsynced = await localDb.getUnsyncedAlerts(uid: 'user_123');
      expect(unsynced.length, 1);
      expect(unsynced.first.id, 'alert_offline_001');

      // Pending queue count should reflect alert
      final pendingCount = await localDb.getPendingCount(uid: 'user_123');
      expect(pendingCount, 1);
    });

    test('Scenario 4: App restart preserves pending trips, alerts, and queue status', () async {
      // 1. Insert offline trip and alert
      final trip = TripModel(
        tripId: 'trip_restart_test',
        uid: 'user_123',
        startLocation: const TripLocation(latitude: 13.0, longitude: 80.0),
        endLocation: const TripLocation(latitude: 13.1, longitude: 80.1),
        startTime: DateTime(2026, 10, 13, 9, 0),
        endTime: DateTime(2026, 10, 13, 9, 20),
        distance: 5000.0,
        duration: 1200,
        avgSpeed: 15.0,
        isSynced: false,
      );
      await localDb.insertTrip(trip);

      final alert = AlertModel(
        id: 'alert_restart_test',
        tripId: 'trip_restart_test',
        alertType: 'COLLISION_WARNING',
        severity: 'warning',
        message: 'Approaching vehicle ahead',
        timestamp: DateTime(2026, 10, 13, 9, 10),
        isSynced: false,
      );
      await localDb.insertAlert(alert, uid: 'user_123');

      expect(await localDb.getPendingCount(uid: 'user_123'), 2);

      // 2. Simulate app restart: re-instantiate LocalDatabaseService with same DB
      final restartedLocalDb = LocalDatabaseService(customDb: testDatabase);

      final retrievedTrips = await restartedLocalDb.getTrips(uid: 'user_123');
      expect(retrievedTrips.length, 1);
      expect(retrievedTrips.first.tripId, 'trip_restart_test');
      expect(retrievedTrips.first.isSynced, isFalse);

      final retrievedAlerts = await restartedLocalDb.getAlerts(uid: 'user_123');
      expect(retrievedAlerts.length, 1);
      expect(retrievedAlerts.first.id, 'alert_restart_test');
      expect(retrievedAlerts.first.isSynced, isFalse);

      final queueCount = await restartedLocalDb.getPendingCount(uid: 'user_123');
      expect(queueCount, 2);
    });

    test('Scenario 5: Successful sync updates is_synced to true and clears queue', () async {
      final trip = TripModel(
        tripId: 'trip_sync_test',
        uid: 'user_123',
        startLocation: const TripLocation(latitude: 13.0, longitude: 80.0),
        endLocation: const TripLocation(latitude: 13.1, longitude: 80.1),
        startTime: DateTime(2026, 10, 13, 8, 0),
        endTime: DateTime(2026, 10, 13, 8, 15),
        distance: 4000.0,
        duration: 900,
        avgSpeed: 16.0,
        isSynced: false,
      );
      await localDb.insertTrip(trip);

      expect(await localDb.getPendingCount(uid: 'user_123'), 1);

      // Simulate successful cloud sync
      await localDb.updateTripSyncStatus('trip_sync_test', isSynced: true);

      final trips = await localDb.getTrips(uid: 'user_123');
      expect(trips.first.isSynced, isTrue);

      final unsynced = await localDb.getUnsyncedTrips(uid: 'user_123');
      expect(unsynced.isEmpty, isTrue);

      final pendingCount = await localDb.getPendingCount(uid: 'user_123');
      expect(pendingCount, 0);
    });

    test('Scenario 6: Idempotent writes prevent duplicate records on repeated inserts', () async {
      final trip = TripModel(
        tripId: 'trip_idempotent_test',
        uid: 'user_123',
        startLocation: const TripLocation(latitude: 13.0, longitude: 80.0),
        endLocation: const TripLocation(latitude: 13.1, longitude: 80.1),
        startTime: DateTime(2026, 10, 13, 8, 0),
        endTime: DateTime(2026, 10, 13, 8, 15),
        distance: 4000.0,
        duration: 900,
        avgSpeed: 16.0,
        isSynced: false,
      );

      // Insert three times in a row
      await localDb.insertTrip(trip);
      await localDb.insertTrip(trip);
      await localDb.insertTrip(trip);

      final trips = await localDb.getTrips(uid: 'user_123');
      expect(trips.length, 1, reason: 'Duplicate tripId must not produce multiple rows');

      final queueItems = await localDb.getPendingQueueItems(uid: 'user_123');
      expect(queueItems.length, 1, reason: 'Queue must contain exactly 1 entry for tripId');
    });

    test('Scenario 7: Cloud sync failure retains local record, increments retry count, and logs error', () async {
      final trip = TripModel(
        tripId: 'trip_fail_test',
        uid: 'user_123',
        startLocation: const TripLocation(latitude: 13.0, longitude: 80.0),
        endLocation: const TripLocation(latitude: 13.1, longitude: 80.1),
        startTime: DateTime(2026, 10, 13, 8, 0),
        endTime: DateTime(2026, 10, 13, 8, 15),
        distance: 4000.0,
        duration: 900,
        avgSpeed: 16.0,
        isSynced: false,
      );
      await localDb.insertTrip(trip);

      // Simulate cloud failure
      await localDb.updateTripSyncStatus(
        'trip_fail_test',
        isSynced: false,
        syncError: 'SocketException: Network is unreachable',
        retryCount: 1,
      );

      final trips = await localDb.getTrips(uid: 'user_123');
      expect(trips.first.isSynced, isFalse);
      expect(trips.first.retryCount, 1);
      expect(trips.first.syncError, contains('Network is unreachable'));

      // Still in unsynced and pending queue
      final unsynced = await localDb.getUnsyncedTrips(uid: 'user_123');
      expect(unsynced.length, 1);
      expect(await localDb.getPendingCount(uid: 'user_123'), 1);
    });

    test('Scenario 8: Multi-user isolation guarantees users access only their own records', () async {
      final tripA = TripModel(
        tripId: 'trip_user_alpha',
        uid: 'user_alpha',
        startLocation: const TripLocation(latitude: 13.0, longitude: 80.0),
        endLocation: const TripLocation(latitude: 13.1, longitude: 80.1),
        startTime: DateTime(2026, 10, 13, 8, 0),
        endTime: DateTime(2026, 10, 13, 8, 15),
        distance: 4000.0,
        duration: 900,
        avgSpeed: 16.0,
        isSynced: false,
      );

      final tripB = TripModel(
        tripId: 'trip_user_beta',
        uid: 'user_beta',
        startLocation: const TripLocation(latitude: 12.9, longitude: 79.9),
        endLocation: const TripLocation(latitude: 12.95, longitude: 79.95),
        startTime: DateTime(2026, 10, 13, 8, 30),
        endTime: DateTime(2026, 10, 13, 8, 45),
        distance: 3500.0,
        duration: 900,
        avgSpeed: 14.0,
        isSynced: false,
      );

      await localDb.insertTrip(tripA);
      await localDb.insertTrip(tripB);

      final tripsAlpha = await localDb.getTrips(uid: 'user_alpha');
      expect(tripsAlpha.length, 1);
      expect(tripsAlpha.first.tripId, 'trip_user_alpha');

      final tripsBeta = await localDb.getTrips(uid: 'user_beta');
      expect(tripsBeta.length, 1);
      expect(tripsBeta.first.tripId, 'trip_user_beta');

      // Clear User Alpha's trips
      await localDb.clearAllTrips(uid: 'user_alpha');

      expect((await localDb.getTrips(uid: 'user_alpha')).isEmpty, isTrue);
      // User Beta's trips must remain completely intact
      expect((await localDb.getTrips(uid: 'user_beta')).length, 1);
    });

    test('Scenario 9: Empty queue handled gracefully with zero pending items', () async {
      final unsynced = await localDb.getUnsyncedTrips(uid: 'user_empty');
      expect(unsynced.isEmpty, isTrue);

      final unsyncedAlerts = await localDb.getUnsyncedAlerts(uid: 'user_empty');
      expect(unsyncedAlerts.isEmpty, isTrue);

      final count = await localDb.getPendingCount(uid: 'user_empty');
      expect(count, 0);
    });

    test('Scenario 10: Successful retry clears error and retry metadata', () async {
      final trip = TripModel(
        tripId: 'trip_retry_reset',
        uid: 'user_123',
        startLocation: const TripLocation(latitude: 13.0, longitude: 80.0),
        endLocation: const TripLocation(latitude: 13.1, longitude: 80.1),
        startTime: DateTime(2026, 10, 13, 8, 0),
        endTime: DateTime(2026, 10, 13, 8, 15),
        distance: 4000.0,
        duration: 900,
        avgSpeed: 16.0,
        isSynced: false,
      );
      await localDb.insertTrip(trip);

      await localDb.updateTripSyncStatus(
        trip.tripId,
        isSynced: false,
        syncError: 'Temporary network failure',
        retryCount: 3,
      );
      await localDb.updateTripSyncStatus(trip.tripId, isSynced: true);

      final stored = (await localDb.getTrips(uid: 'user_123')).single;
      expect(stored.isSynced, isTrue);
      expect(stored.syncError, isNull);
      expect(stored.retryCount, 0);
      expect(await localDb.getPendingCount(uid: 'user_123'), 0);
    });
  });

  group('Phase 5: Conflict and retry policy', () {
    test('Newer cloud records win over older local records', () {
      final localCreatedAt = DateTime(2026, 10, 13, 10, 0);
      final newerCloudCreatedAt = DateTime(2026, 10, 13, 10, 1);

      expect(
        SyncService.shouldUploadLocalRecord(
          localCreatedAt: localCreatedAt,
          cloudCreatedAt: newerCloudCreatedAt,
        ),
        isFalse,
      );
      expect(
        SyncService.shouldUploadLocalRecord(
          localCreatedAt: newerCloudCreatedAt,
          cloudCreatedAt: localCreatedAt,
        ),
        isTrue,
      );
      expect(
        SyncService.shouldUploadLocalRecord(
          localCreatedAt: localCreatedAt,
          cloudCreatedAt: null,
        ),
        isTrue,
      );
    });
  });
}
