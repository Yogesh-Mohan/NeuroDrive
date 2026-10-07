import 'package:geolocator/geolocator.dart';
import '../models/detected_vehicle.dart';

enum RiskLevel { safe, caution, warning, critical, unavailable }

class SafetyStatus {
  final RiskLevel riskLevel;
  final String message;
  final double? ttcSeconds;
  final bool isGpsReliable;

  SafetyStatus({
    required this.riskLevel,
    required this.message,
    this.ttcSeconds,
    this.isGpsReliable = true,
  });
}

class SafetyEngine {
  // Configurable Thresholds
  static const double minGpsAccuracyMeters = 20.0; // Ignore GPS worse than this
  static const double ttcWarningThreshold = 5.0; // Seconds
  static const double ttcCriticalThreshold = 2.5; // Seconds

  /// Main method called every time the Ego vehicle gets a new GPS position.
  SafetyStatus evaluateRisk({
    required Position currentEgoPosition,
    List<DetectedVehicle> detectedObjects = const [],
  }) {
    // 1. Check GPS Quality
    if (currentEgoPosition.accuracy > minGpsAccuracyMeters) {
      return SafetyStatus(
        riskLevel: RiskLevel.unavailable,
        message: 'GPS accuracy insufficient',
        isGpsReliable: false,
      );
    }

    double egoSpeedKmh = currentEgoPosition.speed * 3.6;
    if (egoSpeedKmh < 1.0) egoSpeedKmh = 0.0; // Filter noise

    // 2. Hardware / Target detection check
    if (detectedObjects.isEmpty) {
      // If we are moving but have no hardware to detect others, we cannot calculate TTC.
      if (egoSpeedKmh > 0) {
        return SafetyStatus(
          riskLevel: RiskLevel.safe,
          message: 'Vehicle detection unavailable – hardware integration required.',
          ttcSeconds: null,
        );
      } else {
        return SafetyStatus(
          riskLevel: RiskLevel.safe,
          message: 'Road condition safe (Stationary)',
          ttcSeconds: null,
        );
      }
    }

    // 3. TTC Engine (Only runs if future hardware detected an object)
    // For MVP one-dimensional model, let's find the most dangerous object
    double? lowestTtc;
    
    for (var target in detectedObjects) {
      // Calculate distance between ego and target
      double distanceToTarget = Geolocator.distanceBetween(
        currentEgoPosition.latitude,
        currentEgoPosition.longitude,
        target.latitude,
        target.longitude,
      );

      // Simple relative closing speed (Assuming head-on or following in 1D for MVP)
      // Closing speed = Ego Speed - Target Speed
      // (If positive, we are catching up. If negative, they are pulling away)
      double closingSpeedKmh = egoSpeedKmh - target.speedKmh;
      double closingSpeedMs = closingSpeedKmh / 3.6;

      if (closingSpeedMs > 0 && distanceToTarget > 0) {
        double ttc = distanceToTarget / closingSpeedMs;
        if (lowestTtc == null || ttc < lowestTtc) {
          lowestTtc = ttc;
        }
      }
    }

    // 4. Risk Classification
    if (lowestTtc == null) {
      return SafetyStatus(
        riskLevel: RiskLevel.safe,
        message: 'Road condition safe',
      );
    }

    if (lowestTtc <= ttcCriticalThreshold) {
      return SafetyStatus(
        riskLevel: RiskLevel.critical,
        message: 'IMMEDIATE ATTENTION REQUIRED',
        ttcSeconds: lowestTtc,
      );
    } else if (lowestTtc <= ttcWarningThreshold) {
      return SafetyStatus(
        riskLevel: RiskLevel.warning,
        message: 'Collision risk detected',
        ttcSeconds: lowestTtc,
      );
    } else if (lowestTtc <= ttcWarningThreshold * 2) {
      return SafetyStatus(
        riskLevel: RiskLevel.caution,
        message: 'Maintain safe distance',
        ttcSeconds: lowestTtc,
      );
    }

    return SafetyStatus(
      riskLevel: RiskLevel.safe,
      message: 'Road condition safe',
      ttcSeconds: lowestTtc,
    );
  }

  void reset() {}
}
