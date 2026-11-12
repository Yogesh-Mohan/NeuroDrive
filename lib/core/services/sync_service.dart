import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'local_database_service.dart';
import 'connectivity_service.dart';

enum SyncState { idle, syncing, success, failed }

class SyncResult {
  final bool success;
  final int tripsSynced;
  final int alertsSynced;
  final int failedCount;
  final List<String> errors;

  const SyncResult({
    required this.success,
    this.tripsSynced = 0,
    this.alertsSynced = 0,
    this.failedCount = 0,
    this.errors = const [],
  });

  int get totalSynced => tripsSynced + alertsSynced;
}

class SyncService {
  static const int maxAutomaticRetries = 5;

  static final SyncService _instance = SyncService._internal();
  factory SyncService({
    LocalDatabaseService? databaseService,
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    ConnectivityService? connectivityService,
  }) {
    if (databaseService != null) {
      _instance._db = databaseService;
    }
    if (firestore != null) {
      _instance._firestore = firestore;
    }
    if (auth != null) {
      _instance._auth = auth;
    }
    if (connectivityService != null) {
      _instance._connectivity = connectivityService;
    }
    return _instance;
  }
  SyncService._internal() {
    _init();
  }

  LocalDatabaseService _db = LocalDatabaseService();
  FirebaseFirestore _firestore = FirebaseFirestore.instance;
  FirebaseAuth _auth = FirebaseAuth.instance;
  ConnectivityService _connectivity = ConnectivityService();

  bool _isSyncInProgress = false;
  bool get isSyncInProgress => _isSyncInProgress;

  SyncState _currentState = SyncState.idle;
  SyncState get currentSyncState => _currentState;

  final StreamController<SyncState> _syncStateController =
      StreamController<SyncState>.broadcast();
  Stream<SyncState> get syncStateStream => _syncStateController.stream;

  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<User?>? _authSubscription;

  void _init() {
    // Automatically trigger synchronization when verified internet access returns
    _connectivitySubscription = _connectivity.onInternetConnectionChanged.listen((
      isOnline,
    ) {
      if (isOnline) {
        debugPrint(
          '[SyncService] Verified internet restored. Triggering automatic background sync...',
        );
        unawaited(
          syncAll().catchError((e) {
            debugPrint('[SyncService] Automatic sync encountered error: $e');
            return SyncResult(success: false, errors: [e.toString()]);
          }),
        );
      }
    });

    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user == null) return;
      unawaited(_syncAuthenticatedUser(user.uid));
    });
  }

  Future<void> _syncAuthenticatedUser(String uid) async {
    try {
      await _db.migrateFromSharedPreferences(uid);
      await syncAll(uid: uid);
    } catch (e) {
      debugPrint('[SyncService] Authenticated-user sync failed: $e');
    }
  }

  String? get currentUid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _userTripsRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('trips');
  }

  CollectionReference<Map<String, dynamic>> _userAlertsRef(String uid) {
    return _firestore.collection('users').doc(uid).collection('alerts');
  }

  void _setState(SyncState state) {
    _currentState = state;
    _syncStateController.add(state);
  }

  /// Get count of pending unsynchronized items
  Future<int> getPendingCount({String? uid}) async {
    final targetUid = uid ?? currentUid;
    return await _db.getPendingCount(uid: targetUid);
  }

  /// Main synchronization method: idempotent, atomic status updates, duplicate-safe
  Future<SyncResult> syncAll({String? uid, bool force = false}) async {
    // 1. Concurrency guard to strictly prevent duplicate sync runs
    if (_isSyncInProgress) {
      debugPrint(
        '[SyncService] Sync already in progress. Skipping redundant request.',
      );
      return const SyncResult(
        success: false,
        errors: ['Sync already in progress'],
      );
    }

    // 2. Connectivity verification
    if (!force) {
      final hasInternet = await _connectivity.checkRealInternet();
      if (!hasInternet) {
        debugPrint(
          '[SyncService] No internet access. Retaining records locally.',
        );
        return const SyncResult(success: false, errors: ['No internet access']);
      }
    }

    final targetUid = uid ?? currentUid;
    if (targetUid == null || currentUid != targetUid) {
      debugPrint(
        '[SyncService] No authenticated user. Offline sync postponed.',
      );
      return const SyncResult(success: false, errors: ['User unauthenticated']);
    }

    _isSyncInProgress = true;
    _setState(SyncState.syncing);

    int tripsSynced = 0;
    int alertsSynced = 0;
    int failedCount = 0;
    final List<String> errorLogs = [];

    try {
      // 3. Sync Unsynced Trips
      final unsyncedTrips = await _db.getUnsyncedTrips(uid: targetUid);
      debugPrint(
        '[SyncService] Found ${unsyncedTrips.length} unsynced trips for $targetUid',
      );

      for (final trip in unsyncedTrips) {
        if (currentUid != targetUid) {
          errorLogs.add('Sync stopped because the authenticated user changed.');
          failedCount++;
          break;
        }
        if (trip.uid != targetUid) {
          failedCount++;
          errorLogs.add(
            'Skipped trip ${trip.tripId}: local owner does not match authenticated user.',
          );
          continue;
        }
        if (!force && trip.retryCount >= maxAutomaticRetries) {
          failedCount++;
          errorLogs.add(
            'Retry limit reached for trip ${trip.tripId}. Manual retry required.',
          );
          continue;
        }
        try {
          final docRef = _userTripsRef(targetUid).doc(trip.tripId);
          final existing = await docRef.get().timeout(
            const Duration(seconds: 10),
          );
          final existingCreatedAt = _readDate(existing.data()?['createdAt']);
          if (existing.exists &&
              !_shouldUploadLocalRecord(
                localCreatedAt: trip.createdAt,
                cloudCreatedAt: existingCreatedAt,
              )) {
            await _db.updateTripSyncStatus(trip.tripId, isSynced: true);
            continue;
          }
          await docRef
              .set(
                trip.toFirestoreMap(useServerTimestamp: false),
                SetOptions(merge: true),
              )
              .timeout(const Duration(seconds: 10));

          // Mark as synchronized in SQLite ONLY AFTER cloud write succeeds
          await _db.updateTripSyncStatus(
            trip.tripId,
            isSynced: true,
            syncError: null,
          );
          tripsSynced++;
          debugPrint('[SyncService] Successfully synced trip ${trip.tripId}');
        } catch (e) {
          failedCount++;
          final errorMsg = 'Failed to sync trip ${trip.tripId}: $e';
          errorLogs.add(errorMsg);
          debugPrint('[SyncService] $errorMsg');

          // Increment retry count and preserve in local database
          await _db.updateTripSyncStatus(
            trip.tripId,
            isSynced: false,
            syncError: e.toString(),
            retryCount: trip.retryCount + 1,
          );
        }
      }

      // 4. Sync Unsynced Alerts
      final unsyncedAlerts = await _db.getUnsyncedAlerts(uid: targetUid);
      debugPrint(
        '[SyncService] Found ${unsyncedAlerts.length} unsynced alerts for $targetUid',
      );

      for (final alert in unsyncedAlerts) {
        if (currentUid != targetUid) {
          errorLogs.add('Sync stopped because the authenticated user changed.');
          failedCount++;
          break;
        }
        if (alert.retryCount >= maxAutomaticRetries && !force) {
          failedCount++;
          errorLogs.add(
            'Retry limit reached for alert ${alert.id}. Manual retry required.',
          );
          continue;
        }
        try {
          final docRef = _userAlertsRef(targetUid).doc(alert.id);
          final existing = await docRef.get().timeout(
            const Duration(seconds: 10),
          );
          final existingCreatedAt = _readDate(existing.data()?['createdAt']);
          if (existing.exists &&
              !_shouldUploadLocalRecord(
                localCreatedAt: alert.createdAt,
                cloudCreatedAt: existingCreatedAt,
              )) {
            await _db.updateAlertSyncStatus(alert.id, isSynced: true);
            continue;
          }
          await docRef
              .set(
                alert.toFirestoreMap(useServerTimestamp: false),
                SetOptions(merge: true),
              )
              .timeout(const Duration(seconds: 10));

          // Mark as synchronized in SQLite ONLY AFTER cloud write succeeds
          await _db.updateAlertSyncStatus(
            alert.id,
            isSynced: true,
            syncError: null,
          );
          alertsSynced++;
          debugPrint('[SyncService] Successfully synced alert ${alert.id}');
        } catch (e) {
          failedCount++;
          final errorMsg = 'Failed to sync alert ${alert.id}: $e';
          errorLogs.add(errorMsg);
          debugPrint('[SyncService] $errorMsg');

          await _db.updateAlertSyncStatus(
            alert.id,
            isSynced: false,
            syncError: e.toString(),
            retryCount: alert.retryCount + 1,
          );
        }
      }

      final isOverallSuccess = failedCount == 0;
      _setState(isOverallSuccess ? SyncState.success : SyncState.failed);

      return SyncResult(
        success: isOverallSuccess,
        tripsSynced: tripsSynced,
        alertsSynced: alertsSynced,
        failedCount: failedCount,
        errors: errorLogs,
      );
    } catch (globalErr) {
      debugPrint('[SyncService] Global synchronization error: $globalErr');
      _setState(SyncState.failed);
      return SyncResult(
        success: false,
        tripsSynced: tripsSynced,
        alertsSynced: alertsSynced,
        failedCount: failedCount + 1,
        errors: [globalErr.toString()],
      );
    } finally {
      _isSyncInProgress = false;
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _authSubscription?.cancel();
    _syncStateController.close();
  }

  @visibleForTesting
  static bool shouldUploadLocalRecord({
    required DateTime? localCreatedAt,
    required DateTime? cloudCreatedAt,
  }) {
    if (cloudCreatedAt == null) return true;
    if (localCreatedAt == null) return false;
    return !cloudCreatedAt.isAfter(localCreatedAt);
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static bool _shouldUploadLocalRecord({
    required DateTime? localCreatedAt,
    required DateTime? cloudCreatedAt,
  }) {
    return shouldUploadLocalRecord(
      localCreatedAt: localCreatedAt,
      cloudCreatedAt: cloudCreatedAt,
    );
  }
}
