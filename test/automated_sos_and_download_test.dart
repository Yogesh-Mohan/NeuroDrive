import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_drive/core/models/alert_model.dart';
import 'package:neuro_drive/core/models/emergency_contact_model.dart';
import 'package:neuro_drive/core/models/trip_model.dart';
import 'package:neuro_drive/core/services/ai_safety_service.dart';
import 'package:neuro_drive/core/services/emergency_service.dart';
import 'package:neuro_drive/core/services/trip_report_pdf_service.dart';
import 'package:neuro_drive/widgets/sos_dialog_helper.dart';
import 'package:neuro_drive/screens/trip_details_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        return null;
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.neurodrive.app/native_service'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'sendDirectSms') return true;
        if (methodCall.method == 'hasSmsPermission') return true;
        if (methodCall.method == 'requestSmsPermission') return true;
        if (methodCall.method == 'openDefaultSmsApp') return true;
        if (methodCall.method == 'savePdfToDownloads') return '/storage/emulated/0/Download/test.pdf';
        if (methodCall.method == 'openPdfFile') return true;
        return null;
      },
    );
  });

  group('Automated Emergency SOS Verification', () {
    test('SMS URI generation supports multi-recipient and primary fallback', () {
      final contacts = [
        EmergencyContact(
          id: 'c1',
          name: 'Appa',
          phone: '+91 98765 43210',
          isPrimary: true,
        ),
        EmergencyContact(
          id: 'c2',
          name: 'Amma',
          phone: '+91 91234 56789',
          isPrimary: false,
        ),
      ];

      final phones = contacts
          .map((c) => c.phone.replaceAll(RegExp(r'[^\d+]'), ''))
          .where((p) => p.isNotEmpty)
          .toList();

      expect(phones, equals(['+919876543210', '+919123456789']));

      final primaryContact = contacts.firstWhere(
        (c) => c.isPrimary && c.phone.replaceAll(RegExp(r'[^\d+]'), '').isNotEmpty,
        orElse: () => contacts.first,
      );
      expect(primaryContact.phone, contains('98765 43210'));

      const msg = 'Urgent: I need emergency assistance while driving.';
      const lat = 13.0827;
      const lon = 80.2707;
      final mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lon';
      final fullMessage = '🚨 EMERGENCY SOS from NeuroDrive: $msg\nLive Location: $mapsUrl';

      final uriMulti = Uri(
        scheme: 'sms',
        path: phones.join(','),
        queryParameters: {'body': fullMessage},
      );
      expect(uriMulti.scheme, equals('sms'));
      expect(uriMulti.path, equals('+919876543210,+919123456789'));
      expect(uriMulti.queryParameters['body'], contains('Live Location: https://www.google.com/maps'));

      final uriSingle = Uri(
        scheme: 'sms',
        path: primaryContact.phone.replaceAll(RegExp(r'[^\d+]'), ''),
        queryParameters: {'body': fullMessage},
      );
      expect(uriSingle.path, equals('+919876543210'));
    });

    test('EmergencyService hasSmsPermission and requestSmsPermission succeed', () async {
      final service = EmergencyService();
      final hasPerm = await service.hasSmsPermission();
      expect(hasPerm, isTrue);

      final requested = await service.requestSmsPermission();
      expect(requested, isTrue);
    });

    test('sendDirectSmsToContacts dispatches directly in background without opening chooser', () async {
      final service = EmergencyService();
      final contacts = [
        const EmergencyContact(
          id: 'c1',
          name: 'Dad',
          phone: '+91 98765 43210',
          isPrimary: true,
        ),
      ];

      final sent = await service.sendDirectSmsToContacts(
        contacts: contacts,
        emergencyMessage: 'Test emergency message',
        latitude: 13.0827,
        longitude: 80.2707,
      );

      expect(sent, isTrue);
    });

    test('SosResult encapsulates accurate delivery and coordinates', () {
      const res = SosResult(
        success: true,
        status: 'DELIVERED',
        message: 'Dispatched to 2 contacts',
        mapsUrl: 'https://www.google.com/maps/search/?api=1&query=13.0827,80.2707',
        latitude: 13.0827,
        longitude: 80.2707,
        deliveryProvider: 'NeuroDrive Secure Gateway',
        contactsTargeted: 2,
        deliveredTo: ['+919876543210', '+919123456789'],
      );

      expect(res.success, isTrue);
      expect(res.status, equals('DELIVERED'));
      expect(res.latitude, equals(13.0827));
      expect(res.deliveredTo.length, equals(2));
    });

    testWidgets('Automated SOS modal countdown auto-triggers dispatch when timer reaches 0', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => SosDialogHelper.showSosConfirmationDialog(ctx),
                child: const Text('Open SOS'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open SOS'));
      await tester.pump();

      // Confirmation dialog should be visible with countdown indicator
      expect(find.text('TRIGGER EMERGENCY SOS'), findsOneWidget);
      expect(find.textContaining('Automated dispatch in'), findsOneWidget);

      // Advance clock through the 3-second countdown
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      // Verify it automatically transitions to dispatching step
      expect(find.text('DISPATCHING SOS...'), findsOneWidget);
    });
  });

  group('Trip Safety Report Download & Viewer Verification', () {
    test('TripReportPdfService generates valid PDF bytes with header %PDF', () async {
      final sampleTrip = TripModel(
        tripId: 'test_pdf_trip_01',
        uid: 'user_pdf_01',
        startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
        endLocation: const TripLocation(latitude: 13.0500, longitude: 80.2400),
        startTime: DateTime(2026, 11, 4, 10, 0),
        endTime: DateTime(2026, 11, 4, 10, 30),
        distance: 15000.0,
        duration: 1800,
        avgSpeed: 30.0,
      );

      final sampleReport = AiSafetyReport(
        success: true,
        model: 'gemini-1.5-flash',
        tripSummary: 'Good trip with 15.0 km distance covered safely.',
        recordedSafetyEvents: ['Safe distance buffer alert'],
        dataSupportedObservations: {
          'distance_km': 15.0,
          'duration_minutes': 30.0,
          'average_speed_kmh': 30.0,
          'total_alerts': 1,
          'telemetry_completeness': 'Complete',
          'safety_score': 95,
          'risk_level': 'low',
        },
        practicalRecommendations: 'Continue maintaining 3-second buffer.',
        riskLevel: 'low',
        warnings: [],
      );

      final pdfBytes = await TripReportPdfService.generateTripReportPdf(
        trip: sampleTrip,
        report: sampleReport,
        alerts: [],
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(200));
      // Standard PDF magic byte sequence: %PDF
      expect(String.fromCharCodes(pdfBytes.take(4)), equals('%PDF'));
    });

    testWidgets('Download Trip Safety Report writes file and opens success dialog with View Report button', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final tempDir = Directory.systemTemp.createTempSync('trip_report_test_dir');
      addTearDown(() {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      });

      final sampleTrip = TripModel(
        tripId: 'test_trip_download_99',
        uid: 'user_test_99',
        startLocation: const TripLocation(latitude: 13.0827, longitude: 80.2707),
        endLocation: const TripLocation(latitude: 13.0500, longitude: 80.2400),
        startTime: DateTime(2026, 11, 4, 10, 0),
        endTime: DateTime(2026, 11, 4, 10, 30),
        distance: 12500.0,
        duration: 1800,
        avgSpeed: 25.0,
      );

      final sampleAlerts = [
        AlertModel(
          id: 'alt_01',
          tripId: 'test_trip_download_99',
          alertType: 'SafeDistance',
          severity: 'warning',
          message: 'Safe distance buffer alert',
          timestamp: DateTime(2026, 11, 4, 10, 15),
          distance: 18.0,
          ttc: 2.2,
        ),
      ];

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'model': 'gemini-1.5-flash',
            'trip_summary': 'Trip 12.5 km completed safely with 1 alert.',
            'recorded_safety_events': ['Safe distance buffer alert'],
            'data_supported_observations': {
              'distance_km': 12.5,
              'duration_minutes': 30.0,
              'average_speed_kmh': 25.0,
              'total_alerts': 1,
              'telemetry_completeness': 'Complete',
              'safety_score': 90,
              'risk_level': 'low'
            },
            'practical_recommendations': 'Maintain safe buffer at 25 km/h.',
            'risk_level': 'low',
            'warnings': <String>[],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final aiService = AiSafetyService(
        customBaseUrl: 'http://testserver:8000',
        client: mockClient,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: TripDetailsScreen(
            trip: sampleTrip,
            allAlerts: sampleAlerts,
            aiSafetyService: aiService,
            getDocsDirectory: () async => tempDir,
          ),
        ),
      );

      // Verify screen rendered
      expect(find.text('Trip Details'), findsOneWidget);

      final generateBtn = find.text('Generate AI Safety Report');
      await tester.ensureVisible(generateBtn);
      await tester.pumpAndSettle();

      // Tap generate report button
      await tester.tap(generateBtn);
      await tester.pumpAndSettle();

      // Report content rendered
      expect(find.text('Trip Summary'), findsOneWidget);

      final downloadBtn = find.byKey(const Key('download_report_button'));
      await tester.ensureVisible(downloadBtn);
      await tester.pumpAndSettle();

      // Invoke download report button
      final button = tester.widget<ElevatedButton>(downloadBtn);
      button.onPressed?.call();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Verify Report Downloaded dialog is shown
      expect(find.text('Report Downloaded'), findsOneWidget);
      expect(find.text('View Full Report Now'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      // Verify file was written to disk
      final expectedPdf = File('${tempDir.path}/NeuroDrive_TripReport_test_trip_download_99.pdf');
      expect(expectedPdf.existsSync(), isTrue);
      final pdfBytes = expectedPdf.readAsBytesSync();
      expect(pdfBytes.length, greaterThan(100));
      expect(String.fromCharCodes(pdfBytes.take(4)), equals('%PDF'));

      final expectedFile = File('${tempDir.path}/NeuroDrive_TripReport_test_trip_download_99.txt');
      expect(expectedFile.existsSync(), isTrue);

      final content = expectedFile.readAsStringSync();
      expect(content, contains('NEURODRIVE AI TRIP SAFETY REPORT'));
      expect(content, contains('test_trip_download_99'));
      expect(content, contains('12.5 km'));

      // Tap View Full Report Now button
      await tester.tap(find.text('View Full Report Now'));
      await tester.pumpAndSettle();

      // Verify bottom sheet reader opens with full content
      expect(find.text('Copy Text'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // Tap Done to close reader
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
    });
  });
}
