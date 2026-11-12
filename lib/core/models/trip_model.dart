import 'package:cloud_firestore/cloud_firestore.dart';

class TripLocation {
  final double latitude;
  final double longitude;
  final String address;

  const TripLocation({
    required this.latitude,
    required this.longitude,
    this.address = '',
  });

  factory TripLocation.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const TripLocation(latitude: 0.0, longitude: 0.0);
    return TripLocation(
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      address: (data['address'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
    };
  }
}

class TripModel {
  final String tripId;
  final String uid;
  final TripLocation startLocation;
  final TripLocation endLocation;
  final DateTime startTime;
  final DateTime endTime;
  final double distance; // in meters
  final int duration; // in seconds
  final double avgSpeed; // in km/h
  final DateTime? createdAt;
  final bool isSynced;
  final String? syncError;
  final int retryCount;
  final DateTime? lastSyncAttempt;

  const TripModel({
    required this.tripId,
    required this.uid,
    required this.startLocation,
    required this.endLocation,
    required this.startTime,
    required this.endTime,
    required this.distance,
    required this.duration,
    required this.avgSpeed,
    this.createdAt,
    this.isSynced = true,
    this.syncError,
    this.retryCount = 0,
    this.lastSyncAttempt,
  });

  /// Distance in kilometers
  double get distanceKm => distance / 1000.0;

  /// Duration formatted (e.g. "12 min", "45 sec", "1 hr 15 min")
  String get formattedDuration {
    final int hours = duration ~/ 3600;
    final int minutes = (duration % 3600) ~/ 60;
    final int seconds = duration % 60;

    if (hours > 0) {
      return '$hours hr ${minutes > 0 ? '$minutes min' : ''}'.trim();
    } else if (minutes > 0) {
      return '$minutes min';
    } else {
      return '$seconds sec';
    }
  }

  /// Construct from Firestore DocumentSnapshot
  factory TripModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return TripModel.fromMap(data, id: doc.id);
  }

  /// Construct from Map (handles both Firestore timestamps & ISO strings from local prefs)
  factory TripModel.fromMap(Map<String, dynamic> data, {String? id}) {
    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) {
        return DateTime.tryParse(val) ?? fallback;
      }
      return fallback;
    }

    final now = DateTime.now();
    final start = parseDate(data['startTime'], now);
    final end = parseDate(data['endTime'], now);

    // Support startLocation as a map or individual lat/lng keys
    TripLocation parseStartLoc() {
      if (data['startLocation'] is Map) {
        return TripLocation.fromMap(Map<String, dynamic>.from(data['startLocation'] as Map));
      }
      final lat = (data['startLat'] as num?)?.toDouble() ?? 0.0;
      final lng = (data['startLng'] as num?)?.toDouble() ?? 0.0;
      return TripLocation(latitude: lat, longitude: lng);
    }

    TripLocation parseEndLoc() {
      if (data['endLocation'] is Map) {
        return TripLocation.fromMap(Map<String, dynamic>.from(data['endLocation'] as Map));
      }
      final lat = (data['endLat'] as num?)?.toDouble() ?? 0.0;
      final lng = (data['endLng'] as num?)?.toDouble() ?? 0.0;
      return TripLocation(latitude: lat, longitude: lng);
    }

    // Distance in meters (supports both 'distance' and legacy 'distanceMeters')
    final dist = (data['distance'] as num?)?.toDouble() ??
        (data['distanceMeters'] as num?)?.toDouble() ??
        0.0;

    // Duration in seconds (supports both 'duration' and legacy 'durationSeconds')
    final dur = (data['duration'] as num?)?.toInt() ??
        (data['durationSeconds'] as num?)?.toInt() ??
        0;

    // AvgSpeed (supports calculated or provided)
    double speed = (data['avgSpeed'] as num?)?.toDouble() ?? 0.0;
    if (speed <= 0.0 && dur > 0 && dist > 0) {
      speed = (dist / dur) * 3.6; // m/s to km/h
    }

    return TripModel(
      tripId: id ?? (data['tripId'] ?? data['id'] ?? '').toString(),
      uid: (data['uid'] ?? '').toString(),
      startLocation: parseStartLoc(),
      endLocation: parseEndLoc(),
      startTime: start,
      endTime: end,
      distance: dist,
      duration: dur,
      avgSpeed: speed,
      createdAt: data['createdAt'] != null ? parseDate(data['createdAt'], now) : null,
      isSynced: (data['isSynced'] as bool?) ?? true,
      syncError: data['syncError']?.toString(),
      retryCount: (data['retryCount'] as num?)?.toInt() ?? 0,
      lastSyncAttempt: data['lastSyncAttempt'] != null ? parseDate(data['lastSyncAttempt'], now) : null,
    );
  }

  /// To Firestore Map representation
  Map<String, dynamic> toFirestoreMap({bool useServerTimestamp = true}) {
    return {
      'tripId': tripId,
      'uid': uid,
      'startLocation': startLocation.toMap(),
      'endLocation': endLocation.toMap(),
      // Also provide flat lat/lng for backwards compatibility
      'startLat': startLocation.latitude,
      'startLng': startLocation.longitude,
      'endLat': endLocation.latitude,
      'endLng': endLocation.longitude,
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'distance': distance,
      'distanceMeters': distance, // backwards compatibility
      'duration': duration,
      'durationSeconds': duration, // backwards compatibility
      'avgSpeed': avgSpeed,
      'createdAt': useServerTimestamp ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt ?? DateTime.now()),
    };
  }

  /// To Local Json Map representation
  Map<String, dynamic> toJsonMap() {
    return {
      'tripId': tripId,
      'id': tripId, // backwards compatibility
      'uid': uid,
      'startLocation': startLocation.toMap(),
      'endLocation': endLocation.toMap(),
      'startLat': startLocation.latitude,
      'startLng': startLocation.longitude,
      'endLat': endLocation.latitude,
      'endLng': endLocation.longitude,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'distance': distance,
      'distanceMeters': distance,
      'duration': duration,
      'durationSeconds': duration,
      'avgSpeed': avgSpeed,
      'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
      'isSynced': isSynced,
      'syncError': syncError,
      'retryCount': retryCount,
      'lastSyncAttempt': lastSyncAttempt?.toIso8601String(),
    };
  }

  /// To SQLite Row Map
  Map<String, dynamic> toSqlMap() {
    return {
      'trip_id': tripId,
      'uid': uid,
      'start_lat': startLocation.latitude,
      'start_lng': startLocation.longitude,
      'start_address': startLocation.address,
      'end_lat': endLocation.latitude,
      'end_lng': endLocation.longitude,
      'end_address': endLocation.address,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'distance': distance,
      'duration': duration,
      'avg_speed': avgSpeed,
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
      'sync_error': syncError,
      'retry_count': retryCount,
      'last_sync_attempt': lastSyncAttempt?.toIso8601String(),
    };
  }

  /// From SQLite Row Map
  factory TripModel.fromSqlMap(Map<String, dynamic> map) {
    return TripModel(
      tripId: map['trip_id'] as String,
      uid: (map['uid'] ?? '').toString(),
      startLocation: TripLocation(
        latitude: (map['start_lat'] as num?)?.toDouble() ?? 0.0,
        longitude: (map['start_lng'] as num?)?.toDouble() ?? 0.0,
        address: (map['start_address'] as String?) ?? '',
      ),
      endLocation: TripLocation(
        latitude: (map['end_lat'] as num?)?.toDouble() ?? 0.0,
        longitude: (map['end_lng'] as num?)?.toDouble() ?? 0.0,
        address: (map['end_address'] as String?) ?? '',
      ),
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: DateTime.parse(map['end_time'] as String),
      distance: (map['distance'] as num?)?.toDouble() ?? 0.0,
      duration: (map['duration'] as num?)?.toInt() ?? 0,
      avgSpeed: (map['avg_speed'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      isSynced: (map['is_synced'] as int? ?? 1) == 1,
      syncError: map['sync_error'] as String?,
      retryCount: (map['retry_count'] as int?) ?? 0,
      lastSyncAttempt: map['last_sync_attempt'] != null ? DateTime.tryParse(map['last_sync_attempt'] as String) : null,
    );
  }

  TripModel copyWith({
    String? tripId,
    String? uid,
    TripLocation? startLocation,
    TripLocation? endLocation,
    DateTime? startTime,
    DateTime? endTime,
    double? distance,
    int? duration,
    double? avgSpeed,
    DateTime? createdAt,
    bool? isSynced,
    String? syncError,
    int? retryCount,
    DateTime? lastSyncAttempt,
  }) {
    return TripModel(
      tripId: tripId ?? this.tripId,
      uid: uid ?? this.uid,
      startLocation: startLocation ?? this.startLocation,
      endLocation: endLocation ?? this.endLocation,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      distance: distance ?? this.distance,
      duration: duration ?? this.duration,
      avgSpeed: avgSpeed ?? this.avgSpeed,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      syncError: syncError ?? this.syncError,
      retryCount: retryCount ?? this.retryCount,
      lastSyncAttempt: lastSyncAttempt ?? this.lastSyncAttempt,
    );
  }
}
