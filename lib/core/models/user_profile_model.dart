import 'package:cloud_firestore/cloud_firestore.dart';

class VehicleModel {
  final String name;
  final String registrationNumber;
  final String type;
  final String model;

  const VehicleModel({
    this.name = '',
    this.registrationNumber = '',
    this.type = '',
    this.model = '',
  });

  bool get isEmpty =>
      name.trim().isEmpty &&
      registrationNumber.trim().isEmpty &&
      type.trim().isEmpty &&
      model.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  factory VehicleModel.fromMap(Map<String, dynamic>? data) {
    if (data == null) return const VehicleModel();
    return VehicleModel(
      name: (data['name'] ?? '').toString().trim(),
      // supports both 'registrationNumber' and 'number' for backwards compatibility
      registrationNumber: (data['registrationNumber'] ?? data['number'] ?? '').toString().trim(),
      type: (data['type'] ?? '').toString().trim(),
      model: (data['model'] ?? '').toString().trim(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name.trim(),
      'registrationNumber': registrationNumber.trim(),
      'number': registrationNumber.trim(), // Keep both keys for seamless compatibility
      'type': type.trim(),
      'model': model.trim(),
    };
  }

  VehicleModel copyWith({
    String? name,
    String? registrationNumber,
    String? type,
    String? model,
  }) {
    return VehicleModel(
      name: name ?? this.name,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      type: type ?? this.type,
      model: model ?? this.model,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VehicleModel &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          registrationNumber == other.registrationNumber &&
          type == other.type &&
          model == other.model;

  @override
  int get hashCode =>
      name.hashCode ^
      registrationNumber.hashCode ^
      type.hashCode ^
      model.hashCode;
}

class UserProfile {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final VehicleModel vehicle;

  const UserProfile({
    required this.uid,
    this.name = '',
    this.email = '',
    this.phone = '',
    this.createdAt,
    this.updatedAt,
    this.vehicle = const VehicleModel(),
  });

  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot, {
    String? fallbackEmail,
    String? fallbackName,
  }) {
    final data = snapshot.data() ?? {};
    final uid = snapshot.id;

    DateTime? parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    final vehicleData = data['vehicle'] is Map<String, dynamic>
        ? data['vehicle'] as Map<String, dynamic>
        : (data['vehicle'] is Map ? Map<String, dynamic>.from(data['vehicle'] as Map) : null);

    return UserProfile(
      uid: uid,
      name: (data['name'] ?? fallbackName ?? '').toString().trim(),
      email: (data['email'] ?? fallbackEmail ?? '').toString().trim(),
      phone: (data['phone'] ?? '').toString().trim(),
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
      vehicle: VehicleModel.fromMap(vehicleData),
    );
  }

  UserProfile copyWith({
    String? uid,
    String? name,
    String? email,
    String? phone,
    DateTime? createdAt,
    DateTime? updatedAt,
    VehicleModel? vehicle,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      vehicle: vehicle ?? this.vehicle,
    );
  }
}
