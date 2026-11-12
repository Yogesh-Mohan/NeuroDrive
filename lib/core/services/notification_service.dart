import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'safety_engine.dart';
import 'alert_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService({AlertService? alertService}) {
    if (alertService != null) {
      _instance._customAlertService = alertService;
    }
    return _instance;
  }
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  AlertService? _customAlertService;
  AlertService get _alertService => _customAlertService ??= AlertService();

  // Cooldown tracking
  DateTime? _lastCautionTime;
  DateTime? _lastWarningTime;
  DateTime? _lastCriticalTime;
  
  static const int _cautionCooldownSeconds = 45; // Subtle cautions
  static const int _warningCooldownSeconds = 30; // Don't spam warnings
  static const int _criticalCooldownSeconds = 10; // Critical is more urgent

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const LinuxInitializationSettings initializationSettingsLinux =
        LinuxInitializationSettings(defaultActionName: 'Open notification');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
      linux: initializationSettingsLinux,
    );

    try {
      await _flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
      );

      // Request permission on Android 13+
      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('[NotificationService] initialize warning: $e');
    }
  }

  /// Evaluates safety status, triggers real-time notification, and asynchronously logs alert to Firestore
  Future<void> handleSafetyStatus(
    SafetyStatus status, {
    Position? currentPosition,
    String? tripId,
    double? distanceMeters,
    double? relativeSpeedKmh,
  }) async {
    final now = DateTime.now();
    final effectiveDist = distanceMeters ?? status.distanceMeters;
    final effectiveSpeed = relativeSpeedKmh ?? status.closingSpeedKmh;

    if (status.riskLevel == RiskLevel.caution) {
      if (_lastCautionTime == null || now.difference(_lastCautionTime!).inSeconds > _cautionCooldownSeconds) {
        _lastCautionTime = now;
        // Non-intrusive notification for caution
        await _showNotification('Safety Caution', status.message, Importance.defaultImportance);
        // Persist alert asynchronously without delaying warnings
        _alertService.saveSafetyAlert(
          status: status,
          tripId: tripId,
          latitude: currentPosition?.latitude,
          longitude: currentPosition?.longitude,
          distanceMeters: effectiveDist,
          relativeSpeedKmh: effectiveSpeed,
        );
      }
    } else if (status.riskLevel == RiskLevel.warning) {
      if (_lastWarningTime == null || now.difference(_lastWarningTime!).inSeconds > _warningCooldownSeconds) {
        _lastWarningTime = now;
        await _showNotification('Collision Warning', status.message, Importance.high);
        _alertService.saveSafetyAlert(
          status: status,
          tripId: tripId,
          latitude: currentPosition?.latitude,
          longitude: currentPosition?.longitude,
          distanceMeters: effectiveDist,
          relativeSpeedKmh: effectiveSpeed,
        );
      }
    } else if (status.riskLevel == RiskLevel.critical) {
      if (_lastCriticalTime == null || now.difference(_lastCriticalTime!).inSeconds > _criticalCooldownSeconds) {
        _lastCriticalTime = now;
        await _showNotification('CRITICAL COLLISION ALERT', status.message, Importance.max);
        _alertService.saveSafetyAlert(
          status: status,
          tripId: tripId,
          latitude: currentPosition?.latitude,
          longitude: currentPosition?.longitude,
          distanceMeters: effectiveDist,
          relativeSpeedKmh: effectiveSpeed,
        );
      }
    }
  }

  Future<void> _showNotification(String title, String body, Importance importance) async {
    final bool isCritical = importance == Importance.max;
    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      isCritical ? 'critical_alerts' : 'warning_alerts',
      isCritical ? 'Critical Alerts' : 'Warning Alerts',
      importance: importance,
      priority: isCritical ? Priority.max : Priority.high,
      enableVibration: true,
      playSound: true,
      color: const Color(0xFF00D2FF),
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _flutterLocalNotificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
    );
  }

  /// Triggers a high-priority local emergency notification on device
  Future<void> showEmergencySosNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'emergency_sos_channel',
      'Emergency SOS Alerts',
      channelDescription: 'High priority alerts triggered during SOS emergency events',
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: true,
      playSound: true,
      color: Color(0xFFFF5252),
      fullScreenIntent: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    await _flutterLocalNotificationsPlugin.show(
      id: 99999, // Distinct ID for emergency notification
      title: title,
      body: body,
      notificationDetails: platformDetails,
    );
  }

  /// Triggers a road hazard / pothole advance notification visible on lock screen and HUD
  Future<void> showRoadDamageAlertNotification({
    required String title,
    required String body,
    required String severity,
  }) async {
    final isHigh = severity.toLowerCase() == 'high';
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'road_hazard_channel',
      'Road Damage Alerts',
      channelDescription: 'Advance warnings for upcoming potholes and road damage',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      color: isHigh ? const Color(0xFFFF3366) : const Color(0xFFFF9900),
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _flutterLocalNotificationsPlugin.show(
        id: 88888,
        title: title,
        body: body,
        notificationDetails: platformDetails,
      );
    } catch (e) {
      debugPrint('[NotificationService] Hazard alert notification notice: $e');
    }
  }

  void resetCooldowns() {
    _lastCautionTime = null;
    _lastWarningTime = null;
    _lastCriticalTime = null;
  }
}
