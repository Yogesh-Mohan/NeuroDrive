import 'package:cloud_firestore/cloud_firestore.dart';

class RoadDamageModel {
  final String damageId;
  final double latitude;
  final double longitude;
  final String damageType;
  final String severity; // 'high', 'medium', 'low'
  final String status; // 'active', 'repaired'
  final String district;
  final String source;
  final String region;
  final String? filename;
  final String verificationStatus;
  final DateTime? reportedAt;
  final Map<String, dynamic> metadata;

  // Calculated at runtime during navigation
  final double? distanceToVehicleMeters;
  final double? distanceToRouteCorridorMeters;

  bool get isActive => status.toLowerCase() == 'active';

  const RoadDamageModel({
    required this.damageId,
    required this.latitude,
    required this.longitude,
    this.damageType = 'pothole',
    this.severity = 'medium',
    this.status = 'active',
    this.district = 'Tamil Nadu',
    this.source = 'Global_Potholes_Dataset',
    this.region = 'India',
    this.filename,
    this.verificationStatus = 'verified',
    this.reportedAt,
    this.metadata = const {},
    this.distanceToVehicleMeters,
    this.distanceToRouteCorridorMeters,
  });

  RoadDamageModel copyWith({
    double? distanceToVehicleMeters,
    double? distanceToRouteCorridorMeters,
  }) {
    return RoadDamageModel(
      damageId: damageId,
      latitude: latitude,
      longitude: longitude,
      damageType: damageType,
      severity: severity,
      status: status,
      district: district,
      source: source,
      region: region,
      filename: filename,
      verificationStatus: verificationStatus,
      reportedAt: reportedAt,
      metadata: metadata,
      distanceToVehicleMeters: distanceToVehicleMeters ?? this.distanceToVehicleMeters,
      distanceToRouteCorridorMeters: distanceToRouteCorridorMeters ?? this.distanceToRouteCorridorMeters,
    );
  }

  factory RoadDamageModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return RoadDamageModel.fromMap(data, id: doc.id);
  }

  factory RoadDamageModel.fromMap(Map<String, dynamic> map, {String? id}) {
    DateTime? parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return RoadDamageModel(
      damageId: id ?? (map['damage_id'] ?? map['id'] ?? '').toString(),
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      damageType: (map['damage_type'] ?? 'pothole').toString(),
      severity: (map['severity'] ?? 'medium').toString().toLowerCase(),
      status: (map['status'] ?? 'active').toString().toLowerCase(),
      district: (map['district'] ?? 'Tamil Nadu').toString(),
      source: (map['source'] ?? 'Global_Potholes_Dataset').toString(),
      region: (map['region'] ?? 'India').toString(),
      filename: map['filename']?.toString(),
      verificationStatus: (map['verification_status'] ?? 'verified').toString(),
      reportedAt: parseDate(map['reported_at'] ?? map['created_at']),
      metadata: map['metadata'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(map['metadata'] as Map)
          : {},
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'damage_id': damageId,
      'latitude': latitude,
      'longitude': longitude,
      'damage_type': damageType,
      'severity': severity,
      'status': status,
      'district': district,
      'source': source,
      'region': region,
      'filename': filename,
      'verification_status': verificationStatus,
      'reported_at': reportedAt?.toIso8601String(),
      'metadata': metadata,
    };
  }
}
