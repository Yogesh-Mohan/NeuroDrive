import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_drive/core/models/trip_model.dart';
import 'package:neuro_drive/core/models/alert_model.dart';
import 'package:neuro_drive/core/services/ai_safety_service.dart';
import 'package:neuro_drive/core/services/ai_copilot_service.dart';
import 'package:neuro_drive/screens/trip_details_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleTrip = TripModel(
    tripId: 'trip_gemini_001',
    uid: 'driver_tamil_01',
    startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
    endLocation: const TripLocation(latitude: 12.9716, longitude: 77.5946),
    startTime: DateTime(2026, 11, 2, 9, 0),
    endTime: DateTime(2026, 11, 2, 9, 30),
    distance: 25000.0, // 25 km
    duration: 1800, // 30 min
    avgSpeed: 50.0,
  );

  final sampleAlerts = [
    AlertModel(
      id: 'alert_gem_1',
      tripId: 'trip_gemini_001',
      alertType: 'CollisionRisk',
      severity: 'critical',
      message: 'Imminent collision risk detected',
      timestamp: DateTime(2026, 11, 2, 9, 15),
      distance: 12.0,
      ttc: 1.8,
    ),
    AlertModel(
      id: 'alert_gem_2',
      tripId: 'trip_gemini_001',
      alertType: 'SafeDistance',
      severity: 'warning',
      message: 'Maintain safe distance',
      timestamp: DateTime(2026, 11, 2, 9, 20),
      distance: 35.0,
      ttc: 4.2,
    ),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AiSafetyService.configuredGeminiApiKey = null;
    AiSafetyService.configuredGeminiModel = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  group('Gemini Flash AI Safety Analyst Tests', () {
    test('AiSafetyReport.fromJson parses direct Gemini JSON without nested report key', () {
      final directGeminiJson = {
        'trip_summary': 'Car 25.0 km distance-ah 30.0 minutes-la 50.0 km/h speed-la cover pannirukku. 2 alerts record aagirukku.',
        'recorded_safety_events': [
          '[CRITICAL] Imminent collision risk detected (12m, TTC: 1.8s)',
          '[WARNING] Maintain safe distance (35m, TTC: 4.2s)',
        ],
        'data_supported_observations': {
          'distance_km': 25.0,
          'duration_minutes': 30.0,
          'average_speed_kmh': 50.0,
          'total_alerts': 2,
          'telemetry_completeness': 'Complete',
          'risk_level': 'high',
        },
        'practical_recommendations': 'Munnala irukkira vehicle kitta minimum 3-second gap maintain pannunga. TTC 1.8s vandhadhala quick-aa brake pannunga.',
        'risk_level': 'high',
        'warnings': <String>[],
      };

      final report = AiSafetyReport.fromJson(
        directGeminiJson,
        defaultModel: 'gemini-1.5-flash',
        inferenceTimeSec: 0.95,
      );

      expect(report.success, isTrue);
      expect(report.model, equals('gemini-1.5-flash'));
      expect(report.tripSummary, contains('25.0 km'));
      expect(report.recordedSafetyEvents.length, equals(2));
      expect(report.riskLevel, equals('high'));
      expect(report.dataSupportedObservations['distance_km'], equals(25.0));
      expect(report.practicalRecommendations, contains('minimum 3-second gap'));
      expect(report.inferenceTimeSec, equals(0.95));
    });

    test('AiSafetyService calls Gemini Flash API directly and parses response in ~1 sec', () async {
      String? requestedUrl;
      Map<String, dynamic>? requestedBody;

      final mockClient = MockClient((request) async {
        requestedUrl = request.url.toString();
        requestedBody = jsonDecode(request.body) as Map<String, dynamic>;

        // Simulated Google Gemini Flash response
        final geminiResponseBody = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'trip_summary': 'Car 25.0 km distance-ah 30.0 minutes-la cover pannirukku. 2 alerts record aagirukku.',
                      'recorded_safety_events': [
                        '[CRITICAL] Imminent collision risk detected (12m, TTC: 1.8s)',
                        '[WARNING] Maintain safe distance (35m, TTC: 4.2s)',
                      ],
                      'data_supported_observations': {
                        'distance_km': 25.0,
                        'duration_minutes': 30.0,
                        'average_speed_kmh': 50.0,
                        'total_alerts': 2,
                        'telemetry_completeness': 'Complete',
                        'risk_level': 'high',
                      },
                      'practical_recommendations': 'Munnala vehicle kitta safe following distance maintain pannunga.',
                      'risk_level': 'high',
                      'warnings': [],
                    }),
                  }
                ],
                'role': 'model',
              },
              'finishReason': 'STOP',
            }
          ]
        };

        return http.Response(
          jsonEncode(geminiResponseBody),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiSafetyService(
        geminiApiKey: 'test_gemini_flash_key_123',
        preferGemini: true,
        client: mockClient,
      );

      final report = await service.generateTripSafetyReport(
        trip: sampleTrip,
        alerts: sampleAlerts,
        languageMode: 'tanglish',
      );

      // Verify Google Gemini API URL and query parameters
      expect(requestedUrl, contains('generativelanguage.googleapis.com'));
      expect(requestedUrl, contains('models/gemini-1.5-flash:generateContent'));
      expect(requestedUrl, contains('key=test_gemini_flash_key_123'));

      // Verify Gemini JSON generationConfig
      expect(requestedBody?['generationConfig']?['response_mime_type'], equals('application/json'));

      // Verify Prompt contains Thanglish instructions and trip facts
      final promptText = requestedBody?['contents']?[0]?['parts']?[0]?['text'] as String;
      expect(promptText, contains('25.00 km'));
      expect(promptText, contains('50.0 km/h'));
      expect(promptText, contains('Thanglish'));

      // Verify parsed output
      expect(report.success, isTrue);
      expect(report.model, equals('gemini-1.5-flash'));
      expect(report.riskLevel, equals('high'));
      expect(report.tripSummary, contains('25.0 km'));
      expect(report.practicalRecommendations, contains('safe following distance'));
      expect(report.inferenceTimeSec, isNotNull);
    });

    test('AiSafetyService correctly cleans markdown codeblocks in Gemini JSON output', () async {
      final mockClient = MockClient((request) async {
        final geminiResponseBody = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': '```json\n{"trip_summary": "Clean markdown stripped", "recorded_safety_events": [], "data_supported_observations": {"distance_km": 25.0, "duration_minutes": 30.0, "average_speed_kmh": 50.0, "total_alerts": 0, "telemetry_completeness": "Complete", "risk_level": "low"}, "practical_recommendations": "Keep driving safely", "risk_level": "low"}\n```',
                  }
                ],
              },
            }
          ]
        };

        return http.Response(
          jsonEncode(geminiResponseBody),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiSafetyService(
        geminiApiKey: 'test_key',
        preferGemini: true,
        client: mockClient,
      );

      final report = await service.generateTripSafetyReport(trip: sampleTrip);
      expect(report.tripSummary, equals('Clean markdown stripped'));
      expect(report.riskLevel, equals('low'));
    });

    test('AiSafetyService generates local deterministic report when offline or key is missing', () async {
      // No API key provided, preferGemini = true, enableLocalFallback = true
      final service = AiSafetyService(
        preferGemini: true,
        enableLocalFallback: true,
      );

      final report = await service.generateTripSafetyReport(
        trip: sampleTrip,
        alerts: sampleAlerts,
        languageMode: 'tanglish',
      );

      expect(report.success, isTrue);
      expect(report.model, equals('neuro-local-analyst'));
      expect(report.riskLevel, equals('high')); // Critical alert in sampleAlerts
      expect(report.dataSupportedObservations['distance_km'], equals(25.0));
      expect(report.dataSupportedObservations['duration_minutes'], equals(30.0));
      expect(report.tripSummary, contains('25.0 km'));
      expect(report.warnings, isNotEmpty);
      expect(report.inferenceTimeSec, equals(0.05));
    });

    test('AiSafetyService deterministically marks clean trips as low risk', () async {
      final cleanTrip = TripModel(
        tripId: 'clean_1',
        uid: 'user_1',
        startLocation: const TripLocation(latitude: 13.0, longitude: 80.0),
        endLocation: const TripLocation(latitude: 13.1, longitude: 80.1),
        startTime: DateTime(2026, 11, 2, 10, 0),
        endTime: DateTime(2026, 11, 2, 10, 20),
        distance: 12000.0,
        duration: 1200,
        avgSpeed: 36.0,
      );

      final service = AiSafetyService(preferGemini: true, enableLocalFallback: true);
      final report = await service.generateTripSafetyReport(trip: cleanTrip, alerts: []);

      expect(report.riskLevel, equals('low'));
      expect(report.tripSummary, contains('Safety alerts edhum illai'));
      expect(report.practicalRecommendations, contains('Super driving'));
    });

    test('AiSafetyService persists and reads Gemini API key via SharedPreferences', () async {
      expect(await AiSafetyService.getStoredGeminiApiKey(), isNull);

      await AiSafetyService.saveGeminiApiKey('AIzaSyNewCustomKey');
      expect(await AiSafetyService.getStoredGeminiApiKey(), equals('AIzaSyNewCustomKey'));
      expect(await AiSafetyService.getEffectiveApiKeyStatic(), equals('AIzaSyNewCustomKey'));
    });
  });

  group('Gemini Copilot Service Tests', () {
    test('AiCopilotService queries Gemini Flash when API key is available', () async {
      AiSafetyService.configuredGeminiApiKey = 'test_copilot_key';

      final mockClient = MockClient((request) async {
        expect(request.url.toString(), contains('generativelanguage.googleapis.com'));
        expect(request.url.toString(), contains('key=test_copilot_key'));

        final responseJson = {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'text': jsonEncode({
                      'answer': 'Route clear-ah irukku. Speed 50-la maintain pannunga.',
                      'intent': 'speed',
                      'audio_tts': 'Route clear-ah irukku.',
                      'actionable_recommendation': 'Maintain safe following distance.',
                    }),
                  }
                ],
              },
            }
          ]
        };

        return http.Response(
          jsonEncode(responseJson),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final copilot = AiCopilotService();
      copilot.customClient = mockClient;

      final answer = await copilot.askCopilot(
        query: 'Speed safe-aa irukka?',
        currentSpeedKmh: 50.0,
        languageMode: 'tanglish',
      );

      expect(answer.success, isTrue);
      expect(answer.isLocalFallback, isFalse);
      expect(answer.answer, contains('Route clear-ah irukku'));
      expect(answer.audioTts, equals('Route clear-ah irukku.'));
      expect(answer.actionableRecommendation, contains('safe following distance'));
    });

    test('AiCopilotService falls back to local engine when Gemini call fails', () async {
      AiSafetyService.configuredGeminiApiKey = 'test_copilot_key';

      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final copilot = AiCopilotService();
      copilot.customClient = mockClient;

      final answer = await copilot.askCopilot(
        query: 'Vanakkam',
        currentSpeedKmh: 45.0,
        languageMode: 'tanglish',
      );

      expect(answer.success, isTrue);
      expect(answer.isLocalFallback, isTrue);
      expect(answer.answer, contains('Vanakkam'));
    });

    test('AiCopilotService correctly selects Zero-shot, One-shot, or Few-shot prompt method', () {
      final copilot = AiCopilotService();

      // Greetings / simple queries -> Zero-shot
      expect(copilot.selectPromptMethod('Hello'), equals(PromptMethod.zeroShot));
      expect(copilot.selectPromptMethod('Vanakkam bro'), equals(PromptMethod.zeroShot));

      // Location / Navigation / Reverse Geocoding queries -> One-shot
      expect(copilot.selectPromptMethod('Naa ippo enga irukan?'), equals(PromptMethod.oneShot));
      expect(copilot.selectPromptMethod('Where am I currently located?'), equals(PromptMethod.oneShot));
      expect(copilot.selectPromptMethod('Chennai map location sollu'), equals(PromptMethod.oneShot));

      // ADAS / TTC / Safety / Hazard queries -> Few-shot
      expect(copilot.selectPromptMethod('Danger warning vantha enna pannanum?'), equals(PromptMethod.fewShot));
      expect(copilot.selectPromptMethod('Heavy rain driving safety tips'), equals(PromptMethod.fewShot));
      expect(copilot.selectPromptMethod('Emergency brake condition'), equals(PromptMethod.fewShot));
    });

    testWidgets('TripDetailsScreen renders Download Report button and opens confirmation dialog', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'model': 'gemini-1.5-flash',
            'trip_summary': 'Trip 25.0 km completed safely in 30.0 minutes with 2 alerts.',
            'recorded_safety_events': ['Forward collision warning', 'Maintain safe distance'],
            'data_supported_observations': {
              'distance_km': 25.0,
              'duration_minutes': 30.0,
              'average_speed_kmh': 50.0,
              'total_alerts': 2,
              'telemetry_completeness': 'Complete',
              'safety_score': 84,
              'risk_level': 'medium'
            },
            'practical_recommendations': 'Maintain safe distance at 50 km/h.',
            'risk_level': 'medium',
            'warnings': <String>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = AiSafetyService(
        customBaseUrl: 'http://testserver:8000',
        client: mockClient,
      );

      final tempDir = Directory.systemTemp.createTempSync('neuro_report_test');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      await tester.pumpWidget(
        MaterialApp(
          home: TripDetailsScreen(
            trip: sampleTrip,
            aiSafetyService: service,
            getDocsDirectory: () async => tempDir,
          ),
        ),
      );

      final generateBtn = find.text('Generate AI Safety Report');
      await tester.ensureVisible(generateBtn);
      await tester.pumpAndSettle();

      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      // Scroll so download button is fully visible
      final downloadBtn = find.byKey(const Key('download_report_button'));
      await tester.scrollUntilVisible(find.textContaining('Disclaimer:'), 300, scrollable: find.byType(Scrollable));
      await tester.pumpAndSettle();
      expect(downloadBtn, findsOneWidget);
      expect(find.text('Download Trip Safety Report'), findsOneWidget);

      // Invoke download button action
      final button = tester.widget<ElevatedButton>(downloadBtn);
      button.onPressed?.call();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify confirmation dialog
      expect(find.text('Report Downloaded'), findsOneWidget);
      expect(find.textContaining('Trip Safety Report has been generated'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      // Close dialog
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Report Downloaded'), findsNothing);
    });
  });
}
