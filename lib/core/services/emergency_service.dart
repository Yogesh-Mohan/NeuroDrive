import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/emergency_contact_model.dart';
import 'location_service.dart';
import 'ai_safety_service.dart';


class SosResult {
  final bool success;
  final String status; // 'DELIVERED', 'CONFIG_REQUIRED', 'DELIVERY_FAILED', 'RECORDED_ONLY'
  final String message;
  final String? eventId;
  final String mapsUrl;
  final double? latitude;
  final double? longitude;
  final String deliveryProvider;
  final int contactsTargeted;
  final List<String> deliveredTo;
  final List<String> errors;

  const SosResult({
    required this.success,
    required this.status,
    required this.message,
    this.eventId,
    required this.mapsUrl,
    this.latitude,
    this.longitude,
    required this.deliveryProvider,
    this.contactsTargeted = 0,
    this.deliveredTo = const [],
    this.errors = const [],
  });

  SosResult copyWith({
    bool? success,
    String? status,
    String? message,
    String? eventId,
    String? mapsUrl,
    double? latitude,
    double? longitude,
    String? deliveryProvider,
    int? contactsTargeted,
    List<String>? deliveredTo,
    List<String>? errors,
  }) {
    return SosResult(
      success: success ?? this.success,
      status: status ?? this.status,
      message: message ?? this.message,
      eventId: eventId ?? this.eventId,
      mapsUrl: mapsUrl ?? this.mapsUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      deliveryProvider: deliveryProvider ?? this.deliveryProvider,
      contactsTargeted: contactsTargeted ?? this.contactsTargeted,
      deliveredTo: deliveredTo ?? this.deliveredTo,
      errors: errors ?? this.errors,
    );
  }
}

class EmergencyService {
  final FirebaseFirestore? _customFirestore;
  final FirebaseAuth? _customAuth;
  final LocationService _locationService;
  final http.Client _client;

  // In-flight debounce guard to strictly prevent duplicate concurrent triggers
  bool _isSosInProgress = false;
  bool get isSosInProgress => _isSosInProgress;

  EmergencyService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    LocationService? locationService,
    http.Client? client,
  })  : _customFirestore = firestore,
        _customAuth = auth,
        _locationService = locationService ?? LocationService(),
        _client = client ?? http.Client();

  FirebaseFirestore get _firestore => _customFirestore ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _customAuth ?? FirebaseAuth.instance;

  User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  // ==========================================
  // EMERGENCY CONTACTS MANAGEMENT (FIRESTORE)
  // Subcollection: users/{uid}/emergency_contacts
  // ==========================================

  CollectionReference<Map<String, dynamic>> _contactsCollection(String uid) {
    return _firestore.collection('users').doc(uid).collection('emergency_contacts');
  }

  /// Streams emergency contacts for the current authenticated user in real-time.
  Stream<List<EmergencyContact>> getEmergencyContactsStream() {
    final uid = currentUser?.uid;
    if (uid == null) {
      return Stream.value([]);
    }

    return _contactsCollection(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => EmergencyContact.fromFirestore(doc)).toList();
    });
  }

  static const String _localContactsKey = 'neurodrive_cached_emergency_contacts';

  /// Fetches list of emergency contacts with offline cache support.
  Future<List<EmergencyContact>> getEmergencyContacts() async {
    final uid = currentUser?.uid;

    if (uid != null) {
      try {
        final snapshot = await _contactsCollection(uid).get().timeout(const Duration(seconds: 3));
        final list = snapshot.docs.map((doc) => EmergencyContact.fromFirestore(doc)).toList();
        if (list.isNotEmpty) {
          _cacheContactsLocally(list);
          return list;
        }
      } catch (e) {
        debugPrint('Error getting emergency contacts from Firestore: $e');
      }
    }

    // Fallback to local SharedPreferences cache
    return await _loadContactsLocally();
  }

  Future<void> _cacheContactsLocally(List<EmergencyContact> contacts) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 400));
      final encoded = jsonEncode(contacts.map((c) => {
        'id': c.id,
        'name': c.name,
        'phone': c.phone,
        'relationship': c.relationship,
        'isPrimary': c.isPrimary,
        'createdAt': c.createdAt?.toIso8601String(),
        'updatedAt': c.updatedAt?.toIso8601String(),
      }).toList());
      await prefs.setString(_localContactsKey, encoded);
    } catch (_) {}
  }

  Future<List<EmergencyContact>> _loadContactsLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 400));
      final raw = prefs.getString(_localContactsKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        return list.map((item) => EmergencyContact.fromMap(Map<String, dynamic>.from(item as Map))).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Adds or updates an emergency contact with validation.
  Future<void> saveEmergencyContact({
    String? id,
    required String name,
    required String phone,
    String relationship = 'Family',
    bool isPrimary = false,
  }) async {
    final cleanName = name.trim();
    final cleanPhone = phone.trim();
    final cleanRel = relationship.trim();

    if (cleanName.isEmpty) {
      throw Exception("Contact name cannot be empty.");
    }
    if (cleanPhone.isEmpty) {
      throw Exception("Phone number cannot be empty.");
    }

    // Phone validation (digits, plus, spaces, dashes)
    final cleanPhoneDigits = cleanPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleanPhoneDigits.length < 5 || cleanPhoneDigits.length > 16) {
      throw Exception("Enter a valid phone number (at least 5 digits).");
    }

    final effectiveId = id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final contact = EmergencyContact(
      id: effectiveId,
      name: cleanName,
      phone: cleanPhone,
      relationship: cleanRel.isEmpty ? 'Family' : cleanRel,
      isPrimary: isPrimary,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Save to Firestore if user logged in
    final uid = currentUser?.uid;
    if (uid != null) {
      try {
        final docRef = _contactsCollection(uid).doc(effectiveId);
        await docRef.set(contact.toFirestoreMap(), SetOptions(merge: true)).timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('Firestore save failed for contact, caching locally: $e');
      }
    }

    // Always persist to local cache
    final localList = await _loadContactsLocally();
    final updatedList = localList.where((c) => c.id != effectiveId).toList()..add(contact);
    await _cacheContactsLocally(updatedList);
  }

  /// Deletes an emergency contact.
  Future<void> deleteEmergencyContact(String contactId) async {
    final uid = currentUser?.uid;
    if (uid != null) {
      try {
        await _contactsCollection(uid).doc(contactId).delete().timeout(const Duration(seconds: 3));
      } catch (_) {}
    }

    final localList = await _loadContactsLocally();
    final updatedList = localList.where((c) => c.id != contactId).toList();
    await _cacheContactsLocally(updatedList);
  }

  static const MethodChannel _nativeChannel = MethodChannel('com.neurodrive.app/native_service');

  /// Checks whether SMS permission is granted on the device.
  Future<bool> hasSmsPermission() async {
    if (kIsWeb) return false;
    try {
      final res = await _nativeChannel.invokeMethod<bool>('hasSmsPermission');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Proactively requests runtime SMS permission from the operating system.
  Future<bool> requestSmsPermission() async {
    if (kIsWeb) return false;
    try {
      final res = await _nativeChannel.invokeMethod<bool>('requestSmsPermission');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Directly sends automated SMS to configured emergency contact numbers without chooser dialogs.
  Future<bool> sendDirectSmsToContacts({
    required List<EmergencyContact> contacts,
    required String emergencyMessage,
    double? latitude,
    double? longitude,
  }) async {
    if (contacts.isEmpty) return false;

    // Filter valid phone numbers
    final phones = contacts
        .map((c) => c.phone.replaceAll(RegExp(r'[^\d+]'), ''))
        .where((p) => p.isNotEmpty)
        .toList();

    if (phones.isEmpty) return false;

    final mapsUrl = (latitude != null && longitude != null)
        ? 'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude'
        : 'Location unavailable';

    final fullMessage = '🚨 EMERGENCY SOS from NeuroDrive: $emergencyMessage\nLive Location: $mapsUrl';

    // 1. Attempt Native Direct Background SMS dispatch (Zero chooser, 100% automated)
    bool directSmsSent = false;
    for (final phone in phones) {
      try {
        final res = await _nativeChannel.invokeMethod<bool>('sendDirectSms', {
          'phone': phone,
          'message': fullMessage,
        });
        if (res == true) {
          directSmsSent = true;
          debugPrint('[EmergencyService] Automated background SMS dispatched directly to $phone');
        }
      } catch (nativeErr) {
        debugPrint('[EmergencyService] Native direct SMS notice for $phone: $nativeErr');
      }
    }

    if (directSmsSent) {
      return true;
    }

    // 2. Fallback: Target device default SMS app directly without any chooser (NEVER show WhatsApp)
    final primaryContact = contacts.firstWhere(
      (c) => c.isPrimary && c.phone.replaceAll(RegExp(r'[^\d+]'), '').isNotEmpty,
      orElse: () => contacts.first,
    );
    final primaryPhone = primaryContact.phone.replaceAll(RegExp(r'[^\d+]'), '');

    try {
      final res = await _nativeChannel.invokeMethod<bool>('openDefaultSmsApp', {
        'phone': primaryPhone,
        'message': fullMessage,
      });
      if (res == true) return true;
    } catch (_) {}

    // Fallback to smsto: URI which strictly targets SMS app, NOT generic messaging apps
    try {
      final smstoUri = Uri(
        scheme: 'smsto',
        path: primaryPhone,
        queryParameters: {'body': fullMessage},
      );
      if (await canLaunchUrl(smstoUri)) {
        return await launchUrl(smstoUri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[EmergencyService] smsto launch error: $e');
    }

    return false;
  }


  // ==========================================
  // SOS EVENT DISPATCH & FIREBASE RECORDING
  // ==========================================

  CollectionReference<Map<String, dynamic>> _sosEventsCollection(String uid) {
    return _firestore.collection('users').doc(uid).collection('sos_events');
  }

  /// Streams past SOS events for the authenticated user.
  Stream<List<SosEvent>> getSosEventsStream() {
    final uid = currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _sosEventsCollection(uid)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => SosEvent.fromFirestore(doc)).toList();
    });
  }

  /// Main SOS Trigger Workflow
  /// 1. Prevents duplicate concurrent calls
  /// 2. Retrieves real device GPS coordinates with timeout & permission handling
  /// 3. Builds Google Maps location link from real coordinates
  /// 4. Dispatches to secure backend alert delivery service
  /// 5. Records event in user's private Cloud Firestore `users/{uid}/sos_events`
  Future<SosResult> triggerEmergencySos({
    String emergencyMessage = 'Urgent: I need emergency assistance while driving.',
    Position? preloadedPosition,
    bool directSmsDelivered = false,
    List<String> directDeliveredTo = const [],
  }) async {
    if (_isSosInProgress) {
      throw Exception("An SOS alert dispatch is already in progress. Please wait.");
    }

    _isSosInProgress = true;
    try {
      final user = currentUser;
      final uid = user?.uid ?? 'guest_driver';
      final driverName = (user?.displayName != null && user!.displayName!.trim().isNotEmpty)
          ? user.displayName!.trim()
          : (user?.email ?? 'NeuroDrive Driver');

      // 1. Fetch real emergency contacts
      final contacts = await getEmergencyContacts();

      // 2. Obtain real GPS location
      Position? position = preloadedPosition;
      String? locationError;
      if (position == null) {
        try {
          final hasPermission = await _locationService.handlePermissions();
          if (!hasPermission) {
            locationError = "Location permission denied. GPS coordinates unavailable.";
          } else {
            // High-priority 8s timeout to ensure prompt emergency dispatch
            position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
                timeLimit: Duration(seconds: 8),
              ),
            );
          }
        } on TimeoutException {
          locationError = "Location request timed out. Proceeding with last known coordinates.";
          try {
            position = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        } catch (e) {
          locationError = "GPS error: $e";
        }
      }

      // Generate real Google Maps URL
      final String mapsUrl;
      if (position != null) {
        mapsUrl = 'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}';
      } else {
        mapsUrl = 'Location unavailable (${locationError ?? "GPS offline"})';
      }

      final now = DateTime.now();

      // 3. Dispatch to secure backend alert delivery service
      String deliveryStatus = 'RECORDED_ONLY';
      String deliveryProvider = 'none';
      String deliveryMessage = 'SOS event recorded in cloud.';
      List<String> deliveredTo = [];
      List<String> deliveryErrors = [];

      if (contacts.isEmpty && !directSmsDelivered) {
        deliveryStatus = 'CONFIG_REQUIRED';
        deliveryMessage = 'No emergency contacts configured. Please add contacts in Settings.';
        deliveryErrors.add("No emergency contacts configured for user.");
      } else {
        // Attempt delivery via backend candidates
        final payload = {
          'uid': uid,
          'driver_name': driverName,
          'emergency_message': emergencyMessage,
          'latitude': position?.latitude,
          'longitude': position?.longitude,
          'maps_url': mapsUrl,
          'timestamp': now.toIso8601String(),
          'contacts': contacts.map((c) => {
            'name': c.name,
            'phone': c.phone,
            'relationship': c.relationship,
          }).toList(),
        };

        bool dispatched = false;
        final baseUrls = AiSafetyService.candidateBaseUrls;

        for (final base in baseUrls) {
          try {
            final endpoint = Uri.parse('$base/api/emergency/sos-alert');
            final response = await _client.post(
              endpoint,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 2));

            if (response.statusCode == 200) {
              final decoded = jsonDecode(response.body) as Map<String, dynamic>;
              deliveryStatus = (decoded['status'] ?? 'RECORDED_ONLY').toString();
              deliveryProvider = (decoded['delivery_provider'] ?? 'none').toString();
              deliveryMessage = (decoded['message'] ?? '').toString();
              if (decoded['delivered_to'] is List) {
                deliveredTo = List<String>.from(decoded['delivered_to']);
              }
              if (decoded['errors'] is List) {
                deliveryErrors = List<String>.from(decoded['errors']);
              }
              dispatched = true;
              break;
            } else {
              deliveryErrors.add("Server returned HTTP ${response.statusCode} at $base");
            }
          } catch (e) {
            deliveryErrors.add("Backend error at $base: $e");
            // Try next candidate URL
            continue;
          }
        }

        if (directSmsDelivered) {
          deliveryStatus = 'DELIVERED';
          deliveryProvider = 'Automated Background SMS';
          deliveryMessage = 'Automated emergency SMS dispatched to emergency contacts with live GPS coordinates.';
          if (directDeliveredTo.isNotEmpty) {
            deliveredTo = directDeliveredTo;
          } else {
            deliveredTo = contacts.map((c) => '${c.name} (${c.phone})').toList();
          }
        } else if (!dispatched && contacts.isNotEmpty) {
          deliveryStatus = 'DELIVERY_FAILED';
          deliveryMessage = 'Unable to reach backend alert delivery service. SMS fallback available.';
        }
      }

      // 4. Save Event Record in Firestore (`users/{uid}/sos_events`)
      DocumentReference<Map<String, dynamic>>? eventDoc;
      if (user != null) {
        try {
          eventDoc = await _sosEventsCollection(user.uid).add({
            'uid': user.uid,
            'driverName': driverName,
            'timestamp': Timestamp.fromDate(now),
            'latitude': position?.latitude,
            'longitude': position?.longitude,
            'mapsUrl': mapsUrl,
            'status': deliveryStatus,
            'deliveryProvider': deliveryProvider,
            'contactsTargeted': contacts.length,
            'deliveredTo': deliveredTo,
            'errorMessage': deliveryErrors.isNotEmpty ? deliveryErrors.join('; ') : null,
            'createdAt': FieldValue.serverTimestamp(),
            'emergencyMessage': emergencyMessage,
          }).timeout(const Duration(seconds: 3));
        } catch (e) {
          debugPrint('Firestore save failed for SOS event: $e');
        }
      }

      return SosResult(
        success: deliveryStatus == 'DELIVERED',
        status: deliveryStatus,
        message: deliveryMessage,
        eventId: eventDoc?.id,
        mapsUrl: mapsUrl,
        latitude: position?.latitude,
        longitude: position?.longitude,
        deliveryProvider: deliveryProvider,
        contactsTargeted: contacts.length,
        deliveredTo: deliveredTo,
        errors: deliveryErrors,
      );
    } finally {
      _isSosInProgress = false;
    }
  }

  void dispose() {
    _client.close();
  }
}
