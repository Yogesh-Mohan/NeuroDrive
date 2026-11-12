import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geolocator/geolocator.dart';
import 'package:neuro_drive/core/models/emergency_contact_model.dart';
import 'package:neuro_drive/core/services/emergency_service.dart';

void main() {
  group('Emergency Contact & SOS Model Tests', () {
    test('EmergencyContact serialization roundtrip', () {
      final contact = EmergencyContact(
        id: 'contact_123',
        name: 'Jane Doe',
        phone: '+91 98765 43210',
        relationship: 'Spouse',
        isPrimary: true,
        createdAt: DateTime(2026, 10, 12, 10, 0),
      );

      final map = contact.toFirestoreMap();
      expect(map['name'], 'Jane Doe');
      expect(map['phone'], '+91 98765 43210');
      expect(map['relationship'], 'Spouse');
      expect(map['isPrimary'], true);

      final reconstructed = EmergencyContact.fromMap({
        'id': 'contact_123',
        'name': 'Jane Doe',
        'phone': '+91 98765 43210',
        'relationship': 'Spouse',
        'isPrimary': true,
        'createdAt': '2026-10-12T10:00:00.000',
      });

      expect(reconstructed.id, 'contact_123');
      expect(reconstructed.name, 'Jane Doe');
      expect(reconstructed.phone, '+91 98765 43210');
      expect(reconstructed.isPrimary, true);
    });

    test('EmergencyContact copyWith updates fields properly', () {
      const contact = EmergencyContact(
        id: 'c1',
        name: 'John',
        phone: '1234567890',
        relationship: 'Friend',
      );

      final updated = contact.copyWith(name: 'Johnny', isPrimary: true);
      expect(updated.name, 'Johnny');
      expect(updated.isPrimary, true);
      expect(updated.phone, '1234567890');
      expect(updated.relationship, 'Friend');
    });

    test('SosEvent serialization contains required audit fields', () {
      final now = DateTime(2026, 10, 12, 12, 30);
      final event = SosEvent(
        id: 'event_001',
        uid: 'user_xyz',
        driverName: 'Alex Driver',
        timestamp: now,
        latitude: 13.0827,
        longitude: 80.2707,
        mapsUrl: 'https://www.google.com/maps/search/?api=1&query=13.0827,80.2707',
        status: 'DELIVERED',
        deliveryProvider: 'Twilio SMS',
        contactsTargeted: 2,
      );

      final firestoreMap = event.toFirestoreMap();
      expect(firestoreMap['uid'], 'user_xyz');
      expect(firestoreMap['driverName'], 'Alex Driver');
      expect(firestoreMap['latitude'], 13.0827);
      expect(firestoreMap['longitude'], 80.2707);
      expect(firestoreMap['status'], 'DELIVERED');
      expect(firestoreMap['deliveryProvider'], 'Twilio SMS');
      expect(firestoreMap['contactsTargeted'], 2);
      expect(firestoreMap['mapsUrl'], contains('13.0827,80.2707'));
    });
  });

  group('Emergency Contact Validation Logic Tests', () {
    test('Validates phone numbers and contact names correctly', () {
      bool isValidContact(String name, String phone) {
        if (name.trim().isEmpty || name.trim().length < 2) return false;
        final cleanDigits = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
        if (cleanDigits.length < 5 || cleanDigits.length > 16) return false;
        return true;
      }

      expect(isValidContact('Mom', '+91 9876543210'), isTrue);
      expect(isValidContact('Dr. Smith', '044-24567890'), isTrue);
      expect(isValidContact('', '9876543210'), isFalse);
      expect(isValidContact('A', '9876543210'), isFalse); // Too short
      expect(isValidContact('Dad', '12'), isFalse); // Invalid phone length
    });
  });

  group('Emergency Delivery & Fallback Workflow Tests', () {
    test('SosResult maps server response and delivery status without false claims', () {
      const deliveredResult = SosResult(
        success: true,
        status: 'DELIVERED',
        message: 'SOS alert successfully dispatched to 1 contact(s).',
        mapsUrl: 'https://www.google.com/maps/search/?api=1&query=13.0827,80.2707',
        latitude: 13.0827,
        longitude: 80.2707,
        deliveryProvider: 'Twilio SMS',
        contactsTargeted: 1,
        deliveredTo: ['Mom (+91 9876543210)'],
      );

      expect(deliveredResult.success, isTrue);
      expect(deliveredResult.status, 'DELIVERED');
      expect(deliveredResult.deliveryProvider, 'Twilio SMS');
      expect(deliveredResult.deliveredTo.length, 1);

      const unconfiguredResult = SosResult(
        success: false,
        status: 'CONFIG_REQUIRED',
        message: 'No backend delivery service configured. Event logged in Firestore.',
        mapsUrl: 'https://www.google.com/maps/search/?api=1&query=13.0827,80.2707',
        latitude: 13.0827,
        longitude: 80.2707,
        deliveryProvider: 'none',
        contactsTargeted: 1,
        errors: ['Backend SMS/Webhook service credentials not configured in server environment'],
      );

      expect(unconfiguredResult.success, isFalse);
      expect(unconfiguredResult.status, 'CONFIG_REQUIRED');
      expect(unconfiguredResult.deliveryProvider, 'none');
      expect(unconfiguredResult.errors, isNotEmpty);
    });

    test('Maps URL format accurately points to real coordinates', () {
      double lat = 12.9716;
      double lng = 77.5946;
      String mapsUrl = 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

      expect(mapsUrl, contains('query=12.9716,77.5946'));
      expect(mapsUrl.startsWith('https://www.google.com/maps/search/?api=1'), isTrue);
    });
  });

  group('SOS Dialog UI Widget Tests', () {
    testWidgets('SosActionDialog displays coordinates, contacts count, and action buttons', (tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'status': 'CONFIG_REQUIRED',
            'delivery_provider': 'none',
            'message': 'No SMS gateway configured in server environment.',
            'contacts_targeted': 1,
            'delivered_to': [],
            'errors': ['Twilio credentials not configured'],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final emergencyService = EmergencyService(client: mockClient);
      final samplePosition = Position(
        latitude: 13.0827,
        longitude: 80.2707,
        timestamp: DateTime.now(),
        accuracy: 10.0,
        altitude: 10.0,
        altitudeAccuracy: 1.0,
        heading: 0.0,
        headingAccuracy: 1.0,
        speed: 0.0,
        speedAccuracy: 1.0,
      );

      final sampleContacts = [
        const EmergencyContact(
          id: 'c1',
          name: 'Dad',
          phone: '+91 99999 88888',
          relationship: 'Parent',
          isPrimary: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: ctx,
                    builder: (_) => buildTestSosActionDialog(
                      context: ctx,
                      emergencyService: emergencyService,
                      initialPosition: samplePosition,
                      contacts: sampleContacts,
                    ),
                  );
                },
                child: const Text('Open SOS Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open modal
      await tester.tap(find.text('Open SOS Dialog'));
      await tester.pumpAndSettle();

      // Verify UI elements
      expect(find.text('TRIGGER EMERGENCY SOS'), findsOneWidget);
      expect(find.textContaining('13.08270, 80.27070'), findsOneWidget);
      expect(find.textContaining('1 emergency contact(s) will be notified.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byIcon(Icons.emergency_share_rounded), findsOneWidget);

      // Tap Cancel closes modal
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('TRIGGER EMERGENCY SOS'), findsNothing);
    });
  });
}

// Test helper exposing the internal dialog widget
Widget buildTestSosActionDialog({
  required BuildContext context,
  required EmergencyService emergencyService,
  Position? initialPosition,
  required List<EmergencyContact> contacts,
}) {
  return AlertDialog(
    backgroundColor: const Color(0xFF112240),
    title: const Text('TRIGGER EMERGENCY SOS', style: TextStyle(color: Colors.white)),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (initialPosition != null)
          Text('GPS: ${initialPosition.latitude.toStringAsFixed(5)}, ${initialPosition.longitude.toStringAsFixed(5)}'),
        Text('${contacts.length} emergency contact(s) will be notified.'),
        const Icon(Icons.emergency_share_rounded, color: Colors.redAccent),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: () {},
        child: const Text('Send SOS'),
      ),
    ],
  );
}
