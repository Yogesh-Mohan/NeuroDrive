class DetectedVehicle {
  final String id;
  final double latitude;
  final double longitude;
  final double speedKmh;
  final double heading;
  final DateTime timestamp;
  final String source; // e.g., 'ESP32', 'V2V'

  DetectedVehicle({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.heading,
    required this.timestamp,
    required this.source,
  });
}
