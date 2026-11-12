import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_model.dart';
import 'local_database_service.dart';
import 'sync_service.dart';

class TripService {
  static final TripService _instance = TripService._internal();
  factory TripService({LocalDatabaseService? localDb}) {
    if (localDb != null) _instance._localDb = localDb;
    return _instance;
  }
  TripService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  LocalDatabaseService _localDb = LocalDatabaseService();

  String? get currentUid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _userTripsRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('trips');
  }

  /// Real-time stream of trips for the current authenticated user ordered by startTime descending
  Stream<List<TripModel>> getTripsStream() {
    final uid = currentUid;
    if (uid == null) {
      return Stream.value([]);
    }

    return _userTripsRef(
      uid,
    ).orderBy('startTime', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => TripModel.fromFirestore(doc)).toList();
    });
  }

  /// Fetch trips combining Cloud Firestore with local SQLite cache & sync pending trips
  Future<List<TripModel>> getTrips() async {
    final uid = currentUid;
    if (uid == null) {
      return _getLocalTrips('guest_driver');
    }

    // Attempt background sync of unsynced offline trips first
    syncOfflineTrips().catchError((e) {
      debugPrint('Sync offline trips failed in background: $e');
    });

    List<TripModel> cloudTrips = [];
    try {
      final querySnapshot = await _userTripsRef(uid)
          .orderBy('startTime', descending: true)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 8));

      cloudTrips = querySnapshot.docs
          .map((doc) => TripModel.fromFirestore(doc))
          .toList();

      if (cloudTrips.isNotEmpty) {
        // Cache trips in SQLite local database and SharedPreferences
        for (final t in cloudTrips) {
          try {
            await _localDb.insertTrip(t);
          } catch (_) {}
        }
        await _cacheTripsLocally(uid, cloudTrips);
      }
    } catch (e) {
      debugPrint('Firestore getTrips failed (offline or network issue): $e');
    }

    // Always fetch all local SQLite trips to ensure unsynced / local trips are included
    List<TripModel> localTrips = [];
    try {
      localTrips = await _localDb.getTrips(uid: uid);
    } catch (e) {
      debugPrint('SQLite getTrips failed: $e');
    }

    if (localTrips.isEmpty) {
      localTrips = await _getLocalTrips(uid);
    }

    // Merge without duplicates (favoring local for pending sync states or cloud for confirmed)
    final Map<String, TripModel> mergedMap = {};
    for (final t in cloudTrips) {
      mergedMap[t.tripId] = t;
    }
    for (final t in localTrips) {
      if (!mergedMap.containsKey(t.tripId) || !t.isSynced) {
        mergedMap[t.tripId] = t;
      }
    }

    final result = mergedMap.values.toList();
    result.sort((a, b) => b.startTime.compareTo(a.startTime));
    return result;
  }

  /// Save completed trip with cloud-first, local-fallback, offline-queue guarantee
  Future<TripModel> saveCompletedTrip({
    required DateTime startTime,
    required DateTime endTime,
    required double distanceMeters,
    required int durationSeconds,
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    double? avgSpeedKmh,
  }) async {
    final uid = currentUid ?? 'guest_driver';

    // Ensure at least 1 second or minimum distance if trip completed
    final effDuration = durationSeconds <= 0 ? 1 : durationSeconds;
    final effDistance = distanceMeters;

    // Calculate reliable avg speed if not provided
    final calculatedSpeed = (avgSpeedKmh != null && avgSpeedKmh > 0)
        ? avgSpeedKmh
        : (effDuration > 0 ? (effDistance / effDuration) * 3.6 : 0.0);

    // Generate unique trip document reference & ID
    final docRef = _userTripsRef(uid).doc();
    final tripId = docRef.id;

    final trip = TripModel(
      tripId: tripId,
      uid: uid,
      startLocation: TripLocation(latitude: startLat, longitude: startLng),
      endLocation: TripLocation(latitude: endLat, longitude: endLng),
      startTime: startTime,
      endTime: endTime,
      distance: distanceMeters,
      duration: effDuration,
      avgSpeed: calculatedSpeed,
      createdAt: DateTime.now(),
      isSynced: false,
    );

    // 1. Save to SQLite database first (and queue for sync)
    try {
      await _localDb.insertTrip(trip);
    } catch (e) {
      debugPrint('SQLite insertTrip failed: $e');
    }
    // Backup to SharedPreferences
    await _saveTripLocally(uid, trip);

    // Guest records remain local-only and are never uploaded to another user's account.
    if (currentUid == null) {
      return trip;
    }

    // 2. Save to Firestore
    try {
      await docRef
          .set(trip.toFirestoreMap(useServerTimestamp: true))
          .timeout(const Duration(seconds: 10));
      // Mark as synced locally in SQLite & SharedPreferences
      final syncedTrip = trip.copyWith(isSynced: true);
      try {
        await _localDb.updateTripSyncStatus(tripId, isSynced: true);
      } catch (_) {}
      await _updateLocalTrip(uid, syncedTrip);
      debugPrint('Trip $tripId successfully saved to Firestore.');
      return syncedTrip;
    } catch (e) {
      debugPrint(
        'Cloud save failed for trip $tripId: $e. Trip preserved locally.',
      );
      try {
        await _localDb.updateTripSyncStatus(
          tripId,
          isSynced: false,
          syncError: e.toString(),
        );
      } catch (_) {}
      return trip;
    }
  }

  /// Sync all locally stored trips marked with isSynced == false to Firestore
  Future<void> syncOfflineTrips() async {
    final uid = currentUid;
    if (uid == null) return;

    // Delegate to unified SyncService
    try {
      await SyncService().syncAll(uid: uid);
    } catch (e) {
      debugPrint('SyncService.syncAll failed for trips: $e');
    }

    // Secondary fallback sync from SharedPreferences if any legacy trips remain
    final localTrips = await _getLocalTrips(uid);
    final unsyncedTrips = localTrips.where((t) => !t.isSynced).toList();

    if (unsyncedTrips.isEmpty) return;
    debugPrint(
      'Found ${unsyncedTrips.length} legacy unsynced trips. Attempting sync...',
    );

    for (final trip in unsyncedTrips) {
      try {
        final docRef = _userTripsRef(uid).doc(trip.tripId);
        await docRef.set(
          trip.toFirestoreMap(useServerTimestamp: false),
          SetOptions(merge: true),
        );
        final synced = trip.copyWith(isSynced: true);
        await _updateLocalTrip(uid, synced);
        try {
          await _localDb.updateTripSyncStatus(trip.tripId, isSynced: true);
        } catch (_) {}
        debugPrint('Successfully synchronized offline trip ${trip.tripId}');
      } catch (e) {
        debugPrint('Failed to sync trip ${trip.tripId}: $e');
      }
    }
  }

  /// Clear user's trip history (both local and cloud)
  Future<void> clearAllTrips() async {
    final uid = currentUid;
    if (uid == null) return;

    // Clear SQLite local database
    try {
      await _localDb.clearAllTrips(uid: uid);
    } catch (e) {
      debugPrint('Failed to clear SQLite trips: $e');
    }

    // Clear locally in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('neurodrive_trips_$uid');

    // Clear Firestore collection
    try {
      final snapshot = await _userTripsRef(uid).get();
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      debugPrint('All Firestore trips cleared for $uid');
    } catch (e) {
      debugPrint('Failed to clear Firestore trips: $e');
    }
  }

  // --- Local SharedPreferences Helpers ---

  Future<List<TripModel>> _getLocalTrips(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tripsStr = prefs.getStringList('neurodrive_trips_$uid') ?? [];
      final trips = tripsStr.map((t) {
        final map = json.decode(t) as Map<String, dynamic>;
        return TripModel.fromMap(map);
      }).toList();
      trips.sort((a, b) => b.startTime.compareTo(a.startTime));
      return trips;
    } catch (e) {
      debugPrint('Failed to read local trips: $e');
      return [];
    }
  }

  Future<void> _saveTripLocally(String uid, TripModel trip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tripsStr = prefs.getStringList('neurodrive_trips_$uid') ?? [];

      // Avoid duplicates
      final exists = tripsStr.any((t) {
        final map = json.decode(t) as Map<String, dynamic>;
        return (map['tripId'] ?? map['id']) == trip.tripId;
      });

      if (!exists) {
        tripsStr.add(json.encode(trip.toJsonMap()));
        await prefs.setStringList('neurodrive_trips_$uid', tripsStr);
      }
    } catch (e) {
      debugPrint('Failed to write local trip: $e');
    }
  }

  Future<void> _updateLocalTrip(String uid, TripModel trip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tripsStr = prefs.getStringList('neurodrive_trips_$uid') ?? [];
      final updatedList = <String>[];

      for (final t in tripsStr) {
        final map = json.decode(t) as Map<String, dynamic>;
        if ((map['tripId'] ?? map['id']) == trip.tripId) {
          updatedList.add(json.encode(trip.toJsonMap()));
        } else {
          updatedList.add(t);
        }
      }

      await prefs.setStringList('neurodrive_trips_$uid', updatedList);
    } catch (e) {
      debugPrint('Failed to update local trip: $e');
    }
  }

  Future<void> _cacheTripsLocally(
    String uid,
    List<TripModel> cloudTrips,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Keep any unsynced local trips intact
      final existingLocal = await _getLocalTrips(uid);
      final unsynced = existingLocal.where((t) => !t.isSynced).toList();

      final merged = <String, TripModel>{};
      for (final t in cloudTrips) {
        merged[t.tripId] = t;
      }
      for (final t in unsynced) {
        merged[t.tripId] = t;
      }

      final resultList = merged.values.toList();
      resultList.sort((a, b) => b.startTime.compareTo(a.startTime));

      final serialized = resultList
          .map((t) => json.encode(t.toJsonMap()))
          .toList();
      await prefs.setStringList('neurodrive_trips_$uid', serialized);
    } catch (e) {
      debugPrint('Failed to cache trips locally: $e');
    }
  }
}
