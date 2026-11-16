class V2VTelemetry {
  final String vehicleId;
  final double distanceCm;
  final double distanceMeters;
  final double? remoteDistanceCm;
  final double speedKmh;
  final double closingSpeedKmh;
  final String status; // 'SAFE', 'CAUTION', 'CRITICAL'
  final bool isOnline;
  final DateTime timestamp;
  final double angleDeg; // Forward angle (default 90° for straight ahead)

  const V2VTelemetry({
    required this.vehicleId,
    required this.distanceCm,
    required this.distanceMeters,
    this.remoteDistanceCm,
    this.speedKmh = 0.0,
    this.closingSpeedKmh = 0.0,
    this.status = 'SAFE',
    this.isOnline = true,
    required this.timestamp,
    this.angleDeg = 90.0,
  });

  factory V2VTelemetry.fromMap(Map<dynamic, dynamic> map) {
    // 1. Prioritize 'local', 'distance_cm', 'distance', 'dist', etc.
    dynamic rawDist = map['local'] ??
        map['distance_cm'] ??
        map['distance'] ??
        map['dist'] ??
        map['d'] ??
        map['cm'] ??
        map['val'] ??
        map['value'] ??
        map['remote'];

    // Fallback: If no recognized key, find the first numeric value in the map!
    if (rawDist == null) {
      for (final entry in map.entries) {
        if (entry.value is num) {
          rawDist = entry.value;
          break;
        } else if (entry.value is String) {
          final p = double.tryParse(entry.value.toString());
          if (p != null) {
            rawDist = p;
            break;
          }
        }
      }
    }

    final distCm = (rawDist is num)
        ? rawDist.toDouble()
        : (double.tryParse(rawDist?.toString() ?? '0.0') ?? 0.0);

    // 2. Extract Remote V2V distance if present (e.g. {"local": 4.5, "remote": 14.1})
    dynamic rawRemote = map['remote'] ?? map['remote_dist'] ?? map['v2'] ?? map['vehicle2'];
    double? remoteDist;
    if (rawRemote != null) {
      remoteDist = (rawRemote is num)
          ? rawRemote.toDouble()
          : double.tryParse(rawRemote.toString());
    }

    final rawSpeed = map['speed_kmh'] ?? map['speed'] ?? 0.0;
    final speed = (rawSpeed is num) ? rawSpeed.toDouble() : (double.tryParse(rawSpeed.toString()) ?? 0.0);
    final rawClosing = map['closing_speed_kmh'] ?? 0.0;
    final closing = (rawClosing is num) ? rawClosing.toDouble() : (double.tryParse(rawClosing.toString()) ?? 0.0);
    
    String computedStatus = 'SAFE';
    if (distCm > 0 && distCm < 8.0) {
      computedStatus = 'CRITICAL';
    } else if (distCm >= 8.0 && distCm < 15.0) {
      computedStatus = 'CAUTION';
    }
    
    final statusStr = map['status']?.toString() ?? computedStatus;

    return V2VTelemetry(
      vehicleId: map['vehicle_id']?.toString() ?? 'ESP32_LEAD',
      distanceCm: distCm,
      distanceMeters: distCm / 100.0,
      remoteDistanceCm: remoteDist,
      speedKmh: speed,
      closingSpeedKmh: closing,
      status: statusStr,
      isOnline: map['is_online'] is bool ? map['is_online'] as bool : true,
      timestamp: DateTime.now(),
      angleDeg: (map['angle_deg'] is num) ? (map['angle_deg'] as num).toDouble() : 90.0,
    );
  }

  factory V2VTelemetry.initial() {
    return V2VTelemetry(
      vehicleId: 'CAR_01',
      distanceCm: 0.0,
      distanceMeters: 0.0,
      speedKmh: 0.0,
      closingSpeedKmh: 0.0,
      status: 'SEARCHING',
      isOnline: false,
      timestamp: DateTime.now(),
      angleDeg: 90.0,
    );
  }
}
