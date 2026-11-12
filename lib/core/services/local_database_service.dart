import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/trip_model.dart';
import '../models/alert_model.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService({Database? customDb, DatabaseFactory? customFactory}) {
    if (customDb != null) {
      _instance._database = customDb;
    }
    if (customFactory != null) {
      _instance._customFactory = customFactory;
    }
    return _instance;
  }
  LocalDatabaseService._internal();

  static const String _dbName = 'neurodrive_local.db';
  static const int _dbVersion = 1;

  static const String tableTrips = 'trips';
  static const String tableAlerts = 'alerts';
  static const String tableSyncQueue = 'sync_queue';

  Database? _database;
  DatabaseFactory? _customFactory;

  /// Visible for testing to reset or inject test database
  @visibleForTesting
  void setDatabase(Database? db) {
    _database = db;
  }

  /// Visible for testing to inject custom factory
  @visibleForTesting
  void setFactory(DatabaseFactory? factory) {
    _customFactory = factory;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final factory = _customFactory ?? databaseFactory;
    final dbPath = await factory.getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);

    return await factory.openDatabase(
      fullPath,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('Creating local SQLite database v$version...');

    // Trips Table
    await db.execute('''
      CREATE TABLE $tableTrips (
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

    // Alerts Table
    await db.execute('''
      CREATE TABLE $tableAlerts (
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

    // Sync Queue Table
    await db.execute('''
      CREATE TABLE $tableSyncQueue (
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

    // Indexes for fast lookup
    await db.execute('CREATE INDEX idx_trips_uid ON $tableTrips(uid)');
    await db.execute('CREATE INDEX idx_trips_synced ON $tableTrips(is_synced)');
    await db.execute('CREATE INDEX idx_alerts_uid ON $tableAlerts(uid)');
    await db.execute('CREATE INDEX idx_alerts_synced ON $tableAlerts(is_synced)');
    await db.execute('CREATE INDEX idx_queue_status ON $tableSyncQueue(status)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('Upgrading database from $oldVersion to $newVersion');
    // Future migrations go here
  }

  // ==========================================
  // TRIPS STORAGE METHODS
  // ==========================================

  /// Insert or replace a trip in SQLite
  Future<void> insertTrip(TripModel trip) async {
    final db = await database;
    await db.insert(
      tableTrips,
      trip.toSqlMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Queue if not synced
    if (!trip.isSynced) {
      await queueItem(
        id: trip.tripId,
        entityType: 'trip',
        uid: trip.uid,
      );
    }
  }

  /// Retrieve all trips for a specific user (or all if uid is null)
  Future<List<TripModel>> getTrips({String? uid}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableTrips,
      where: uid != null ? 'uid = ?' : null,
      whereArgs: uid != null ? [uid] : null,
      orderBy: 'start_time DESC',
    );

    return maps.map((m) => TripModel.fromSqlMap(m)).toList();
  }

  /// Retrieve only unsynchronized trips
  Future<List<TripModel>> getUnsyncedTrips({String? uid}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableTrips,
      where: uid != null ? 'is_synced = 0 AND uid = ?' : 'is_synced = 0',
      whereArgs: uid != null ? [uid] : null,
      orderBy: 'start_time ASC',
    );

    return maps.map((m) => TripModel.fromSqlMap(m)).toList();
  }

  /// Update trip synchronization status
  Future<void> updateTripSyncStatus(
    String tripId, {
    required bool isSynced,
    String? syncError,
    int? retryCount,
    DateTime? lastSyncAttempt,
  }) async {
    final db = await database;
    final Map<String, dynamic> updates = {
      'is_synced': isSynced ? 1 : 0,
      'sync_error': isSynced ? null : syncError,
      'retry_count': isSynced ? 0 : (retryCount ?? 0),
      'last_sync_attempt': (lastSyncAttempt ?? DateTime.now()).toIso8601String(),
    };

    await db.update(
      tableTrips,
      updates,
      where: 'trip_id = ?',
      whereArgs: [tripId],
    );

    if (isSynced) {
      await removeFromQueue(tripId);
    } else {
      await updateQueueStatus(
        id: tripId,
        status: 'failed',
        error: syncError,
        retryCount: retryCount,
      );
    }
  }

  /// Delete a single trip
  Future<void> deleteTrip(String tripId) async {
    final db = await database;
    await db.delete(tableTrips, where: 'trip_id = ?', whereArgs: [tripId]);
    await removeFromQueue(tripId);
  }

  /// Clear all trips (optionally filtered by uid)
  Future<void> clearAllTrips({String? uid}) async {
    final db = await database;
    if (uid != null) {
      await db.delete(tableTrips, where: 'uid = ?', whereArgs: [uid]);
      await db.delete(tableSyncQueue, where: 'uid = ? AND entity_type = ?', whereArgs: [uid, 'trip']);
    } else {
      await db.delete(tableTrips);
      await db.delete(tableSyncQueue, where: 'entity_type = ?', whereArgs: ['trip']);
    }
  }

  // ==========================================
  // ALERTS STORAGE METHODS
  // ==========================================

  /// Insert or replace an alert in SQLite
  Future<void> insertAlert(AlertModel alert, {required String uid}) async {
    final db = await database;
    await db.insert(
      tableAlerts,
      alert.toSqlMap(uid: uid),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Queue if not synced
    if (!alert.isSynced) {
      await queueItem(
        id: alert.id,
        entityType: 'alert',
        uid: uid,
      );
    }
  }

  /// Retrieve all alerts for a specific user
  Future<List<AlertModel>> getAlerts({String? uid}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableAlerts,
      where: uid != null ? 'uid = ?' : null,
      whereArgs: uid != null ? [uid] : null,
      orderBy: 'timestamp DESC',
    );

    return maps.map((m) => AlertModel.fromSqlMap(m)).toList();
  }

  /// Retrieve only unsynchronized alerts
  Future<List<AlertModel>> getUnsyncedAlerts({String? uid}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableAlerts,
      where: uid != null ? 'is_synced = 0 AND uid = ?' : 'is_synced = 0',
      whereArgs: uid != null ? [uid] : null,
      orderBy: 'timestamp ASC',
    );

    return maps.map((m) => AlertModel.fromSqlMap(m)).toList();
  }

  /// Update alert synchronization status
  Future<void> updateAlertSyncStatus(
    String alertId, {
    required bool isSynced,
    String? syncError,
    int? retryCount,
    DateTime? lastSyncAttempt,
  }) async {
    final db = await database;
    final Map<String, dynamic> updates = {
      'is_synced': isSynced ? 1 : 0,
      'sync_error': isSynced ? null : syncError,
      'retry_count': isSynced ? 0 : (retryCount ?? 0),
      'last_sync_attempt': (lastSyncAttempt ?? DateTime.now()).toIso8601String(),
    };

    await db.update(
      tableAlerts,
      updates,
      where: 'id = ?',
      whereArgs: [alertId],
    );

    if (isSynced) {
      await removeFromQueue(alertId);
    } else {
      await updateQueueStatus(
        id: alertId,
        status: 'failed',
        error: syncError,
        retryCount: retryCount,
      );
    }
  }

  /// Clear all alerts
  Future<void> clearAllAlerts({String? uid}) async {
    final db = await database;
    if (uid != null) {
      await db.delete(tableAlerts, where: 'uid = ?', whereArgs: [uid]);
      await db.delete(tableSyncQueue, where: 'uid = ? AND entity_type = ?', whereArgs: [uid, 'alert']);
    } else {
      await db.delete(tableAlerts);
      await db.delete(tableSyncQueue, where: 'entity_type = ?', whereArgs: ['alert']);
    }
  }

  // ==========================================
  // SYNC QUEUE MANAGEMENT
  // ==========================================

  /// Add entity to sync queue
  Future<void> queueItem({
    required String id,
    required String entityType,
    required String uid,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      tableSyncQueue,
      {
        'id': id,
        'entity_type': entityType,
        'uid': uid,
        'status': 'pending',
        'retry_count': 0,
        'last_error': null,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update status of a queue item
  Future<void> updateQueueStatus({
    required String id,
    required String status,
    String? error,
    int? retryCount,
  }) async {
    final db = await database;
    final Map<String, dynamic> updates = {
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (error != null) updates['last_error'] = error;
    if (retryCount != null) updates['retry_count'] = retryCount;

    await db.update(
      tableSyncQueue,
      updates,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Remove entity from sync queue
  Future<void> removeFromQueue(String id) async {
    final db = await database;
    await db.delete(tableSyncQueue, where: 'id = ?', whereArgs: [id]);
  }

  /// Get pending queue items
  Future<List<Map<String, dynamic>>> getPendingQueueItems({String? uid}) async {
    final db = await database;
    return await db.query(
      tableSyncQueue,
      where: uid != null ? 'uid = ? AND status != ?' : 'status != ?',
      whereArgs: uid != null ? [uid, 'synced'] : ['synced'],
      orderBy: 'created_at ASC',
    );
  }

  /// Get total count of pending sync items
  Future<int> getPendingCount({String? uid}) async {
    final db = await database;
    final res = await db.rawQuery(
      uid != null
          ? "SELECT COUNT(*) as count FROM $tableSyncQueue WHERE uid = ? AND status != 'synced'"
          : "SELECT COUNT(*) as count FROM $tableSyncQueue WHERE status != 'synced'",
      uid != null ? [uid] : null,
    );
    return (res.first['count'] as num?)?.toInt() ?? 0;
  }

  // ==========================================
  // LEGACY SHAREDPREFERENCES MIGRATION
  // ==========================================

  /// Migrates any legacy JSON strings in SharedPreferences to SQLite with zero data loss
  Future<void> migrateFromSharedPreferences(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Migrate Trips
      final tripsKey = 'neurodrive_trips_$uid';
      final tripsStr = prefs.getStringList(tripsKey);
      if (tripsStr != null && tripsStr.isNotEmpty) {
        for (final item in tripsStr) {
          try {
            final map = json.decode(item) as Map<String, dynamic>;
            final trip = TripModel.fromMap(map);
            await insertTrip(trip);
          } catch (e) {
            debugPrint('Failed to migrate trip: $e');
          }
        }
      }

      // 2. Migrate Alerts
      final alertsKey = 'neurodrive_alerts_$uid';
      final alertsStr = prefs.getStringList(alertsKey);
      if (alertsStr != null && alertsStr.isNotEmpty) {
        for (final item in alertsStr) {
          try {
            final map = json.decode(item) as Map<String, dynamic>;
            final alert = AlertModel.fromMap(map);
            await insertAlert(alert, uid: uid);
          } catch (e) {
            debugPrint('Failed to migrate alert: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('SharedPreferences migration error: $e');
    }
  }

  /// Close database connection
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}
