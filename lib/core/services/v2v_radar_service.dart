import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/v2v_telemetry.dart';
import '../models/alert_model.dart';
import 'alert_service.dart';

enum V2VConnectionMode {
  cloudFirestore,
  firebaseRealtime,
  localEsp32,
  simulation,
}

class V2VRadarService {
  static final V2VRadarService _instance = V2VRadarService._internal();
  factory V2VRadarService() => _instance;
  V2VRadarService._internal();

  final FlutterTts _tts = FlutterTts();
  final _telemetryController = StreamController<V2VTelemetry>.broadcast();
  Stream<V2VTelemetry> get telemetryStream => _telemetryController.stream;

  V2VTelemetry _latestTelemetry = V2VTelemetry.initial();
  V2VTelemetry get latestTelemetry => _latestTelemetry;

  V2VConnectionMode _currentMode = V2VConnectionMode.firebaseRealtime;
  V2VConnectionMode get currentMode => _currentMode;

  StreamSubscription<DocumentSnapshot>? _firestoreSubscription;
  StreamSubscription<DatabaseEvent>? _rtdbSubscription;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _pollingTimer;
  Timer? _simulationTimer;
  DateTime? _lastAlertSpokenTime;
  DateTime? _lastProximityAlertSavedTime;

  // Proximity alert tracking
  int _proximityAlertCount = 0;
  int get proximityAlertCount => _proximityAlertCount;
  final _alertCountController = StreamController<int>.broadcast();
  Stream<int> get alertCountStream => _alertCountController.stream;

  final List<AlertModel> _proximityAlerts = [];
  List<AlertModel> get proximityAlerts => List.unmodifiable(_proximityAlerts);

  String _localUrl = 'http://192.168.4.1/';
  String _firebaseNode = 'live_telemetry/car_01';
  final String _firestoreDoc = 'car_01';

  // Debug Diagnostics
  String _lastDebugLog = 'Starting...';
  String get lastDebugLog => _lastDebugLog;
  String? _workingEndpoint;
  String? get workingEndpoint => _workingEndpoint;
  String? _lastRawPayload;
  String? get lastRawPayload => _lastRawPayload;

  String get localUrl => _localUrl;
  String get firebaseNode => _firebaseNode;
  String get firestoreDoc => _firestoreDoc;

  bool _isInitialized = false;

  void initialize({V2VConnectionMode initialMode = V2VConnectionMode.firebaseRealtime}) {
    if (!_isInitialized) {
      _isInitialized = true;
      _initTts();
      setConnectionMode(initialMode);
    }
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.5);
    } catch (e) {
      debugPrint('[V2VRadarService] TTS initialization: $e');
    }
  }

  void setConnectionMode(V2VConnectionMode mode, {String? customUrl, String? customFirebaseNode}) {
    _currentMode = mode;
    if (customUrl != null && customUrl.isNotEmpty) {
      _localUrl = customUrl.trim();
      if (!_localUrl.startsWith('http://') && !_localUrl.startsWith('https://')) {
        _localUrl = 'http://$_localUrl';
      }
    }
    if (customFirebaseNode != null && customFirebaseNode.isNotEmpty) {
      _firebaseNode = customFirebaseNode.trim();
    }

    _stopAllSources();
    _workingEndpoint = null;

    switch (mode) {
      case V2VConnectionMode.cloudFirestore:
        _startFirestoreListener();
        break;
      case V2VConnectionMode.firebaseRealtime:
        _startFirebaseListener();
        break;
      case V2VConnectionMode.localEsp32:
        _startLocalEsp32Link();
        break;
      case V2VConnectionMode.simulation:
        _startSimulation();
        break;
    }
  }

  void _stopAllSources() {
    _firestoreSubscription?.cancel();
    _firestoreSubscription = null;
    _rtdbSubscription?.cancel();
    _rtdbSubscription = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _wsChannel?.sink.close();
    _wsChannel = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }

  // 1. Cloud Firestore Real-time Stream (Already configured in project!)
  void _startFirestoreListener() {
    _lastDebugLog = 'Listening to Cloud Firestore: v2v_telemetry/$_firestoreDoc';
    try {
      _firestoreSubscription = FirebaseFirestore.instance
          .collection('v2v_telemetry')
          .doc(_firestoreDoc)
          .snapshots()
          .listen((docSnapshot) {
        if (docSnapshot.exists && docSnapshot.data() != null) {
          final data = docSnapshot.data()!;
          final telemetry = V2VTelemetry.fromMap(data);
          _lastDebugLog = 'Connected to Firestore (dist: ${telemetry.distanceCm}cm)';
          _publish(telemetry);
        } else {
          _lastDebugLog = 'Doc v2v_telemetry/$_firestoreDoc is empty. Tap "Seed Data" to create.';
          _publish(V2VTelemetry(
            vehicleId: 'CAR_01',
            distanceCm: 0.0,
            distanceMeters: 0.0,
            status: 'EMPTY DOC',
            isOnline: false,
            timestamp: DateTime.now(),
          ));
        }
      }, onError: (err) {
        _lastDebugLog = 'Firestore stream error: $err';
      });
    } catch (e) {
      _lastDebugLog = 'Firestore init error: $e';
    }
  }

  /// Instant creation/seeding of Firestore document from App
  Future<void> seedFirestoreData({double distanceCm = 14.1}) async {
    try {
      _lastDebugLog = 'Seeding Firestore document...';
      await FirebaseFirestore.instance.collection('v2v_telemetry').doc(_firestoreDoc).set({
        'vehicle_id': 'CAR_01',
        'distance_cm': distanceCm,
        'distance_m': distanceCm / 100.0,
        'speed_kmh': 32.0,
        'closing_speed_kmh': 4.5,
        'status': distanceCm < 8.0 ? 'CRITICAL' : (distanceCm < 15.0 ? 'CAUTION' : 'SAFE'),
        'is_online': true,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _lastDebugLog = 'Successfully seeded Firestore v2v_telemetry/$_firestoreDoc!';
    } catch (e) {
      _lastDebugLog = 'Failed to seed Firestore: $e';
    }
  }

  // 2. Direct Local ESP32 Link
  void _startLocalEsp32Link() {
    _lastDebugLog = 'Connecting to $_localUrl ...';
    _tryConnectWebSocket();

    _pollingTimer = Timer.periodic(const Duration(milliseconds: 150), (timer) async {
      if (_wsChannel != null && _wsSubscription != null) {
        return;
      }
      await _pollBestEndpoint();
    });
  }

  void _tryConnectWebSocket() {
    try {
      final host = _localUrl
          .replaceFirst('http://', '')
          .replaceFirst('https://', '')
          .split('/')
          .first;
      final wsUri = Uri.parse('ws://$host/ws');

      _wsChannel = WebSocketChannel.connect(wsUri);
      _wsSubscription = _wsChannel!.stream.listen((message) {
        _lastDebugLog = 'Connected via WebSocket (ws://$host/ws)';
        _handleIncomingPayload(message.toString(), sourceEndpoint: 'ws://$host/ws');
      }, onError: (err) {
        _lastDebugLog = 'WS unavailable, polling HTTP endpoints';
        _wsSubscription?.cancel();
        _wsSubscription = null;
        _wsChannel = null;
      }, onDone: () {
        _wsSubscription = null;
        _wsChannel = null;
      });
    } catch (e) {
      _lastDebugLog = 'WS error: $e';
    }
  }

  Future<void> _pollBestEndpoint() async {
    final baseUrl = _localUrl.endsWith('/') ? _localUrl : '$_localUrl/';

    if (_workingEndpoint != null) {
      final success = await _fetchFromUrl(_workingEndpoint!);
      if (success) return;
      _workingEndpoint = null;
    }

    final candidateEndpoints = [
      '${baseUrl}distance',
      '${baseUrl}data',
      '${baseUrl}read',
      '${baseUrl}radar',
      '${baseUrl}get',
      baseUrl,
    ];

    for (final endpoint in candidateEndpoints) {
      final success = await _fetchFromUrl(endpoint);
      if (success) {
        _workingEndpoint = endpoint;
        _lastDebugLog = 'Connected to $endpoint';
        return;
      }
    }

    _lastDebugLog = 'Unreachable: Make sure Mobile Data is OFF and connected to ESP32 WiFi';
    _publish(V2VTelemetry(
      vehicleId: 'ESP32 (192.168.4.1)',
      distanceCm: _latestTelemetry.distanceCm,
      distanceMeters: _latestTelemetry.distanceMeters,
      speedKmh: _latestTelemetry.speedKmh,
      status: 'SEARCHING...',
      isOnline: false,
      timestamp: DateTime.now(),
    ));
  }

  Future<bool> _fetchFromUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http.get(uri).timeout(const Duration(milliseconds: 400));
      if (response.statusCode == 200 && response.body.trim().isNotEmpty) {
        return _handleIncomingPayload(response.body, sourceEndpoint: url);
      }
    } catch (_) {}
    return false;
  }

  bool _handleIncomingPayload(String rawBody, {String? sourceEndpoint}) {
    _lastRawPayload = rawBody.length > 120 ? '${rawBody.substring(0, 120)}...' : rawBody;

    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        final telemetry = V2VTelemetry.fromMap(decoded);
        _publish(telemetry);
        return true;
      }
    } catch (_) {}

    final numRegex = RegExp(r'(?:DIST|DISTANCE)?[:=\s]*([0-9]+\.?[0-9]*)', caseSensitive: false);
    final numMatch = numRegex.firstMatch(rawBody);
    if (numMatch != null && !rawBody.contains('<html') && !rawBody.contains('<!DOCTYPE')) {
      final val = double.tryParse(numMatch.group(1) ?? '');
      if (val != null && val >= 0 && val <= 400) {
        _publish(V2VTelemetry(
          vehicleId: 'ESP32_LEAD_01',
          distanceCm: val,
          distanceMeters: val / 100.0,
          status: val < 8.0 ? 'CRITICAL' : (val < 15.0 ? 'CAUTION' : 'SAFE'),
          isOnline: true,
          timestamp: DateTime.now(),
        ));
        return true;
      }
    }

    if (rawBody.contains('<html') || rawBody.contains('<!DOCTYPE') || rawBody.contains('<div')) {
      final patterns = [
        RegExp(r'id=["''](?:distance|dist|live_dist|live-distance)["''][^>]*>([0-9.]+)<', caseSensitive: false),
        RegExp(r'LIVE DETECTED DISTANCE[^0-9]*([0-9.]+)', caseSensitive: false),
        RegExp(r'([0-9.]+)\s*cm', caseSensitive: false),
      ];

      for (final p in patterns) {
        final match = p.firstMatch(rawBody);
        if (match != null && match.group(1) != null) {
          final val = double.tryParse(match.group(1)!);
          if (val != null && val > 0 && val < 400) {
            _publish(V2VTelemetry(
              vehicleId: 'ESP32_LEAD_01',
              distanceCm: val,
              distanceMeters: val / 100.0,
              status: val < 8.0 ? 'CRITICAL' : (val < 15.0 ? 'CAUTION' : 'SAFE'),
              isOnline: true,
              timestamp: DateTime.now(),
            ));
            return true;
          }
        }
      }
    }

    return false;
  }

  // 3. Firebase Realtime Database Listener
  void _startFirebaseListener() {
    _lastDebugLog = 'Listening to Realtime Database: $_firebaseNode';
    try {
      final rtdb = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://neurodrive-be33a-default-rtdb.firebaseio.com',
      );
      final dbRef = rtdb.ref(_firebaseNode);
      _rtdbSubscription = dbRef.onValue.listen((DatabaseEvent event) {
        if (event.snapshot.value != null) {
          try {
            final val = event.snapshot.value;
            Map<dynamic, dynamic> data;
            if (val is Map) {
              data = Map<dynamic, dynamic>.from(val);
            } else if (val is num) {
              data = {'distance_cm': val, 'is_online': true};
            } else {
              data = {'distance_cm': double.tryParse(val.toString()) ?? 0.0, 'is_online': true};
            }
            final telemetry = V2VTelemetry.fromMap(data);
            _lastDebugLog = 'RTDB Connected (dist: ${telemetry.distanceCm}cm)';
            _publish(telemetry);
          } catch (e) {
            _lastDebugLog = 'RTDB parse error: $e';
          }
        } else {
          _lastDebugLog = 'RTDB node $_firebaseNode is empty';
        }
      }, onError: (err) {
        _lastDebugLog = 'RTDB error: $err';
      });
    } catch (e) {
      _lastDebugLog = 'Firebase RTDB init failed: $e';
    }
  }

  /// Push test distance to Realtime Database
  Future<void> pushTestDistanceToRtdb({double distanceCm = 14.1}) async {
    try {
      final rtdb = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://neurodrive-be33a-default-rtdb.firebaseio.com',
      );
      await rtdb.ref(_firebaseNode).update({
        'vehicle_id': 'CAR_01',
        'distance_cm': distanceCm,
        'speed_kmh': 35.0,
        'closing_speed_kmh': 4.2,
        'status': distanceCm < 8.0 ? 'CRITICAL' : (distanceCm < 15.0 ? 'CAUTION' : 'SAFE'),
        'is_online': true,
      });
      _lastDebugLog = 'Successfully updated RTDB distance: $distanceCm cm';
    } catch (e) {
      _lastDebugLog = 'RTDB update error: $e';
    }
  }

  // 4. Realtime Simulation
  void _startSimulation() {
    _lastDebugLog = 'Running Simulation Demo';
    double simAngle = 0.0;
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      simAngle += 0.08;
      final distCm = 13.5 + 8.0 * math.sin(simAngle);
      final closingSpeed = (math.cos(simAngle) * 15.0).abs();

      final telemetry = V2VTelemetry(
        vehicleId: 'ESP32_SIMULATOR',
        distanceCm: double.parse(distCm.toStringAsFixed(1)),
        distanceMeters: double.parse((distCm / 100.0).toStringAsFixed(3)),
        speedKmh: 34.0,
        closingSpeedKmh: double.parse(closingSpeed.toStringAsFixed(1)),
        status: distCm < 8.0 ? 'CRITICAL' : (distCm < 15.0 ? 'CAUTION' : 'SAFE'),
        isOnline: true,
        timestamp: DateTime.now(),
        angleDeg: 90.0,
      );

      _publish(telemetry);
    });
  }

  void _publish(V2VTelemetry telemetry) {
    _latestTelemetry = telemetry;
    _telemetryController.add(telemetry);

    // Trigger proximity alert when status is CRITICAL (person/vehicle too close - red on radar)
    if (telemetry.status == 'CRITICAL') {
      final now = DateTime.now();

      // TTS voice warning (every 4 seconds)
      if (_lastAlertSpokenTime == null || now.difference(_lastAlertSpokenTime!).inSeconds >= 4) {
        _lastAlertSpokenTime = now;
        _tts.speak('Warning! Vehicle ahead too close!');
      }

      // Save proximity alert (throttle: one alert per 10 seconds to avoid spam)
      if (_lastProximityAlertSavedTime == null || now.difference(_lastProximityAlertSavedTime!).inSeconds >= 10) {
        _lastProximityAlertSavedTime = now;
        _saveProximityAlert(telemetry);
      }
    }
  }

  /// Create and store a proximity alert when radar detects critical closeness
  void _saveProximityAlert(V2VTelemetry telemetry) {
    final now = DateTime.now();
    final alertId = 'radar_prox_${now.millisecondsSinceEpoch}';

    final alert = AlertModel(
      id: alertId,
      alertType: 'PROXIMITY_ALERT',
      severity: 'critical',
      message: 'Radar proximity alert! Object detected at ${telemetry.distanceCm.toStringAsFixed(1)} cm — too close!',
      source: 'V2VRadar',
      distance: telemetry.distanceMeters,
      relativeSpeed: telemetry.closingSpeedKmh,
      timestamp: now,
      createdAt: now,
      isSynced: false,
    );

    // Increment alert count
    _proximityAlertCount++;
    _alertCountController.add(_proximityAlertCount);

    // Store in local list
    _proximityAlerts.add(alert);

    // Save to AlertService (Firestore + SQLite + SharedPrefs)
    try {
      AlertService().saveDirectAlert(alert);
      debugPrint('[V2VRadar] Proximity alert #$_proximityAlertCount saved: ${telemetry.distanceCm} cm');
    } catch (e) {
      debugPrint('[V2VRadar] Failed to save proximity alert: $e');
    }
  }

  /// Reset alert count (e.g. when starting new session)
  void resetAlertCount() {
    _proximityAlertCount = 0;
    _proximityAlerts.clear();
    _alertCountController.add(0);
  }

  void dispose() {
    _stopAllSources();
    _telemetryController.close();
    _alertCountController.close();
  }
}
