import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/alert_model.dart';
import 'safety_engine.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  // Cooldown tracking
  DateTime? _lastWarningTime;
  DateTime? _lastCriticalTime;
  
  static const int _warningCooldownSeconds = 30; // Don't spam warnings
  static const int _criticalCooldownSeconds = 10; // Critical is more urgent

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
    
    // Request permission on Android 13+
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> handleSafetyStatus(SafetyStatus status) async {
    // Only process actionable alerts
    if (status.riskLevel == RiskLevel.warning) {
      final now = DateTime.now();
      if (_lastWarningTime == null || now.difference(_lastWarningTime!).inSeconds > _warningCooldownSeconds) {
        _lastWarningTime = now;
        await _showNotification('Collision Warning', status.message, false);
        await _saveAlertHistory(status);
      }
    } else if (status.riskLevel == RiskLevel.critical) {
      final now = DateTime.now();
      if (_lastCriticalTime == null || now.difference(_lastCriticalTime!).inSeconds > _criticalCooldownSeconds) {
        _lastCriticalTime = now;
        await _showNotification('CRITICAL COLLISION ALERT', status.message, true);
        await _saveAlertHistory(status);
      }
    }
  }

  Future<void> _showNotification(String title, String body, bool isCritical) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      isCritical ? 'critical_alerts' : 'warning_alerts',
      isCritical ? 'Critical Alerts' : 'Warning Alerts',
      importance: isCritical ? Importance.max : Importance.high,
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

  Future<void> _saveAlertHistory(SafetyStatus status) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return; // Don't save if not logged in

      final prefs = await SharedPreferences.getInstance();
      final alertsStr = prefs.getStringList('neurodrive_alerts_$uid') ?? [];
      
      final newAlert = AlertModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestamp: DateTime.now(),
        riskLevel: status.riskLevel.toString(),
        message: status.message,
        source: 'System', // Currently system ego physics
      );

      alertsStr.add(json.encode(newAlert.toJson()));
      await prefs.setStringList('neurodrive_alerts_$uid', alertsStr);
    } catch (e) {
      // Ignore save error, don't crash
    }
  }

  void resetCooldowns() {
    _lastWarningTime = null;
    _lastCriticalTime = null;
  }
}
