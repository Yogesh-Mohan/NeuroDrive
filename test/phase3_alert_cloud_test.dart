import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_drive/core/models/alert_model.dart';
import 'package:neuro_drive/core/services/safety_engine.dart';

void main() {
  group('Phase 3 - AlertModel Tests', () {
    test('AlertModel initializes and serializes correctly', () {
      final now = DateTime(2026, 10, 11, 15, 30, 0);

      final alert = AlertModel(
        id: 'alert_001',
        tripId: 'trip_100',
        alertType: 'CRITICAL_COLLISION_ALERT',
        severity: 'critical',
        message: 'IMMEDIATE ATTENTION REQUIRED',
        distance: 18.5,
        relativeSpeed: 64.0,
        ttc: 1.8,
        latitude: 13.0827,
        longitude: 80.2707,
        timestamp: now,
        createdAt: now,
        isSynced: true,
      );

      expect(alert.id, 'alert_001');
      expect(alert.tripId, 'trip_100');
      expect(alert.alertType, 'CRITICAL_COLLISION_ALERT');
      expect(alert.severity, 'critical');
      expect(alert.riskLevel, 'critical');
      expect(alert.distance, 18.5);
      expect(alert.relativeSpeed, 64.0);
      expect(alert.ttc, 1.8);
      expect(alert.latitude, 13.0827);
      expect(alert.longitude, 80.2707);
      expect(alert.isSynced, isTrue);
    });

    test('AlertModel toFirestoreMap formats correct schema', () {
      final now = DateTime(2026, 10, 11, 16, 0, 0);

      final alert = AlertModel(
        id: 'alert_fs_01',
        tripId: 'trip_active',
        alertType: 'COLLISION_WARNING',
        severity: 'warning',
        message: 'Collision risk detected',
        distance: 35.0,
        relativeSpeed: 45.0,
        ttc: 3.2,
        latitude: 12.9815,
        longitude: 80.2180,
        timestamp: now,
        isSynced: true,
      );

      final map = alert.toFirestoreMap(useServerTimestamp: false);
      expect(map['alertId'], 'alert_fs_01');
      expect(map['tripId'], 'trip_active');
      expect(map['alertType'], 'COLLISION_WARNING');
      expect(map['severity'], 'warning');
      expect(map['message'], 'Collision risk detected');
      expect(map['distance'], 35.0);
      expect(map['relativeSpeed'], 45.0);
      expect(map['TTC'], 3.2);
      expect(map['latitude'], 12.9815);
      expect(map['longitude'], 80.2180);
    });

    test('AlertModel roundtrip toJsonMap and fromMap preserves telemetry', () {
      final now = DateTime.now();

      final original = AlertModel(
        id: 'alert_roundtrip',
        tripId: 'trip_xyz',
        alertType: 'CAUTION_ALERT',
        severity: 'caution',
        message: 'Maintain safe distance',
        distance: 50.0,
        relativeSpeed: 30.0,
        ttc: 6.0,
        latitude: 13.0,
        longitude: 80.0,
        timestamp: now,
        isSynced: false,
      );

      final json = original.toJsonMap();
      expect(json['isSynced'], isFalse);

      final reconstructed = AlertModel.fromMap(json);
      expect(reconstructed.id, original.id);
      expect(reconstructed.tripId, original.tripId);
      expect(reconstructed.severity, original.severity);
      expect(reconstructed.distance, original.distance);
      expect(reconstructed.ttc, original.ttc);
      expect(reconstructed.isSynced, isFalse);
    });

    test('AlertModel fromMap handles legacy SharedPreferences format gracefully', () {
      final legacy = {
        'id': 'legacy_alert_007',
        'timestamp': '2026-10-11T12:00:00.000',
        'riskLevel': 'RiskLevel.critical',
        'message': 'IMMEDIATE ATTENTION REQUIRED',
        'source': 'System',
      };

      final alert = AlertModel.fromMap(legacy);
      expect(alert.id, 'legacy_alert_007');
      expect(alert.severity, 'critical');
      expect(alert.message, 'IMMEDIATE ATTENTION REQUIRED');
      expect(alert.distance, isNull);
      expect(alert.ttc, isNull);
    });
  });

  group('Phase 3 - SafetyEngine Risk Classification Verification', () {
    test('SafetyEngine risk thresholds preserve caution, warning, and critical rules', () {
      expect(SafetyEngine.ttcCriticalThreshold, 2.5);
      expect(SafetyEngine.ttcWarningThreshold, 5.0);
      expect(SafetyEngine.minGpsAccuracyMeters, 20.0);
    });

    test('Alert ordering sorts newest first', () {
      final now = DateTime.now();
      final alerts = [
        AlertModel(
          id: 'a1',
          alertType: 'WARN',
          severity: 'warning',
          message: 'Older alert',
          timestamp: now.subtract(const Duration(hours: 3)),
        ),
        AlertModel(
          id: 'a2',
          alertType: 'CRIT',
          severity: 'critical',
          message: 'Newest alert',
          timestamp: now,
        ),
        AlertModel(
          id: 'a3',
          alertType: 'CAUT',
          severity: 'caution',
          message: 'Intermediate alert',
          timestamp: now.subtract(const Duration(hours: 1)),
        ),
      ];

      alerts.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      expect(alerts[0].id, 'a2'); // Newest
      expect(alerts[1].id, 'a3'); // 1 hr ago
      expect(alerts[2].id, 'a1'); // 3 hrs ago
    });
  });
}
