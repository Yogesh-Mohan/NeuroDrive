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
  group('Step 4 - AI Trip Safety Analyst Flutter Service Tests', () {
    final sampleTrip = TripModel(
      tripId: 'test_trip_123',
      uid: 'user_456',
      startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
      endLocation: const TripLocation(latitude: 12.9716, longitude: 77.5946),
      startTime: DateTime(2026, 10, 12, 8, 30),
      endTime: DateTime(2026, 10, 12, 8, 55),
      distance: 15400.0, // 15.4 km
      duration: 1500, // 25 min
      avgSpeed: 36.9,
    );

    final List<AlertModel> sampleAlerts = [
      AlertModel(
        id: 'alert_1',
        tripId: 'test_trip_123',
        alertType: 'CollisionRisk',
        severity: 'warning',
        message: 'Forward collision risk detected',
        timestamp: DateTime(2026, 10, 12, 8, 40),
        distance: 28.0,
        ttc: 3.2,
      ),
      AlertModel(
        id: 'alert_2',
        tripId: 'test_trip_123',
        alertType: 'SafeDistance',
        severity: 'caution',
        message: 'Maintain safe distance',
        timestamp: DateTime(2026, 10, 12, 8, 45),
        distance: 45.0,
        ttc: 5.5,
      ),
    ];

    test('AiSafetyReport.fromJson parses complete API response correctly', () {
      final mockJson = {
        'success': true,
        'model': 'google/flan-t5-base',
        'report': {
          'trip_summary': 'A car traveled 15.4 km in 25.0 minutes at an average speed of 36.9 km/h, with 2 safety alerts recorded.',
          'recorded_safety_events': [
            'Warning: Forward collision risk detected',
            'Caution: Maintain safe distance'
          ],
          'data_supported_observations': {
            'distance_km': 15.4,
            'duration_minutes': 25.0,
            'average_speed_kmh': 36.9,
            'total_alerts': 2,
            'telemetry_completeness': 'Complete',
            'risk_level': 'high'
          },
          'practical_recommendations': 'A driver should avoid a forward collision warning and maintain a safe following distance.',
          'risk_level': 'high'
        },
        'warnings': <String>[],
        'inference_time_sec': 7.32
      };

      final report = AiSafetyReport.fromJson(mockJson);

      expect(report.success, isTrue);
      expect(report.model, equals('google/flan-t5-base'));
      expect(report.tripSummary, contains('15.4 km'));
      expect(report.recordedSafetyEvents.length, equals(2));
      expect(report.riskLevel, equals('high'));
      expect(report.practicalRecommendations, contains('safe following distance'));
      expect(report.inferenceTimeSec, equals(7.32));
      expect(report.warnings, isEmpty);
    });

    test('AiSafetyService correctly formats payload and returns report', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/ai-trip-safety-report'));
        expect(request.method, equals('POST'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['distance_km'], equals(15.4));
        expect(body['duration_minutes'], equals(25.0));
        expect(body['avg_speed_kmh'], equals(36.9));
        expect(body['alert_count'], equals(2));
        expect((body['alerts'] as List).length, equals(2));

        return http.Response(
          jsonEncode({
            'success': true,
            'model': 'google/flan-t5-base',
            'report': {
              'trip_summary': 'Trip completed successfully.',
              'recorded_safety_events': ['Forward collision risk detected'],
              'data_supported_observations': {
                'distance_km': 15.4,
                'duration_minutes': 25.0,
                'average_speed_kmh': 36.9,
                'total_alerts': 2,
                'telemetry_completeness': 'Complete',
                'risk_level': 'high'
              },
              'practical_recommendations': 'Keep safe following distance.',
              'risk_level': 'high'
            },
            'warnings': <String>[],
            'inference_time_sec': 4.5
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiSafetyService(
        customBaseUrl: 'http://testserver:8000',
        client: mockClient,
      );

      final report = await service.generateTripSafetyReport(
        trip: sampleTrip,
        alerts: sampleAlerts,
      );

      expect(report.success, isTrue);
      expect(report.riskLevel, equals('high'));
      expect(report.tripSummary, equals('Trip completed successfully.'));
    });

    test('AiSafetyService handles 400 validation error gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'error': 'Invalid request payload format or value constraints.',
            'details': ['distance_km must be >= 0']
          }),
          400,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiSafetyService(
        customBaseUrl: 'http://testserver:8000',
        client: mockClient,
      );

      expect(
        () => service.generateTripSafetyReport(trip: sampleTrip),
        throwsA(isA<Exception>()),
      );
    });

    test('AiSafetyService handles 503 model service unavailable gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'AI inference engine is currently unavailable.'}),
          503,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiSafetyService(
        customBaseUrl: 'http://testserver:8000',
        client: mockClient,
      );

      expect(
        () => service.generateTripSafetyReport(trip: sampleTrip),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Step 4 - TripDetailsScreen Widget UI Tests', () {
    final sampleTrip = TripModel(
      tripId: 'test_trip_123',
      uid: 'user_456',
      startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
      endLocation: const TripLocation(latitude: 12.9716, longitude: 77.5946),
      startTime: DateTime(2026, 10, 12, 8, 30),
      endTime: DateTime(2026, 10, 12, 8, 55),
      distance: 15400.0,
      duration: 1500,
      avgSpeed: 36.9,
    );

    testWidgets('TripDetailsScreen renders telemetry and Generate AI Report button', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: TripDetailsScreen(trip: sampleTrip),
        ),
      );

      expect(find.text('Trip Details'), findsOneWidget);
      expect(find.text('15.40 km'), findsOneWidget);
      expect(find.text('25 min'), findsOneWidget);
      expect(find.text('36.9 km/h'), findsOneWidget);
      expect(find.text('Generate AI Safety Report'), findsOneWidget);
    });

    testWidgets('Tapping Generate AI Report displays loading state then report card', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'model': 'google/flan-t5-base',
            'report': {
              'trip_summary': 'A car traveled 15.4 km in 25.0 minutes at an average speed of 36.9 km/h, with 2 safety alerts recorded.',
              'recorded_safety_events': [
                'Warning: Forward collision risk detected',
                'Caution: Maintain safe distance'
              ],
              'data_supported_observations': {
                'distance_km': 15.4,
                'duration_minutes': 25.0,
                'average_speed_kmh': 36.9,
                'total_alerts': 2,
                'telemetry_completeness': 'Complete',
                'risk_level': 'high'
              },
              'practical_recommendations': 'A driver should avoid a forward collision warning and maintain a safe following distance.',
              'risk_level': 'high'
            },
            'warnings': <String>[],
            'inference_time_sec': 5.2
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
            trip: sampleTrip,
            aiSafetyService: service,
          ),
        ),
      );

      final generateBtn = find.text('Generate AI Safety Report');
      await tester.ensureVisible(generateBtn);
      await tester.pumpAndSettle();

      await tester.tap(generateBtn);
      await tester.pumpAndSettle(); // Settle mock response

      // Verify report card is displayed
      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(find.text('Trip Summary'), findsOneWidget);
      expect(find.textContaining('15.4 km in 25.0 minutes'), findsOneWidget);
      expect(find.text('Practical Recommendations'), findsOneWidget);
      expect(find.textContaining('safe following distance'), findsOneWidget);
      expect(find.textContaining('Disclaimer:'), findsOneWidget);
    });

    testWidgets('Displays error state and Retry button when API fails', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = AiSafetyService(
        customBaseUrl: 'http://testserver:8000',
        client: mockClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripDetailsScreen(
            trip: sampleTrip,
            aiSafetyService: service,
          ),
        ),
      );

      final generateBtn = find.text('Generate AI Safety Report');
      await tester.ensureVisible(generateBtn);
      await tester.pumpAndSettle();

      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      expect(find.text('Report Generation Failed'), findsOneWidget);
      expect(find.text('Retry Analysis'), findsOneWidget);
    });
  });
}
