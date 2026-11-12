import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents an emergency contact configured by the user.
class EmergencyContact {
  final String id;
  final String name;
  final String phone;
  final String relationship;
  final bool isPrimary;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.relationship = 'Family',
    this.isPrimary = false,
    this.createdAt,
    this.updatedAt,
  });

  factory EmergencyContact.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    return EmergencyContact.fromMap(data, id: snapshot.id);
  }

  factory EmergencyContact.fromMap(Map<String, dynamic> data, {String? id}) {
    DateTime? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return EmergencyContact(
      id: id ?? (data['id'] ?? '').toString(),
      name: (data['name'] ?? '').toString().trim(),
      phone: (data['phone'] ?? '').toString().trim(),
      relationship: (data['relationship'] ?? 'Family').toString().trim(),
      isPrimary: data['isPrimary'] == true,
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'name': name.trim(),
      'phone': phone.trim(),
      'relationship': relationship.trim(),
      'isPrimary': isPrimary,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  EmergencyContact copyWith({
    String? id,
    String? name,
    String? phone,
    String? relationship,
    bool? isPrimary,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      relationship: relationship ?? this.relationship,
      isPrimary: isPrimary ?? this.isPrimary,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmergencyContact &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          phone == other.phone &&
          relationship == other.relationship &&
          isPrimary == other.isPrimary;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      phone.hashCode ^
      relationship.hashCode ^
      isPrimary.hashCode;
}

/// Represents an emergency / SOS dispatch event record.
class SosEvent {
  final String id;
  final String uid;
  final String driverName;
  final DateTime timestamp;
  final double? latitude;
  final double? longitude;
  final String mapsUrl;
  final String status; // 'DELIVERED', 'CONFIG_REQUIRED', 'DELIVERY_FAILED', 'RECORDED_ONLY'
  final String deliveryProvider;
  final int contactsTargeted;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;

  const SosEvent({
    required this.id,
    required this.uid,
    required this.driverName,
    required this.timestamp,
    this.latitude,
    this.longitude,
    required this.mapsUrl,
    required this.status,
    required this.deliveryProvider,
    this.contactsTargeted = 0,
    this.errorMessage,
    this.metadata,
  });

  factory SosEvent.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final data = snapshot.data() ?? {};
    final id = snapshot.id;

    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return SosEvent(
      id: id,
      uid: (data['uid'] ?? '').toString(),
      driverName: (data['driverName'] ?? '').toString(),
      timestamp: parseTimestamp(data['timestamp']),
      latitude: data['latitude'] is num ? (data['latitude'] as num).toDouble() : null,
      longitude: data['longitude'] is num ? (data['longitude'] as num).toDouble() : null,
      mapsUrl: (data['mapsUrl'] ?? '').toString(),
      status: (data['status'] ?? 'RECORDED_ONLY').toString(),
      deliveryProvider: (data['deliveryProvider'] ?? 'none').toString(),
      contactsTargeted: (data['contactsTargeted'] as num?)?.toInt() ?? 0,
      errorMessage: data['errorMessage']?.toString(),
      metadata: data['metadata'] is Map ? Map<String, dynamic>.from(data['metadata'] as Map) : null,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return {
      'uid': uid,
      'driverName': driverName,
      'timestamp': Timestamp.fromDate(timestamp),
      'latitude': latitude,
      'longitude': longitude,
      'mapsUrl': mapsUrl,
      'status': status,
      'deliveryProvider': deliveryProvider,
      'contactsTargeted': contactsTargeted,
      'errorMessage': errorMessage,
      'metadata': metadata,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
