import 'package:cloud_firestore/cloud_firestore.dart';

class AlertModel {
  final String id;
  final String? tripId;
  final String alertType;
  final String severity; // 'caution', 'warning', 'critical'
  final String message;
  final String source;
  final double? distance; // in meters
  final double? relativeSpeed; // in km/h
  final double? ttc; // in seconds
  final double? latitude;
  final double? longitude;
  final DateTime timestamp;
  final DateTime? createdAt;
  final bool isSynced;
  final String? syncError;
  final int retryCount;
  final DateTime? lastSyncAttempt;

  const AlertModel({
    required this.id,
    this.tripId,
    required this.alertType,
    required this.severity,
    required this.message,
    this.source = 'SafetyEngine',
    this.distance,
    this.relativeSpeed,
    this.ttc,
    this.latitude,
    this.longitude,
    required this.timestamp,
    this.createdAt,
    this.isSynced = true,
    this.syncError,
    this.retryCount = 0,
    this.lastSyncAttempt,
  });

  /// Legacy getter for riskLevel compatibility
  String get riskLevel => severity;

  /// Construct from Firestore DocumentSnapshot
  factory AlertModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AlertModel.fromMap(data, id: doc.id);
  }

  /// Construct from Map (handles Firestore timestamps & ISO strings from local prefs)
  factory AlertModel.fromMap(Map<String, dynamic> data, {String? id}) {
    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) {
        return DateTime.tryParse(val) ?? fallback;
      }
      return fallback;
    }

    final now = DateTime.now();
    final ts = parseDate(data['timestamp'], now);

    // Normalize severity string from 'RiskLevel.warning' or raw 'warning'
    String rawSev = (data['severity'] ?? data['riskLevel'] ?? 'warning').toString();
    if (rawSev.contains('.')) {
      rawSev = rawSev.split('.').last;
    }
    rawSev = rawSev.toLowerCase();

    return AlertModel(
      id: id ?? (data['id'] ?? data['alertId'] ?? '').toString(),
      tripId: data['tripId']?.toString(),
      alertType: (data['alertType'] ?? (rawSev == 'critical' ? 'COLLISION_ALERT' : 'COLLISION_WARNING')).toString(),
      severity: rawSev,
      message: (data['message'] ?? 'Safety alert triggered').toString(),
      source: (data['source'] ?? 'SafetyEngine').toString(),
      distance: (data['distance'] as num?)?.toDouble(),
      relativeSpeed: (data['relativeSpeed'] as num?)?.toDouble(),
      ttc: (data['TTC'] as num?)?.toDouble() ?? (data['ttc'] as num?)?.toDouble(),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      timestamp: ts,
      createdAt: data['createdAt'] != null ? parseDate(data['createdAt'], now) : null,
      isSynced: (data['isSynced'] as bool?) ?? true,
      syncError: data['syncError']?.toString(),
      retryCount: (data['retryCount'] as num?)?.toInt() ?? 0,
      lastSyncAttempt: data['lastSyncAttempt'] != null ? parseDate(data['lastSyncAttempt'], now) : null,
    );
  }

  /// Backwards-compatible factory from JSON
  factory AlertModel.fromJson(Map<String, dynamic> json) => AlertModel.fromMap(json);

  /// Convert to Firestore Map representation
  Map<String, dynamic> toFirestoreMap({bool useServerTimestamp = true}) {
    final Map<String, dynamic> map = {
      'alertId': id,
      'alertType': alertType,
      'severity': severity,
      'message': message,
      'source': source,
      'timestamp': Timestamp.fromDate(timestamp),
      'createdAt': useServerTimestamp ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt ?? DateTime.now()),
    };

    if (tripId != null && tripId!.isNotEmpty) {
      map['tripId'] = tripId;
    }
    if (distance != null) {
      map['distance'] = distance;
    }
    if (relativeSpeed != null) {
      map['relativeSpeed'] = relativeSpeed;
    }
    if (ttc != null) {
      map['TTC'] = ttc;
      map['ttc'] = ttc;
    }
    if (latitude != null) {
      map['latitude'] = latitude;
    }
    if (longitude != null) {
      map['longitude'] = longitude;
    }

    return map;
  }

  /// Convert to Local JSON Map
  Map<String, dynamic> toJsonMap() {
    final Map<String, dynamic> map = {
      'id': id,
      'alertId': id,
      'tripId': tripId,
      'alertType': alertType,
      'severity': severity,
      'riskLevel': severity, // backwards compatibility
      'message': message,
      'source': source,
      'distance': distance,
      'relativeSpeed': relativeSpeed,
      'TTC': ttc,
      'ttc': ttc,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
      'isSynced': isSynced,
      'syncError': syncError,
      'retryCount': retryCount,
      'lastSyncAttempt': lastSyncAttempt?.toIso8601String(),
    };
    return map;
  }

  /// Convert to SQLite Row Map
  Map<String, dynamic> toSqlMap({String? uid}) {
    return {
      'id': id,
      'uid': uid ?? '',
      'trip_id': tripId,
      'alert_type': alertType,
      'severity': severity,
      'message': message,
      'source': source,
      'distance': distance,
      'relative_speed': relativeSpeed,
      'ttc': ttc,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
      'sync_error': syncError,
      'retry_count': retryCount,
      'last_sync_attempt': lastSyncAttempt?.toIso8601String(),
    };
  }

  /// Construct from SQLite Row Map
  factory AlertModel.fromSqlMap(Map<String, dynamic> map) {
    return AlertModel(
      id: map['id'] as String,
      tripId: map['trip_id'] as String?,
      alertType: (map['alert_type'] ?? 'SAFETY_ALERT').toString(),
      severity: (map['severity'] ?? 'warning').toString(),
      message: (map['message'] ?? '').toString(),
      source: (map['source'] ?? 'SafetyEngine').toString(),
      distance: (map['distance'] as num?)?.toDouble(),
      relativeSpeed: (map['relative_speed'] as num?)?.toDouble(),
      ttc: (map['ttc'] as num?)?.toDouble(),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      timestamp: DateTime.parse(map['timestamp'] as String),
      createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'] as String) : null,
      isSynced: (map['is_synced'] as int? ?? 1) == 1,
      syncError: map['sync_error'] as String?,
      retryCount: (map['retry_count'] as int?) ?? 0,
      lastSyncAttempt: map['last_sync_attempt'] != null ? DateTime.tryParse(map['last_sync_attempt'] as String) : null,
    );
  }

  /// Backwards compatible toJson()
  Map<String, dynamic> toJson() => toJsonMap();

  AlertModel copyWith({
    String? id,
    String? tripId,
    String? alertType,
    String? severity,
    String? message,
    String? source,
    double? distance,
    double? relativeSpeed,
    double? ttc,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    DateTime? createdAt,
    bool? isSynced,
    String? syncError,
    int? retryCount,
    DateTime? lastSyncAttempt,
  }) {
    return AlertModel(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      alertType: alertType ?? this.alertType,
      severity: severity ?? this.severity,
      message: message ?? this.message,
      source: source ?? this.source,
      distance: distance ?? this.distance,
      relativeSpeed: relativeSpeed ?? this.relativeSpeed,
      ttc: ttc ?? this.ttc,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      createdAt: createdAt ?? this.createdAt,
      isSynced: isSynced ?? this.isSynced,
      syncError: syncError ?? this.syncError,
      retryCount: retryCount ?? this.retryCount,
      lastSyncAttempt: lastSyncAttempt ?? this.lastSyncAttempt,
    );
  }
}
