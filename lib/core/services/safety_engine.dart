import 'package:geolocator/geolocator.dart';
import '../models/detected_vehicle.dart';

enum RiskLevel { safe, caution, warning, critical, unavailable }

class SafetyStatus {
  final RiskLevel riskLevel;
  final String message;
  final double? ttcSeconds;
  final bool isGpsReliable;
  final double? distanceMeters;
  final double? closingSpeedKmh;
  final String? threatId;
  final String? reason;

  SafetyStatus({
    required this.riskLevel,
    required this.message,
    this.ttcSeconds,
    this.isGpsReliable = true,
    this.distanceMeters,
    this.closingSpeedKmh,
    this.threatId,
    this.reason,
  });

  bool get hasActiveThreat =>
      riskLevel == RiskLevel.caution ||
      riskLevel == RiskLevel.warning ||
      riskLevel == RiskLevel.critical;
}

/// Represents the evaluated Time-to-Collision result for a single target object.
class TtcCalculationResult {
  final bool isValid;
  final double? ttcSeconds;
  final double distanceMeters;
  final double closingSpeedMs;
  final double closingSpeedKmh;
  final String calculationReason;

  const TtcCalculationResult({
    required this.isValid,
    this.ttcSeconds,
    required this.distanceMeters,
    required this.closingSpeedMs,
    required this.closingSpeedKmh,
    required this.calculationReason,
  });

  factory TtcCalculationResult.invalid(String reason) {
    return TtcCalculationResult(
      isValid: false,
      ttcSeconds: null,
      distanceMeters: 0.0,
      closingSpeedMs: 0.0,
      closingSpeedKmh: 0.0,
      calculationReason: reason,
    );
  }
}

class SafetyEngine {
  // Configurable Safety Thresholds
  static const double minGpsAccuracyMeters = 20.0; // Ignore GPS worse than this
  static const double ttcWarningThreshold = 5.0; // Seconds (Threshold for warning)
  static const double ttcCriticalThreshold = 2.5; // Seconds (Threshold for critical)
  static const double ttcCautionThreshold = 10.0; // Seconds (Threshold for caution: 2 * warning)

  // Physical validation bounds
  static const double maxReliableSensorDistanceMeters = 250.0;
  static const double minReliableSensorDistanceMeters = 0.2; // 20cm minimum
  static const double maxReliableClosingSpeedKmh = 250.0; // Realistic closing speed max
  static const Duration sensorStaleThreshold = Duration(seconds: 4);

  // In-memory state tracking to prevent duplicate alerts and manage threat resets
  String? _lastActiveThreatId;
  RiskLevel _lastActiveRiskLevel = RiskLevel.safe;
  DateTime? _lastAlertTriggerTime;
  static const Duration duplicateAlertSuppressionWindow = Duration(seconds: 5);

  RiskLevel get lastActiveRiskLevel => _lastActiveRiskLevel;
  String? get lastActiveThreatId => _lastActiveThreatId;

  /// Pure mathematical Time-to-Collision validation and calculation.
  ///
  /// Formula: TTC = Distance (m) / Closing Speed (m/s)
  /// Validated strictly when:
  /// - Distance is positive and within physical sensor limits
  /// - Closing speed is strictly positive (approaching, not departing or stationary)
  /// - Reading is not stale, NaN, infinite, or corrupted
  static TtcCalculationResult calculateTtc({
    required double distanceMeters,
    required double closingSpeedKmh,
    DateTime? measurementTimestamp,
    bool isSensorReliable = true,
  }) {
    // 1. Reliability validation
    if (!isSensorReliable) {
      return TtcCalculationResult.invalid('Sensor reading flagged as unreliable');
    }

    // 2. Staleness check
    if (measurementTimestamp != null) {
      final age = DateTime.now().difference(measurementTimestamp);
      if (age > sensorStaleThreshold) {
        return TtcCalculationResult.invalid('Sensor data is stale (${age.inSeconds}s old)');
      }
    }

    // 3. Numeric bounds validation for distance
    if (distanceMeters.isNaN || distanceMeters.isInfinite) {
      return TtcCalculationResult.invalid('Invalid non-numeric distance');
    }
    if (distanceMeters <= 0.0) {
      return TtcCalculationResult.invalid('Distance must be strictly positive');
    }
    if (distanceMeters < minReliableSensorDistanceMeters) {
      return TtcCalculationResult.invalid('Distance below minimum reliable hardware threshold');
    }
    if (distanceMeters > maxReliableSensorDistanceMeters) {
      return TtcCalculationResult.invalid('Distance exceeds maximum reliable sensor range');
    }

    // 4. Numeric bounds validation for closing speed
    if (closingSpeedKmh.isNaN || closingSpeedKmh.isInfinite) {
      return TtcCalculationResult.invalid('Invalid non-numeric closing speed');
    }

    // Convert km/h to m/s: 1 km/h = 1000m / 3600s = 1 / 3.6 m/s
    final double closingSpeedMs = closingSpeedKmh / 3.6;

    // A vehicle pulling away or keeping pace has closingSpeed <= 0.
    // TTC is only valid when objects are converging (closing speed > 0).
    if (closingSpeedMs <= 0.001) {
      return TtcCalculationResult(
        isValid: false,
        ttcSeconds: null,
        distanceMeters: distanceMeters,
        closingSpeedMs: closingSpeedMs,
        closingSpeedKmh: closingSpeedKmh,
        calculationReason: closingSpeedMs < 0
            ? 'Target vehicle is moving away (negative closing speed)'
            : 'Zero relative closing speed (distance constant)',
      );
    }

    if (closingSpeedKmh > maxReliableClosingSpeedKmh) {
      return TtcCalculationResult.invalid('Closing speed exceeds realistic physical envelope');
    }

    // 5. Accurate TTC Calculation: Distance / Closing Speed
    final double ttc = distanceMeters / closingSpeedMs;

    return TtcCalculationResult(
      isValid: true,
      ttcSeconds: ttc,
      distanceMeters: distanceMeters,
      closingSpeedMs: closingSpeedMs,
      closingSpeedKmh: closingSpeedKmh,
      calculationReason: 'Calculated using valid sensor distance and closing speed',
    );
  }

  /// Main method called every time the Ego vehicle gets a new GPS position or sensor update.
  SafetyStatus evaluateRisk({
    required Position currentEgoPosition,
    List<DetectedVehicle> detectedObjects = const [],
    DateTime? currentTime,
  }) {
    // 1. Check GPS Quality
    if (currentEgoPosition.accuracy > minGpsAccuracyMeters) {
      return SafetyStatus(
        riskLevel: RiskLevel.unavailable,
        message: 'GPS accuracy insufficient',
        isGpsReliable: false,
        reason: 'GPS accuracy (${currentEgoPosition.accuracy.toStringAsFixed(1)}m) is worse than threshold (${minGpsAccuracyMeters}m)',
      );
    }

    double egoSpeedKmh = currentEgoPosition.speed * 3.6;
    if (egoSpeedKmh < 1.0) egoSpeedKmh = 0.0; // Filter stationary noise

    // 2. Hardware / Target detection check
    // Note: GPS speed alone cannot determine inter-vehicle distance or closing speed without sensors!
    if (detectedObjects.isEmpty) {
      _resetThreatStateIfCleared();
      if (egoSpeedKmh > 0) {
        return SafetyStatus(
          riskLevel: RiskLevel.safe,
          message: 'Vehicle detection unavailable – hardware integration required.',
          ttcSeconds: null,
          reason: 'No external sensor data received; GPS speed alone cannot infer forward hazards.',
        );
      } else {
        return SafetyStatus(
          riskLevel: RiskLevel.safe,
          message: 'Road condition safe (Stationary)',
          ttcSeconds: null,
          reason: 'Vehicle stationary with no detected targets.',
        );
      }
    }

    // 3. Evaluate detected objects using robust TTC calculations
    double? lowestTtc;
    DetectedVehicle? mostCriticalTarget;
    TtcCalculationResult? bestTtcResult;

    for (final target in detectedObjects) {
      // Determine distance: prioritize direct hardware sensor reading (e.g. ESP32 ultrasonic/radar)
      double distanceToTarget;
      if (target.directDistanceMeters != null) {
        distanceToTarget = target.directDistanceMeters!;
      } else {
        // Fallback to Haversine GPS coordinate distance
        distanceToTarget = Geolocator.distanceBetween(
          currentEgoPosition.latitude,
          currentEgoPosition.longitude,
          target.latitude,
          target.longitude,
        );
      }

      // Determine closing speed: prioritize direct doppler/radar sensor reading
      double closingSpeedKmh;
      if (target.directClosingSpeedKmh != null) {
        closingSpeedKmh = target.directClosingSpeedKmh!;
      } else {
        // Closing speed = Ego Speed - Target Speed (in 1D following model)
        closingSpeedKmh = egoSpeedKmh - target.speedKmh;
      }

      // Compute strictly validated TTC
      final ttcResult = calculateTtc(
        distanceMeters: distanceToTarget,
        closingSpeedKmh: closingSpeedKmh,
        measurementTimestamp: target.timestamp,
        isSensorReliable: target.isReliable,
      );

      if (ttcResult.isValid && ttcResult.ttcSeconds != null) {
        if (lowestTtc == null || ttcResult.ttcSeconds! < lowestTtc) {
          lowestTtc = ttcResult.ttcSeconds!;
          mostCriticalTarget = target;
          bestTtcResult = ttcResult;
        }
      }
    }

    // 4. Threat Classification based on validated TTC thresholds
    if (lowestTtc == null || mostCriticalTarget == null || bestTtcResult == null) {
      _resetThreatStateIfCleared();
      return SafetyStatus(
        riskLevel: RiskLevel.safe,
        message: 'Road condition safe',
        reason: 'Detected targets are either moving away, maintaining distance, or readings are invalid.',
      );
    }

    RiskLevel calculatedRisk;
    String message;

    if (lowestTtc <= ttcCriticalThreshold) {
      calculatedRisk = RiskLevel.critical;
      message = 'IMMEDIATE ATTENTION REQUIRED';
    } else if (lowestTtc <= ttcWarningThreshold) {
      calculatedRisk = RiskLevel.warning;
      message = 'Collision risk detected';
    } else if (lowestTtc <= ttcCautionThreshold) {
      calculatedRisk = RiskLevel.caution;
      message = 'Maintain safe distance';
    } else {
      calculatedRisk = RiskLevel.safe;
      message = 'Road condition safe';
    }

    // Update state tracking
    _lastActiveRiskLevel = calculatedRisk;
    _lastActiveThreatId = mostCriticalTarget.id;

    return SafetyStatus(
      riskLevel: calculatedRisk,
      message: message,
      ttcSeconds: lowestTtc,
      distanceMeters: bestTtcResult.distanceMeters,
      closingSpeedKmh: bestTtcResult.closingSpeedKmh,
      threatId: mostCriticalTarget.id,
      reason: 'TTC ${lowestTtc.toStringAsFixed(1)}s (dist: ${bestTtcResult.distanceMeters.toStringAsFixed(1)}m, closing: ${bestTtcResult.closingSpeedKmh.toStringAsFixed(1)} km/h)',
    );
  }

  RiskLevel _lastAlertRiskLevel = RiskLevel.safe;

  /// Determines whether a new alert notification should be triggered or suppressed
  /// to prevent spamming duplicate alerts for the exact same ongoing threat.
  bool shouldTriggerAlert({
    required SafetyStatus status,
    DateTime? now,
  }) {
    if (!status.hasActiveThreat) return false;

    final currentTime = now ?? DateTime.now();

    // If threat transitioned to a more severe level (e.g. caution -> warning -> critical), always trigger immediately
    final isEscalation = _isSeverityEscalation(_lastAlertRiskLevel, status.riskLevel);
    if (isEscalation) {
      _lastAlertTriggerTime = currentTime;
      _lastAlertRiskLevel = status.riskLevel;
      _lastActiveThreatId = status.threatId;
      return true;
    }

    // If it's a completely different threat object, trigger immediately
    if (status.threatId != null && status.threatId != _lastActiveThreatId) {
      _lastAlertTriggerTime = currentTime;
      _lastAlertRiskLevel = status.riskLevel;
      _lastActiveThreatId = status.threatId;
      return true;
    }

    // If within suppression window for the same threat and same/lower severity, suppress duplicate
    if (_lastAlertTriggerTime != null) {
      final elapsed = currentTime.difference(_lastAlertTriggerTime!);
      if (elapsed < duplicateAlertSuppressionWindow) {
        return false;
      }
    }

    _lastAlertTriggerTime = currentTime;
    _lastAlertRiskLevel = status.riskLevel;
    _lastActiveThreatId = status.threatId;
    return true;
  }

  bool _isSeverityEscalation(RiskLevel prev, RiskLevel current) {
    int rank(RiskLevel level) {
      switch (level) {
        case RiskLevel.critical:
          return 3;
        case RiskLevel.warning:
          return 2;
        case RiskLevel.caution:
          return 1;
        default:
          return 0;
      }
    }
    return rank(current) > rank(prev);
  }

  void _resetThreatStateIfCleared() {
    _lastActiveThreatId = null;
    _lastActiveRiskLevel = RiskLevel.safe;
    _lastAlertRiskLevel = RiskLevel.safe;
  }

  /// Resets internal engine state
  void reset() {
    _lastActiveThreatId = null;
    _lastActiveRiskLevel = RiskLevel.safe;
    _lastAlertRiskLevel = RiskLevel.safe;
    _lastAlertTriggerTime = null;
  }
}
