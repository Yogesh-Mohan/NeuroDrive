import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/alert_model.dart';
import 'ai_safety_service.dart';

/// Standard priority levels for safety alerts
enum AlertPriorityLevel {
  critical,
  high,
  medium,
  low,
}

/// A classified and prioritized safety alert containing ranking, deterministic explanation,
/// and AI enhancement summary.
class PrioritizedAlert {
  final AlertModel alert;
  final AlertPriorityLevel priority;
  final int priorityScore; // 0 - 100 numeric score
  final String priorityReason;
  final String audioVoicePrompt;
  final bool isAiEnhanced;
  final String? aiRecommendation;

  const PrioritizedAlert({
    required this.alert,
    required this.priority,
    required this.priorityScore,
    required this.priorityReason,
    required this.audioVoicePrompt,
    this.isAiEnhanced = false,
    this.aiRecommendation,
  });

  String get priorityLabel {
    switch (priority) {
      case AlertPriorityLevel.critical:
        return 'Critical';
      case AlertPriorityLevel.high:
        return 'High';
      case AlertPriorityLevel.medium:
        return 'Medium';
      case AlertPriorityLevel.low:
        return 'Low';
    }
  }

  Map<String, dynamic> toMap() {
    return {
      'alertId': alert.id,
      'alertType': alert.alertType,
      'priority': priorityLabel,
      'priorityScore': priorityScore,
      'priorityReason': priorityReason,
      'audioVoicePrompt': audioVoicePrompt,
      'isAiEnhanced': isAiEnhanced,
      'aiRecommendation': aiRecommendation,
      'ttc': alert.ttc,
      'distance': alert.distance,
      'relativeSpeed': alert.relativeSpeed,
    };
  }
}

/// Result of prioritizing a batch of alerts
class AlertPrioritizationResult {
  final List<PrioritizedAlert> prioritizedAlerts;
  final PrioritizedAlert? topAlert;
  final bool isAiAssisted;
  final String summaryExplanation;

  const AlertPrioritizationResult({
    required this.prioritizedAlerts,
    this.topAlert,
    required this.isAiAssisted,
    required this.summaryExplanation,
  });
}

/// Service that coordinates deterministic safety rules with AI assistance
/// to prioritize alerts, select the most urgent threat, prevent spam,
/// and produce driver audio prompts.
class AlertPriorityAssistant {
  static final AlertPriorityAssistant _instance = AlertPriorityAssistant._internal();
  factory AlertPriorityAssistant({http.Client? client, String? customBaseUrl}) {
    if (client != null || customBaseUrl != null) {
      _instance._client = client ?? http.Client();
      if (customBaseUrl != null) _instance._baseUrl = customBaseUrl;
    }
    return _instance;
  }

  AlertPriorityAssistant._internal()
      : _client = http.Client(),
        _baseUrl = AiSafetyService.defaultBaseUrl;

  http.Client _client;
  String _baseUrl;

  // Track recently voiced alert hashes to prevent duplicate interruptions
  final Map<String, DateTime> _recentVoicePrompts = {};
  static const Duration _promptCooldown = Duration(seconds: 8);

  /// Prioritizes a single alert deterministically.
  /// Deterministic safety rules are absolute and cannot be downgraded by AI.
  PrioritizedAlert evaluateSingleAlert(AlertModel alert) {
    int score = 0;
    final List<String> reasons = [];
    AlertPriorityLevel level = AlertPriorityLevel.low;
    String voicePrompt = '';

    final sev = alert.severity.toLowerCase();
    final ttc = alert.ttc;
    final dist = alert.distance;
    final speed = alert.relativeSpeed;

    // Rule 1: Evaluate Time-to-Collision (TTC) - the highest deterministic safety indicator
    if (ttc != null && ttc > 0 && !ttc.isNaN && !ttc.isInfinite) {
      if (ttc <= 2.5) {
        score += 55;
        level = AlertPriorityLevel.critical;
        reasons.add('Imminent impact TTC (${ttc.toStringAsFixed(1)}s <= 2.5s)');
        voicePrompt = 'Critical hazard! Brake now.';
      } else if (ttc <= 5.0) {
        score += 35;
        if (level != AlertPriorityLevel.critical) level = AlertPriorityLevel.high;
        reasons.add('Short TTC detected (${ttc.toStringAsFixed(1)}s <= 5.0s)');
        voicePrompt = 'Warning: Vehicle approaching rapidly. Slow down.';
      } else if (ttc <= 10.0) {
        score += 20;
        if (level == AlertPriorityLevel.low) level = AlertPriorityLevel.medium;
        reasons.add('Moderate TTC (${ttc.toStringAsFixed(1)}s)');
        voicePrompt = 'Caution: Maintain safe following distance.';
      } else {
        score += 5;
        reasons.add('Normal headway TTC (${ttc.toStringAsFixed(1)}s)');
        voicePrompt = 'Traffic alert ahead.';
      }
    } else {
      reasons.add('No reliable TTC data');
    }

    // Rule 2: Evaluate Obstacle Distance
    if (dist != null && dist > 0 && !dist.isNaN) {
      if (dist < 10.0) {
        score += 25;
        if (level != AlertPriorityLevel.critical) level = AlertPriorityLevel.critical;
        reasons.add('Severe close proximity (<10m)');
      } else if (dist < 30.0) {
        score += 15;
        if (level == AlertPriorityLevel.low) level = AlertPriorityLevel.high;
        reasons.add('Close proximity (<30m)');
      } else if (dist < 60.0) {
        score += 5;
        reasons.add('Vehicle detected at ${dist.toStringAsFixed(0)}m');
      }
    }

    // Rule 3: Evaluate Relative Closing Speed
    if (speed != null && speed > 0 && !speed.isNaN) {
      if (speed >= 50.0) {
        score += 15;
        reasons.add('High closing speed (${speed.toStringAsFixed(0)} km/h)');
      } else if (speed >= 20.0) {
        score += 10;
        reasons.add('Moderate closing speed (${speed.toStringAsFixed(0)} km/h)');
      }
    }

    // Rule 4: Evaluate Base Severity classification
    if (sev == 'critical') {
      score += 25;
      level = AlertPriorityLevel.critical;
      if (voicePrompt.isEmpty) voicePrompt = 'Immediate collision alert. Take action.';
    } else if (sev == 'warning') {
      score += 15;
      if (level == AlertPriorityLevel.low) level = AlertPriorityLevel.high;
      if (voicePrompt.isEmpty) voicePrompt = 'Collision risk warning. Be vigilant.';
    } else if (sev == 'caution') {
      score += 5;
      if (level == AlertPriorityLevel.low) level = AlertPriorityLevel.medium;
      if (voicePrompt.isEmpty) voicePrompt = 'Caution ahead.';
    }

    // Cap score to 100
    score = score.clamp(0, 100);

    // Finalize default prompt if still empty
    if (voicePrompt.isEmpty) {
      voicePrompt = alert.message.isNotEmpty ? alert.message : 'Notice: Safety alert.';
    }

    final reasonStr = reasons.join('; ');

    return PrioritizedAlert(
      alert: alert,
      priority: level,
      priorityScore: score,
      priorityReason: reasonStr,
      audioVoicePrompt: voicePrompt,
      isAiEnhanced: false,
    );
  }

  /// Prioritizes a list of incoming alerts:
  /// 1. Evaluates all alerts deterministically.
  /// 2. Sorts descending by priority score and timestamp.
  /// 3. If multiple alerts exist and AI service is available, enriches with contextual AI explanation
  ///    without ever overriding critical deterministic safety rules.
  /// 4. Provides fallback behavior seamlessly if AI backend is offline.
  Future<AlertPrioritizationResult> prioritizeAlerts(
    List<AlertModel> alerts, {
    bool requestAiEnhancement = true,
  }) async {
    if (alerts.isEmpty) {
      return const AlertPrioritizationResult(
        prioritizedAlerts: [],
        topAlert: null,
        isAiAssisted: false,
        summaryExplanation: 'No active alerts.',
      );
    }

    // 1. Run Deterministic Prioritization for each alert
    final List<PrioritizedAlert> prioritizedList = alerts.map(evaluateSingleAlert).toList();

    // Sort: Highest priority score first. Tie breaker: lowest valid TTC, then most recent timestamp.
    prioritizedList.sort((a, b) {
      final scoreCompare = b.priorityScore.compareTo(a.priorityScore);
      if (scoreCompare != 0) return scoreCompare;

      final aTtc = a.alert.ttc ?? 999.0;
      final bTtc = b.alert.ttc ?? 999.0;
      final ttcCompare = aTtc.compareTo(bTtc);
      if (ttcCompare != 0) return ttcCompare;

      return b.alert.timestamp.compareTo(a.alert.timestamp);
    });

    final topAlert = prioritizedList.first;
    bool aiAssisted = false;
    String summary = 'Prioritized based on deterministic physical metrics (${topAlert.priorityLabel} priority).';

    // 2. Optional AI Enhancement via Backend if multiple or complex alerts exist
    if (requestAiEnhancement && alerts.isNotEmpty) {
      try {
        final aiResult = await _requestAiPrioritization(prioritizedList);
        if (aiResult != null) {
          aiAssisted = true;
          summary = aiResult;
        }
      } catch (e) {
        debugPrint('AI Prioritization fallback to deterministic rules: $e');
        // Fallback is purely deterministic and fully safe
      }
    }

    return AlertPrioritizationResult(
      prioritizedAlerts: prioritizedList,
      topAlert: topAlert,
      isAiAssisted: aiAssisted,
      summaryExplanation: summary,
    );
  }

  /// Checks if a voice prompt should be delivered to the driver,
  /// suppressing rapid repeat prompts for the same alert type/threat.
  bool shouldDeliverVoicePrompt(PrioritizedAlert prioritizedAlert, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final key = '${prioritizedAlert.alert.alertType}_${prioritizedAlert.priority}';

    // Critical alerts always punch through if at least 2 seconds passed
    if (prioritizedAlert.priority == AlertPriorityLevel.critical) {
      final lastPrompt = _recentVoicePrompts[key];
      if (lastPrompt == null || currentTime.difference(lastPrompt).inSeconds >= 2) {
        _recentVoicePrompts[key] = currentTime;
        return true;
      }
      return false;
    }

    // High and medium alerts adhere to the full cooldown window
    final lastPrompt = _recentVoicePrompts[key];
    if (lastPrompt == null || currentTime.difference(lastPrompt) >= _promptCooldown) {
      _recentVoicePrompts[key] = currentTime;
      return true;
    }

    return false;
  }

  /// Calls backend AI prioritization endpoint if available
  Future<String?> _requestAiPrioritization(List<PrioritizedAlert> list) async {
    final candidateUrls = [
      _baseUrl,
      ...AiSafetyService.candidateBaseUrls.where((u) => u != _baseUrl),
    ];
    final payload = {
      'alert_count': list.length,
      'alerts': list.map((p) => p.toMap()).toList(),
    };

    for (final url in candidateUrls) {
      try {
        final uri = Uri.parse('$url/api/ai-alert-priority');
        final response = await _client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          if (decoded['success'] == true) {
            return decoded['summary_recommendation']?.toString();
          }
        }
      } catch (_) {
        // Continue to next candidate URL or fallback silently
      }
    }
    return null;
  }

  /// Resets voice prompt cooldown state
  void resetCooldowns() {
    _recentVoicePrompts.clear();
  }
}
