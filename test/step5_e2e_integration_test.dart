import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_drive/core/models/trip_model.dart';
import 'package:neuro_drive/core/models/alert_model.dart';
import 'package:neuro_drive/core/services/ai_safety_service.dart';
import 'package:neuro_drive/screens/trip_details_screen.dart';

void main() {
  group('Step 5 - End-to-End Flutter UI & Workflow Validation', () {
    final tripAlerted = TripModel(
      tripId: 'trip_alerted_1',
      uid: 'user_001',
      startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
      endLocation: const TripLocation(latitude: 13.0012, longitude: 80.2565),
      startTime: DateTime(2026, 10, 12, 10, 0),
      endTime: DateTime(2026, 10, 12, 10, 25),
      distance: 15400.0, // 15.4 km
      duration: 1500, // 25 min
      avgSpeed: 36.9,
    );

    final tripClean = TripModel(
      tripId: 'trip_clean_2',
      uid: 'user_001',
      startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
      endLocation: const TripLocation(latitude: 12.8342, longitude: 79.7036),
      startTime: DateTime(2026, 10, 12, 14, 0),
      endTime: DateTime(2026, 10, 12, 14, 40),
      distance: 42000.0, // 42 km
      duration: 2400, // 40 min
      avgSpeed: 63.0,
    );

    final sampleAlerts = [
      AlertModel(
        id: 'a_1',
        tripId: 'trip_alerted_1',
        alertType: 'CollisionRisk',
        severity: 'warning',
        message: 'Forward collision risk detected',
        timestamp: DateTime(2026, 10, 12, 10, 10),
        distance: 28.0,
        ttc: 3.2,
      ),
      AlertModel(
        id: 'a_2',
        tripId: 'trip_alerted_1',
        alertType: 'SafeDistance',
        severity: 'caution',
        message: 'Maintain safe distance',
        timestamp: DateTime(2026, 10, 12, 10, 15),
        distance: 45.0,
        ttc: 5.5,
      ),
    ];

    testWidgets('Verification I: Repeated taps do not trigger duplicate concurrent requests', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        // Introduce small artificial latency to allow checking debounce
        await Future.delayed(const Duration(milliseconds: 100));
        return http.Response(
          jsonEncode({
            'success': true,
            'model': 'google/flan-t5-base',
            'report': {
              'trip_summary': 'Trip completed.',
              'recorded_safety_events': ['Forward collision risk detected'],
              'data_supported_observations': {
                'distance_km': 15.4,
                'duration_minutes': 25.0,
                'average_speed_kmh': 36.9,
                'total_alerts': 2,
                'telemetry_completeness': 'Complete',
                'risk_level': 'high'
              },
              'practical_recommendations': 'Maintain safe distance.',
              'risk_level': 'high'
            },
            'warnings': <String>[],
            'inference_time_sec': 3.7
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiSafetyService(
        customBaseUrl: 'http://testserver:8000',
        client: mockClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripDetailsScreen(
            trip: tripAlerted,
            allAlerts: sampleAlerts,
            aiSafetyService: service,
          ),
        ),
      );

      final generateBtn = find.text('Generate AI Safety Report');
      await tester.ensureVisible(generateBtn);
      await tester.pumpAndSettle();

      // Tap 3 times rapidly
      await tester.tap(generateBtn);
      await tester.tap(generateBtn, warnIfMissed: false);
      await tester.tap(generateBtn, warnIfMissed: false);

      await tester.pumpAndSettle();

      // Only exactly ONE request must have been dispatched
      expect(requestCount, equals(1));
      expect(find.text('HIGH RISK'), findsOneWidget);
    });

    testWidgets('Verification J: Multiple different trips produce distinct reports in UI', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final isAlertedTrip = (body['alert_count'] as int) > 0;

        return http.Response(
          jsonEncode({
            'success': true,
            'model': 'google/flan-t5-base',
            'report': {
              'trip_summary': isAlertedTrip
                  ? 'A car traveled 15.4 km with 2 safety alerts.'
                  : 'A car traveled 42.0 km with 0 safety alerts.',
              'recorded_safety_events': isAlertedTrip
                  ? ['Warning: Forward collision risk detected']
                  : ['No safety alerts recorded during trip.'],
              'data_supported_observations': {
                'distance_km': isAlertedTrip ? 15.4 : 42.0,
                'duration_minutes': isAlertedTrip ? 25.0 : 40.0,
                'average_speed_kmh': isAlertedTrip ? 36.9 : 63.0,
                'total_alerts': isAlertedTrip ? 2 : 0,
                'telemetry_completeness': 'Complete',
                'risk_level': isAlertedTrip ? 'high' : 'low'
              },
              'practical_recommendations': isAlertedTrip
                  ? 'Maintain a safe following distance.'
                  : 'avoiding distractions',
              'risk_level': isAlertedTrip ? 'high' : 'low'
            },
            'warnings': <String>[],
            'inference_time_sec': 3.1
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiSafetyService(
        customBaseUrl: 'http://testserver:8000',
        client: mockClient,
      );

      // Render Alerted Trip
      await tester.pumpWidget(
        MaterialApp(
          home: TripDetailsScreen(
            key: const Key('trip_1'),
            trip: tripAlerted,
            allAlerts: sampleAlerts,
            aiSafetyService: service,
          ),
        ),
      );

      await tester.ensureVisible(find.text('Generate AI Safety Report'));
      await tester.tap(find.text('Generate AI Safety Report'));
      await tester.pumpAndSettle();

      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(find.textContaining('15.4 km with 2 safety alerts'), findsOneWidget);

      // Now Render Clean Trip with unique key
      await tester.pumpWidget(
        MaterialApp(
          home: TripDetailsScreen(
            key: const Key('trip_2'),
            trip: tripClean,
            allAlerts: const [],
            aiSafetyService: service,
          ),
        ),
      );

      await tester.ensureVisible(find.text('Generate AI Safety Report'));
      await tester.tap(find.text('Generate AI Safety Report'));
      await tester.pumpAndSettle();

      expect(find.text('LOW RISK'), findsOneWidget);
      expect(find.textContaining('42.0 km with 0 safety alerts'), findsOneWidget);
    });

    testWidgets('Verification E & F: Graceful error recovery and Retry Flow', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      int attempt = 0;
      final mockClient = MockClient((request) async {
        attempt++;
        if (attempt == 1) {
          // First attempt fails with 503
          return http.Response(
            jsonEncode({'detail': 'AI inference engine is currently unavailable.'}),
            503,
            headers: {'content-type': 'application/json'},
          );
        } else {
          // Second attempt (retry) succeeds
          return http.Response(
            jsonEncode({
              'success': true,
              'model': 'google/flan-t5-base',
              'report': {
                'trip_summary': 'Recovered trip analysis.',
                'recorded_safety_events': ['No safety alerts recorded during trip.'],
                'data_supported_observations': {
                  'distance_km': 42.0,
                  'duration_minutes': 40.0,
                  'average_speed_kmh': 63.0,
                  'total_alerts': 0,
                  'telemetry_completeness': 'Complete',
                  'risk_level': 'low'
                },
                'practical_recommendations': 'Drive safely.',
                'risk_level': 'low'
              },
              'warnings': <String>[],
              'inference_time_sec': 2.8
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
      });

      final service = AiSafetyService(
        customBaseUrl: 'http://testserver:8000',
        client: mockClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripDetailsScreen(
            trip: tripClean,
            aiSafetyService: service,
          ),
        ),
      );

      // Attempt 1 -> Fails
      await tester.ensureVisible(find.text('Generate AI Safety Report'));
      await tester.tap(find.text('Generate AI Safety Report'));
      await tester.pumpAndSettle();

      expect(find.text('Report Generation Failed'), findsOneWidget);
      expect(find.text('Retry Analysis'), findsOneWidget);

      // Attempt 2 -> Tap Retry -> Succeeds
      await tester.tap(find.text('Retry Analysis'));
      await tester.pumpAndSettle();

      expect(find.text('LOW RISK'), findsOneWidget);
      expect(find.text('Recovered trip analysis.'), findsOneWidget);
      expect(attempt, equals(2));
    });
  });
}
