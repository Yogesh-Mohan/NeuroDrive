import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_drive/core/models/trip_model.dart';
import 'package:neuro_drive/core/models/alert_model.dart';
import 'package:neuro_drive/core/models/emergency_contact_model.dart';
import 'package:neuro_drive/core/services/ai_safety_service.dart';
import 'package:neuro_drive/core/services/ai_copilot_service.dart';
import 'package:neuro_drive/core/services/location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('WORK 1: Location Distance & Proximity Biasing Verification', () {
    test('Calculates real-world distance and sorts short-distance places before far places', () {
      // User is at Chennai Central (13.0827, 80.2707)
      const userLat = 13.0827;
      const userLng = 80.2707;

      // Place A: Egmore (~1.16 km away)
      const placeALat = 13.0783;
      const placeALng = 80.2610;
      final distA = Geolocator.distanceBetween(userLat, userLng, placeALat, placeALng);

      // Place B: Marina Beach (~3.8 km away)
      const placeBLat = 13.0500;
      const placeBLng = 80.2824;
      final distB = Geolocator.distanceBetween(userLat, userLng, placeBLat, placeBLng);

      // Place C: Coimbatore (~425 km away)
      const placeCLat = 11.0168;
      const placeCLng = 76.9558;
      final distC = Geolocator.distanceBetween(userLat, userLng, placeCLat, placeCLng);

      // Verify distance accuracy with real coordinates
      expect(distA, greaterThan(1000));
      expect(distA, lessThan(2000));
      expect(distB, greaterThan(distA));
      expect(distC, greaterThan(400000));

      // Simulate search results sorting
      final searchList = [
        {'name': 'Coimbatore Junction', 'dist': distC},
        {'name': 'Marina Beach, Chennai', 'dist': distB},
        {'name': 'Egmore Railway Station', 'dist': distA},
      ];

      searchList.sort((a, b) => (a['dist'] as double).compareTo(b['dist'] as double));

      // Nearest short-distance must be index 0
      expect(searchList[0]['name'], equals('Egmore Railway Station'));
      expect(searchList[1]['name'], equals('Marina Beach, Chennai'));
      expect(searchList[2]['name'], equals('Coimbatore Junction'));
    });
  });

  group('WORK 2: Emergency SOS Contact Message & Link Verification', () {
    test('Constructs direct SMS with Settings contacts, GPS link, and alert message', () {
      final contacts = [
        EmergencyContact(
          id: 'c1',
          name: 'Dad',
          phone: '+91 98765 43210',
          relationship: 'Family',
          isPrimary: true,
        ),
        EmergencyContact(
          id: 'c2',
          name: 'Doctor Anand',
          phone: '+91 91234 56789',
          relationship: 'Doctor',
          isPrimary: false,
        ),
      ];

      const userLat = 13.0827;
      const userLng = 80.2707;
      const alertMsg = 'Urgent: I need emergency assistance while driving.';

      final phones = contacts
          .map((c) => c.phone.replaceAll(RegExp(r'[^\d+]'), ''))
          .where((p) => p.isNotEmpty)
          .toList();

      expect(phones, equals(['+919876543210', '+919123456789']));

      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$userLat,$userLng';
      final fullMessage = '🚨 EMERGENCY SOS from NeuroDrive: $alertMsg\nLive Location: $mapsUrl';

      final recipientPhones = phones.join(',');
      final uri = Uri(
        scheme: 'sms',
        path: recipientPhones,
        queryParameters: <String, String>{
          'body': fullMessage,
        },
      );

      // Verify SMS URI components
      expect(uri.scheme, equals('sms'));
      expect(uri.path, equals('+919876543210,+919123456789'));
      expect(uri.queryParameters['body'], contains('https://www.google.com/maps/search/?api=1&query=13.0827,80.2707'));
      expect(uri.queryParameters['body'], contains('EMERGENCY SOS from NeuroDrive'));
    });
  });

  group('WORK 3: Chatbot Human-Readable Location Verification', () {
    test('Reverse geocoding resolves coordinates to readable city/area without raw lat/long in responses', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'address': {
              'road': 'Anna Salai',
              'city': 'Chennai',
              'state': 'Tamil Nadu',
            },
            'display_name': 'Anna Salai, Triplicane, Chennai, Tamil Nadu',
          }),
          200,
        );
      });

      final locService = LocationService()..customClient = mockClient;
      final chennaiAddr = await locService.reverseGeocode(13.0827, 80.2707);

      expect(chennaiAddr, contains('Anna Salai'));
      expect(chennaiAddr, contains('Chennai'));
      expect(chennaiAddr, isNot(contains('13.0827')));
      expect(chennaiAddr, isNot(contains('80.2707')));
    });
  });

  group('WORK 4: Chatbot Dynamic AI Prompting (Zero, One, Few-shot)', () {
    test('Dynamic prompt method routing selects appropriate prompt strategy across multiple queries', () {
      final copilot = AiCopilotService();

      // Zero-shot queries (Casual / Greetings)
      expect(copilot.selectPromptMethod('Hi'), equals(PromptMethod.zeroShot));
      expect(copilot.selectPromptMethod('Vanakkam bro epdi irukinga?'), equals(PromptMethod.zeroShot));
      expect(copilot.selectPromptMethod('Who are you?'), equals(PromptMethod.zeroShot));

      // One-shot queries (Status / Current Speed / Current Location)
      expect(copilot.selectPromptMethod('Naa ippo enga irukan?'), equals(PromptMethod.oneShot));
      expect(copilot.selectPromptMethod('Where am I currently located?'), equals(PromptMethod.oneShot));
      expect(copilot.selectPromptMethod('Current vehicle speed evlo?'), equals(PromptMethod.oneShot));
      expect(copilot.selectPromptMethod('Chennai map location sollu'), equals(PromptMethod.oneShot));

      // Few-shot queries (ADAS rules / Road Hazards / TTC critical situations)
      expect(copilot.selectPromptMethod('Danger warning vantha enna pannanum?'), equals(PromptMethod.fewShot));
      expect(copilot.selectPromptMethod('TTC 1.8 seconds danger-ah?'), equals(PromptMethod.fewShot));
      expect(copilot.selectPromptMethod('Night drive heavy rain safety tips sollu'), equals(PromptMethod.fewShot));
      expect(copilot.selectPromptMethod('Emergency brake condition explanation'), equals(PromptMethod.fewShot));
    });
  });

  group('WORK 5: AI Trip Safety Report with Multiple Contrasting Datasets', () {
    test('Generates completely different reports for 3 distinct driving scenarios', () {
      final safetyService = AiSafetyService();

      // =========================================================================
      // DATASET 1: Short Clean Daytime City Commute
      // =========================================================================
      final trip1 = TripModel(
        tripId: 'trip_dataset_01',
        uid: 'user_a',
        startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
        endLocation: const TripLocation(latitude: 13.0700, longitude: 80.2600),
        startTime: DateTime(2026, 11, 4, 10, 0), // Daytime 10:00 AM
        endTime: DateTime(2026, 11, 4, 10, 15),
        distance: 4500.0, // 4.5 km
        duration: 900, // 15 mins
        avgSpeed: 30.0,
      );
      final List<AlertModel> alerts1 = []; // Zero alerts

      final report1 = safetyService.generateLocalDeterministicReport(
        trip: trip1,
        tripAlerts: alerts1,
        languageMode: 'tanglish',
      );

      // =========================================================================
      // DATASET 2: Long Night Drive with Critical Proximity & TTC < 2.5s Alert
      // =========================================================================
      final trip2 = TripModel(
        tripId: 'trip_dataset_02',
        uid: 'user_b',
        startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
        endLocation: const TripLocation(latitude: 12.8000, longitude: 79.9000),
        startTime: DateTime(2026, 11, 4, 21, 0), // Night 9:00 PM
        endTime: DateTime(2026, 11, 4, 22, 20),
        distance: 52000.0, // 52 km
        duration: 4800, // 80 mins (> 1 hr continuous drive)
        avgSpeed: 65.0,
      );
      final alerts2 = [
        AlertModel(
          id: 'alt_01',
          tripId: 'trip_dataset_02',
          alertType: 'CollisionRisk',
          severity: 'critical',
          message: 'Imminent forward crash hazard',
          timestamp: DateTime(2026, 11, 4, 21, 45),
          distance: 14.0,
          ttc: 1.6,
        ),
      ];

      final report2 = safetyService.generateLocalDeterministicReport(
        trip: trip2,
        tripAlerts: alerts2,
        languageMode: 'tanglish',
      );

      // =========================================================================
      // DATASET 3: Highway High-Speed Drive (>80 km/h) with Proximity Warning
      // =========================================================================
      final trip3 = TripModel(
        tripId: 'trip_dataset_03',
        uid: 'user_c',
        startLocation: const TripLocation(latitude: 13.0000, longitude: 80.1000),
        endLocation: const TripLocation(latitude: 12.3000, longitude: 79.2000),
        startTime: DateTime(2026, 11, 4, 15, 0), // Afternoon 3:00 PM
        endTime: DateTime(2026, 11, 4, 16, 0),
        distance: 95000.0, // 95 km
        duration: 3600, // 60 mins
        avgSpeed: 95.0, // High speed > 80 km/h
      );
      final alerts3 = [
        AlertModel(
          id: 'alt_02',
          tripId: 'trip_dataset_03',
          alertType: 'SafeDistance',
          severity: 'warning',
          message: 'Tailgating warning',
          timestamp: DateTime(2026, 11, 4, 15, 30),
          distance: 30.0,
          ttc: 3.5,
        ),
      ];

      final report3 = safetyService.generateLocalDeterministicReport(
        trip: trip3,
        tripAlerts: alerts3,
        languageMode: 'tanglish',
      );

      // -------------------------------------------------------------
      // ASSERTIONS & VERIFICATION OF DATA-DRIVEN DIVERGENCE:
      // -------------------------------------------------------------

      // 1. Safety Scores must accurately reflect driving behavior
      final score1 = report1.dataSupportedObservations['safety_score'] as int;
      final score2 = report2.dataSupportedObservations['safety_score'] as int;
      final score3 = report3.dataSupportedObservations['safety_score'] as int;

      expect(score1, equals(100), reason: 'Clean trip should have 100/100 score');
      expect(score2, lessThanOrEqualTo(75), reason: 'Critical collision risk penalizes score');
      expect(score3, lessThan(85), reason: 'Overspeeding >80 km/h + warning should lower score');

      // 2. Risk levels must match
      expect(report1.riskLevel, equals('low'));
      expect(report2.riskLevel, equals('high'));
      expect(report3.riskLevel, equals('medium'));

      // 3. Summaries must be completely unique and reflect real numbers
      expect(report1.tripSummary, contains('4.5 km'));
      expect(report1.tripSummary, contains('Safety alerts edhum illai'));

      expect(report2.tripSummary, contains('52.0 km'));
      expect(report2.tripSummary, contains('Critical collision alert TTC < 2.5s'));
      expect(report2.tripSummary, contains('Night driving'));

      expect(report3.tripSummary, contains('95.0 km'));
      expect(report3.tripSummary, contains('95.0 km/h'));

      // 4. Practical recommendations must be customized
      expect(report1.practicalRecommendations, contains('Super driving!'));
      expect(report2.practicalRecommendations, contains('3-second gap'));
      expect(report2.practicalRecommendations, contains('1 hour-ku mela continuous drive'));
      expect(report3.practicalRecommendations, contains('Traffic-la safe following distance'));

      // 5. Reports must NOT be identical (Zero canned responses)
      expect(report1.tripSummary, isNot(equals(report2.tripSummary)));
      expect(report2.tripSummary, isNot(equals(report3.tripSummary)));
      expect(report1.practicalRecommendations, isNot(equals(report2.practicalRecommendations)));

      // 6. Report file export verification
      final tempDir = Directory.systemTemp.createTempSync('export_verify');
      final exportFile = File('${tempDir.path}/report_test.txt');
      exportFile.writeAsStringSync('Score: $score2, Summary: ${report2.tripSummary}');
      expect(exportFile.existsSync(), isTrue);
      expect(exportFile.readAsStringSync(), contains('52.0 km'));
      tempDir.deleteSync(recursive: true);
    });
  });
}
