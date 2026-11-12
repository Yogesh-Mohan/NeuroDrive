import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_drive/core/models/alert_model.dart';
import 'package:neuro_drive/core/models/detected_vehicle.dart';
import 'package:neuro_drive/core/services/safety_engine.dart';
import 'package:neuro_drive/core/services/alert_priority_assistant.dart';

void main() {
  group('SafetyEngine & TTC Validation Tests', () {
    late SafetyEngine engine;

    setUp(() {
      engine = SafetyEngine();
      engine.reset();
    });

    Position createPosition({
      double speed = 16.67, // ~60 km/h in m/s
      double accuracy = 5.0,
      double latitude = 13.0827,
      double longitude = 80.2707,
    }) {
      return Position(
        latitude: latitude,
        longitude: longitude,
        timestamp: DateTime.now(),
        accuracy: accuracy,
        altitude: 10.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 1.0,
        speed: speed,
        speedAccuracy: 1.0,
      );
    }

    test('TTC Formula: TTC = Distance / Closing Speed with unit conversion (km/h to m/s)', () {
      // 50 meters distance, 36 km/h closing speed (= 10 m/s)
      // Expected TTC = 50 / 10 = 5.0 seconds
      final result = SafetyEngine.calculateTtc(
        distanceMeters: 50.0,
        closingSpeedKmh: 36.0,
      );

      expect(result.isValid, isTrue);
      expect(result.ttcSeconds, closeTo(5.0, 0.001));
      expect(result.closingSpeedMs, closeTo(10.0, 0.001));
    });

    test('TTC Validation: Approaching object triggers valid TTC', () {
      // 20 meters distance, 72 km/h closing speed (= 20 m/s)
      // TTC = 20 / 20 = 1.0 second (Critical)
      final result = SafetyEngine.calculateTtc(
        distanceMeters: 20.0,
        closingSpeedKmh: 72.0,
      );

      expect(result.isValid, isTrue);
      expect(result.ttcSeconds, closeTo(1.0, 0.001));
      expect(result.ttcSeconds! <= SafetyEngine.ttcCriticalThreshold, isTrue);
    });

    test('TTC Validation: Negative closing speed (target pulling away) yields invalid TTC', () {
      // Ego is slower than target (closing speed = -20 km/h)
      final result = SafetyEngine.calculateTtc(
        distanceMeters: 40.0,
        closingSpeedKmh: -20.0,
      );

      expect(result.isValid, isFalse);
      expect(result.ttcSeconds, isNull);
      expect(result.calculationReason, contains('negative closing speed'));
    });

    test('TTC Validation: Zero closing speed (constant distance) yields invalid TTC', () {
      final result = SafetyEngine.calculateTtc(
        distanceMeters: 30.0,
        closingSpeedKmh: 0.0,
      );

      expect(result.isValid, isFalse);
      expect(result.ttcSeconds, isNull);
      expect(result.calculationReason, contains('Zero relative closing speed'));
    });

    test('TTC Validation: Invalid sensor readings (NaN, infinite, negative, zero distance)', () {
      // NaN distance
      expect(SafetyEngine.calculateTtc(distanceMeters: double.nan, closingSpeedKmh: 40.0).isValid, isFalse);
      // Infinite distance
      expect(SafetyEngine.calculateTtc(distanceMeters: double.infinity, closingSpeedKmh: 40.0).isValid, isFalse);
      // Zero distance
      expect(SafetyEngine.calculateTtc(distanceMeters: 0.0, closingSpeedKmh: 40.0).isValid, isFalse);
      // Negative distance
      expect(SafetyEngine.calculateTtc(distanceMeters: -15.0, closingSpeedKmh: 40.0).isValid, isFalse);
      // Below min reliable distance threshold
      expect(SafetyEngine.calculateTtc(distanceMeters: 0.1, closingSpeedKmh: 40.0).isValid, isFalse);
      // Beyond max reliable distance threshold
      expect(SafetyEngine.calculateTtc(distanceMeters: 500.0, closingSpeedKmh: 40.0).isValid, isFalse);
      // NaN closing speed
      expect(SafetyEngine.calculateTtc(distanceMeters: 25.0, closingSpeedKmh: double.nan).isValid, isFalse);
      // Excessive unrealistic closing speed
      expect(SafetyEngine.calculateTtc(distanceMeters: 25.0, closingSpeedKmh: 400.0).isValid, isFalse);
    });

    test('TTC Validation: Stale measurement data is safely rejected', () {
      final staleTime = DateTime.now().subtract(const Duration(seconds: 10));
      final result = SafetyEngine.calculateTtc(
        distanceMeters: 25.0,
        closingSpeedKmh: 30.0,
        measurementTimestamp: staleTime,
      );

      expect(result.isValid, isFalse);
      expect(result.ttcSeconds, isNull);
      expect(result.calculationReason, contains('stale'));
    });

    test('TTC Validation: Unreliable sensor flag is safely rejected', () {
      final result = SafetyEngine.calculateTtc(
        distanceMeters: 25.0,
        closingSpeedKmh: 30.0,
        isSensorReliable: false,
      );

      expect(result.isValid, isFalse);
      expect(result.ttcSeconds, isNull);
      expect(result.calculationReason, contains('unreliable'));
    });

    test('SafetyEngine: Evaluates critical, warning, and caution threshold boundaries accurately', () {
      final egoPos = createPosition(speed: 20.0); // 72 km/h

      // 1. Critical boundary: TTC = 2.0s <= 2.5s
      final targetCritical = DetectedVehicle.fromEsp32(
        id: 'target_crit',
        distanceMeters: 20.0,
        closingSpeedKmh: 36.0, // 10 m/s -> TTC = 2.0s
      );
      final statusCrit = engine.evaluateRisk(
        currentEgoPosition: egoPos,
        detectedObjects: [targetCritical],
      );
      expect(statusCrit.riskLevel, RiskLevel.critical);
      expect(statusCrit.ttcSeconds, closeTo(2.0, 0.01));
      expect(statusCrit.message, 'IMMEDIATE ATTENTION REQUIRED');

      // 2. Warning boundary: TTC = 4.0s (<= 5.0s and > 2.5s)
      final targetWarning = DetectedVehicle.fromEsp32(
        id: 'target_warn',
        distanceMeters: 40.0,
        closingSpeedKmh: 36.0, // 10 m/s -> TTC = 4.0s
      );
      final statusWarn = engine.evaluateRisk(
        currentEgoPosition: egoPos,
        detectedObjects: [targetWarning],
      );
      expect(statusWarn.riskLevel, RiskLevel.warning);
      expect(statusWarn.ttcSeconds, closeTo(4.0, 0.01));
      expect(statusWarn.message, 'Collision risk detected');

      // 3. Caution boundary: TTC = 7.0s (<= 10.0s and > 5.0s)
      final targetCaution = DetectedVehicle.fromEsp32(
        id: 'target_caut',
        distanceMeters: 70.0,
        closingSpeedKmh: 36.0, // 10 m/s -> TTC = 7.0s
      );
      final statusCaut = engine.evaluateRisk(
        currentEgoPosition: egoPos,
        detectedObjects: [targetCaution],
      );
      expect(statusCaut.riskLevel, RiskLevel.caution);
      expect(statusCaut.ttcSeconds, closeTo(7.0, 0.01));
      expect(statusCaut.message, 'Maintain safe distance');

      // 4. Safe headway: TTC = 15.0s (> 10.0s)
      final targetSafe = DetectedVehicle.fromEsp32(
        id: 'target_safe',
        distanceMeters: 150.0,
        closingSpeedKmh: 36.0, // 10 m/s -> TTC = 15.0s
      );
      final statusSafe = engine.evaluateRisk(
        currentEgoPosition: egoPos,
        detectedObjects: [targetSafe],
      );
      expect(statusSafe.riskLevel, RiskLevel.safe);
      expect(statusSafe.message, 'Road condition safe');
    });

    test('SafetyEngine: GPS speed alone without sensor hardware does not claim collision warning', () {
      final egoPos = createPosition(speed: 30.0); // 108 km/h, moving fast
      final status = engine.evaluateRisk(
        currentEgoPosition: egoPos,
        detectedObjects: [], // No hardware sensor data
      );

      expect(status.riskLevel, RiskLevel.safe);
      expect(status.ttcSeconds, isNull);
      expect(status.message, contains('hardware integration required'));
    });

    test('SafetyEngine: Degraded GPS accuracy flags status as unavailable', () {
      final degradedGps = createPosition(accuracy: 35.0); // Worse than 20m threshold
      final status = engine.evaluateRisk(
        currentEgoPosition: degradedGps,
        detectedObjects: [
          DetectedVehicle.fromEsp32(id: 't1', distanceMeters: 20.0, closingSpeedKmh: 40.0),
        ],
      );

      expect(status.riskLevel, RiskLevel.unavailable);
      expect(status.isGpsReliable, isFalse);
      expect(status.message, 'GPS accuracy insufficient');
    });

    test('SafetyEngine: Duplicate alert prevention and severity escalation', () {
      final egoPos = createPosition();
      final now = DateTime.now();

      final targetWarning = DetectedVehicle.fromEsp32(
        id: 'car_ahead_1',
        distanceMeters: 36.0,
        closingSpeedKmh: 36.0, // TTC = 3.6s (Warning)
      );

      // First warning event triggers alert
      final status1 = engine.evaluateRisk(currentEgoPosition: egoPos, detectedObjects: [targetWarning]);
      expect(engine.shouldTriggerAlert(status: status1, now: now), isTrue);

      // Same threat within 2 seconds with same severity is suppressed
      expect(engine.shouldTriggerAlert(status: status1, now: now.add(const Duration(seconds: 2))), isFalse);

      // Threat escalates to critical (distance closes to 15m, TTC = 1.5s): MUST trigger immediately!
      final targetCritical = DetectedVehicle.fromEsp32(
        id: 'car_ahead_1',
        distanceMeters: 15.0,
        closingSpeedKmh: 36.0, // TTC = 1.5s (Critical)
      );
      final status2 = engine.evaluateRisk(currentEgoPosition: egoPos, detectedObjects: [targetCritical]);
      expect(engine.shouldTriggerAlert(status: status2, now: now.add(const Duration(seconds: 3))), isTrue);

      // Threat clears: engine state resets appropriately
      engine.evaluateRisk(currentEgoPosition: egoPos, detectedObjects: []);
      expect(engine.lastActiveRiskLevel, RiskLevel.safe);
      expect(engine.lastActiveThreatId, isNull);
    });
  });

  group('AI Alert Priority Assistant Tests', () {
    test('evaluateSingleAlert: Correctly ranks critical, high, medium, and low using physical data', () {
      final assistant = AlertPriorityAssistant();
      final now = DateTime.now();

      final criticalAlert = AlertModel(
        id: 'crit_1',
        alertType: 'CRITICAL_COLLISION_ALERT',
        severity: 'critical',
        message: 'IMMEDIATE ATTENTION REQUIRED',
        distance: 8.5,
        relativeSpeed: 60.0,
        ttc: 1.2,
        timestamp: now,
      );

      final prioritizedCrit = assistant.evaluateSingleAlert(criticalAlert);
      expect(prioritizedCrit.priority, AlertPriorityLevel.critical);
      expect(prioritizedCrit.priorityScore >= 80, isTrue);
      expect(prioritizedCrit.audioVoicePrompt, contains('Brake now'));
      expect(prioritizedCrit.priorityReason, contains('Imminent impact TTC'));

      final warningAlert = AlertModel(
        id: 'warn_1',
        alertType: 'COLLISION_WARNING',
        severity: 'warning',
        message: 'Collision risk detected',
        distance: 35.0,
        relativeSpeed: 40.0,
        ttc: 3.5,
        timestamp: now,
      );

      final prioritizedWarn = assistant.evaluateSingleAlert(warningAlert);
      expect(prioritizedWarn.priority, AlertPriorityLevel.high);
      expect(prioritizedWarn.priorityScore, inInclusiveRange(40, 79));
      expect(prioritizedWarn.audioVoicePrompt, contains('Slow down'));

      final cautionAlert = AlertModel(
        id: 'caut_1',
        alertType: 'CAUTION_ALERT',
        severity: 'caution',
        message: 'Maintain safe distance',
        distance: 65.0,
        relativeSpeed: 25.0,
        ttc: 8.0,
        timestamp: now,
      );

      final prioritizedCaut = assistant.evaluateSingleAlert(cautionAlert);
      expect(prioritizedCaut.priority, AlertPriorityLevel.medium);
      expect(prioritizedCaut.audioVoicePrompt, contains('Maintain safe following distance'));
    });

    test('prioritizeAlerts: Sorts multiple simultaneous alerts so the most urgent is presented first', () async {
      final assistant = AlertPriorityAssistant();
      final now = DateTime.now();

      final alerts = [
        AlertModel(
          id: 'a_caut',
          alertType: 'CAUTION_ALERT',
          severity: 'caution',
          message: 'Safe distance advisory',
          distance: 50.0,
          ttc: 7.5,
          timestamp: now.subtract(const Duration(seconds: 1)),
        ),
        AlertModel(
          id: 'a_crit',
          alertType: 'CRITICAL_COLLISION_ALERT',
          severity: 'critical',
          message: 'IMMEDIATE ATTENTION REQUIRED',
          distance: 12.0,
          ttc: 1.8,
          timestamp: now,
        ),
        AlertModel(
          id: 'a_warn',
          alertType: 'COLLISION_WARNING',
          severity: 'warning',
          message: 'Forward hazard',
          distance: 30.0,
          ttc: 4.0,
          timestamp: now.subtract(const Duration(seconds: 2)),
        ),
      ];

      final result = await assistant.prioritizeAlerts(alerts, requestAiEnhancement: false);

      expect(result.prioritizedAlerts.length, 3);
      expect(result.topAlert?.alert.id, 'a_crit');
      expect(result.prioritizedAlerts[0].priority, AlertPriorityLevel.critical);
      expect(result.prioritizedAlerts[1].priority, AlertPriorityLevel.high);
      expect(result.prioritizedAlerts[2].priority, AlertPriorityLevel.medium);
    });

    test('prioritizeAlerts: Gracefully falls back to deterministic safety rules if AI backend fails', () async {
      // Mock client that returns 503 or throws error
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'error': 'Backend offline'}), 503);
      });

      final assistant = AlertPriorityAssistant(client: mockClient);
      final alert = AlertModel(
        id: 'crit_test',
        alertType: 'CRITICAL_COLLISION_ALERT',
        severity: 'critical',
        message: 'IMMEDIATE ATTENTION REQUIRED',
        distance: 10.0,
        ttc: 1.5,
        timestamp: DateTime.now(),
      );

      final result = await assistant.prioritizeAlerts([alert], requestAiEnhancement: true);

      // Even though AI was offline, deterministic safety must strictly hold
      expect(result.isAiAssisted, isFalse);
      expect(result.topAlert?.priority, AlertPriorityLevel.critical);
      expect(result.summaryExplanation, contains('Prioritized based on deterministic physical metrics'));
    });

    test('prioritizeAlerts: Integrates successfully with AI endpoint when available', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'summary_recommendation': 'CRITICAL: Immediate collision risk detected. Apply braking immediately.',
            'top_threat_id': 'crit_test',
            'recommended_audio_action': 'Critical hazard ahead. Brake immediately.',
          }),
          200,
        );
      });

      final assistant = AlertPriorityAssistant(client: mockClient);
      final alert = AlertModel(
        id: 'crit_test',
        alertType: 'CRITICAL_COLLISION_ALERT',
        severity: 'critical',
        message: 'IMMEDIATE ATTENTION REQUIRED',
        distance: 10.0,
        ttc: 1.5,
        timestamp: DateTime.now(),
      );

      final result = await assistant.prioritizeAlerts([alert], requestAiEnhancement: true);

      expect(result.isAiAssisted, isTrue);
      expect(result.summaryExplanation, contains('CRITICAL: Immediate collision risk detected'));
      expect(result.topAlert?.priority, AlertPriorityLevel.critical);
    });

    test('Voice Prompt Delivery: Avoids spamming driver with duplicate voice prompts', () {
      final assistant = AlertPriorityAssistant();
      assistant.resetCooldowns();
      final now = DateTime.now();

      final highAlert = PrioritizedAlert(
        alert: AlertModel(
          id: 'warn_id',
          alertType: 'COLLISION_WARNING',
          severity: 'warning',
          message: 'Warning',
          timestamp: now,
        ),
        priority: AlertPriorityLevel.high,
        priorityScore: 70,
        priorityReason: 'Closing rapidly',
        audioVoicePrompt: 'Warning: Vehicle closing rapidly.',
      );

      // First prompt triggers
      expect(assistant.shouldDeliverVoicePrompt(highAlert, now: now), isTrue);

      // 3 seconds later: suppressed
      expect(assistant.shouldDeliverVoicePrompt(highAlert, now: now.add(const Duration(seconds: 3))), isFalse);

      // 10 seconds later: allowed
      expect(assistant.shouldDeliverVoicePrompt(highAlert, now: now.add(const Duration(seconds: 10))), isTrue);
    });

    test('Conservatively handles missing, negative, and invalid data without inventing hazards', () {
      final assistant = AlertPriorityAssistant();
      final emptyAlert = AlertModel(
        id: 'empty_data',
        alertType: 'SYSTEM_EVENT',
        severity: 'info',
        message: 'System check',
        distance: null,
        relativeSpeed: null,
        ttc: null,
        timestamp: DateTime.now(),
      );

      final prioritized = assistant.evaluateSingleAlert(emptyAlert);
      expect(prioritized.priority, AlertPriorityLevel.low);
      expect(prioritized.priorityScore, 0);
      expect(prioritized.priorityReason, contains('No reliable TTC data'));
    });
  });
}
