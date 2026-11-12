class DetectedVehicle {
  final String id;
  final double latitude;
  final double longitude;
  final double speedKmh;
  final double heading;
  final DateTime timestamp;
  final String source; // e.g., 'ESP32', 'V2V', 'Radar'

  /// Direct physical sensor distance in meters (e.g. from ESP32 ultrasonic/LiDAR/mmWave radar).
  /// When provided, this takes precedence over GPS coordinate haversine approximation.
  final double? directDistanceMeters;

  /// Direct measured relative closing speed in km/h or m/s (from radar / doppler sensor).
  /// If null, relative closing speed can be derived from ego speed and target speed.
  final double? directClosingSpeedKmh;

  /// Reliability flag: set to false if sensor reading is noisy, corrupted, out-of-range, or stale.
  final bool isReliable;

  DetectedVehicle({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.heading,
    required this.timestamp,
    required this.source,
    this.directDistanceMeters,
    this.directClosingSpeedKmh,
    this.isReliable = true,
  });

  /// Factory constructor for ESP32 hardware telemetry
  factory DetectedVehicle.fromEsp32({
    required String id,
    required double distanceMeters,
    double? closingSpeedKmh,
    double egoSpeedKmh = 0.0,
    DateTime? timestamp,
    bool isReliable = true,
    double latitude = 0.0,
    double longitude = 0.0,
    double heading = 0.0,
  }) {
    return DetectedVehicle(
      id: id,
      latitude: latitude,
      longitude: longitude,
      speedKmh: egoSpeedKmh,
      heading: heading,
      timestamp: timestamp ?? DateTime.now(),
      source: 'ESP32',
      directDistanceMeters: distanceMeters,
      directClosingSpeedKmh: closingSpeedKmh,
      isReliable: isReliable,
    );
  }
}
