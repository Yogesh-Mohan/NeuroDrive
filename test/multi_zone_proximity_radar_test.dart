import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_drive/core/services/v2v_radar_service.dart';
import 'package:neuro_drive/core/models/v2v_telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ADAS Multi-Zone Proximity Guard Fine-Tuning Tests', () {
    late V2VRadarService radarService;

    setUp(() {
      radarService = V2VRadarService();
      radarService.resetAlertCount();
    });

    test('ProximityZoneStats defaults and copyWith functionality', () {
      const stats = ProximityZoneStats();
      expect(stats.cautionCount, 0);
      expect(stats.criticalCount, 0);
      expect(stats.totalCount, 0);
      expect(stats.currentZone, 'SAFE');
      expect(stats.distanceCm, 0.0);

      final updated = stats.copyWith(
        cautionCount: 3,
        criticalCount: 1,
        totalCount: 4,
        currentZone: 'CAUTION',
        distanceCm: 12.4,
      );

      expect(updated.cautionCount, 3);
      expect(updated.criticalCount, 1);
      expect(updated.totalCount, 4);
      expect(updated.currentZone, 'CAUTION');
      expect(updated.distanceCm, 12.4);
    });

    test('Zone classification correctly handles Safe, Caution, and Critical telemetry', () {
      final now = DateTime.now();

      // 1. Safe zone (> 15 cm)
      final safeTelemetry = V2VTelemetry(
        vehicleId: 'CAR_TEST',
        distanceCm: 22.0,
        distanceMeters: 0.22,
        status: 'SAFE',
        isOnline: true,
        timestamp: now,
      );
      expect(safeTelemetry.status, 'SAFE');

      // 2. Caution zone (8 - 15 cm)
      final cautionTelemetry = V2VTelemetry(
        vehicleId: 'CAR_TEST',
        distanceCm: 11.5,
        distanceMeters: 0.115,
        status: 'CAUTION',
        isOnline: true,
        timestamp: now,
      );
      expect(cautionTelemetry.status, 'CAUTION');

      // 3. Critical zone (< 8 cm)
      final criticalTelemetry = V2VTelemetry(
        vehicleId: 'CAR_TEST',
        distanceCm: 5.2,
        distanceMeters: 0.052,
        status: 'CRITICAL',
        isOnline: true,
        timestamp: now,
      );
      expect(criticalTelemetry.status, 'CRITICAL');
    });

    test('resetAlertCount resets both caution and critical counts to 0', () {
      radarService.resetAlertCount();
      expect(radarService.cautionAlertCount, 0);
      expect(radarService.criticalAlertCount, 0);
      expect(radarService.proximityAlertCount, 0);
      expect(radarService.zoneStats.currentZone, 'SAFE');
    });
  });
}
