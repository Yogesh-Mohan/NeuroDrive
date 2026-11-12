import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_model.dart';
import '../models/alert_model.dart';

/// Structured AI Trip Safety Report returned by Gemini Flash or the Backend API.
class AiSafetyReport {
  final bool success;
  final String model;
  final String tripSummary;
  final List<String> recordedSafetyEvents;
  final Map<String, dynamic> dataSupportedObservations;
  final String practicalRecommendations;
  final String riskLevel;
  final List<String> warnings;
  final double? inferenceTimeSec;

  const AiSafetyReport({
    required this.success,
    required this.model,
    required this.tripSummary,
    required this.recordedSafetyEvents,
    required this.dataSupportedObservations,
    required this.practicalRecommendations,
    required this.riskLevel,
    this.warnings = const [],
    this.inferenceTimeSec,
  });

  factory AiSafetyReport.fromJson(
    Map<String, dynamic> json, {
    String? defaultModel,
    double? inferenceTimeSec,
  }) {
    // If nested in 'report', extract it; otherwise treat json itself as report
    final reportMap = json['report'] is Map<String, dynamic>
        ? json['report'] as Map<String, dynamic>
        : json;
    final observationsMap = reportMap['data_supported_observations'] as Map<String, dynamic>? ?? {};
    final eventsRaw = (reportMap['recorded_safety_events'] ?? json['recorded_safety_events']) as List<dynamic>? ?? [];
    final warningsRaw = (json['warnings'] ?? reportMap['warnings']) as List<dynamic>? ?? [];

    return AiSafetyReport(
      success: json['success'] as bool? ?? true,
      model: (json['model'] ?? reportMap['model'] ?? defaultModel ?? 'gemini-1.5-flash').toString(),
      tripSummary: (reportMap['trip_summary'] ?? '').toString(),
      recordedSafetyEvents: eventsRaw.map((e) => e.toString()).toList(),
      dataSupportedObservations: observationsMap,
      practicalRecommendations: (reportMap['practical_recommendations'] ?? '').toString(),
      riskLevel: (reportMap['risk_level'] ?? observationsMap['risk_level'] ?? 'low').toString(),
      warnings: warningsRaw.map((w) => w.toString()).toList(),
      inferenceTimeSec: (json['inference_time_sec'] as num?)?.toDouble() ?? inferenceTimeSec,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'model': model,
      'report': {
        'trip_summary': tripSummary,
        'recorded_safety_events': recordedSafetyEvents,
        'data_supported_observations': dataSupportedObservations,
        'practical_recommendations': practicalRecommendations,
        'risk_level': riskLevel,
      },
      'warnings': warnings,
      if (inferenceTimeSec != null) 'inference_time_sec': inferenceTimeSec,
    };
  }
}

/// Service powering AI Trip Safety Analysis directly via Google Gemini Flash API
/// or via legacy Python backend, with local deterministic fallback when offline.
class AiSafetyService {
  static const String defaultGeminiModel = 'gemini-1.5-flash';
  static const String envGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static String? configuredGeminiApiKey;
  static String? configuredGeminiModel;

  // Candidate backend base URLs to try in order:
  // 1. Custom URL or environment variable (if specified)
  // 2. http://127.0.0.1:8000 (Physical Android device via 'adb reverse' or desktop/web)
  // 3. http://172.1.25.104:8000 (Local Wi-Fi IP for direct network access)
  // 4. http://10.0.2.2:8000 (Android Emulator virtual router host)
  static List<String> get candidateBaseUrls {
    const envUrl = String.fromEnvironment('AI_BACKEND_URL');
    if (envUrl.isNotEmpty) return [envUrl];

    if (!kIsWeb && Platform.isAndroid) {
      return [
        'http://127.0.0.1:8000',
        'http://10.153.86.81:8000',
        'http://10.0.2.2:8000',
      ];
    }
    return ['http://127.0.0.1:8000'];
  }

  static String get defaultBaseUrl => candidateBaseUrls.first;

  /// Loads saved Gemini API key from local persistent preferences
  static Future<String?> getStoredGeminiApiKey() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 300));
      return prefs.getString('gemini_api_key');
    } catch (_) {
      return null;
    }
  }

  /// Persists Gemini API key to local persistent preferences
  static Future<void> saveGeminiApiKey(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(milliseconds: 300));
      await prefs.setString('gemini_api_key', key.trim());
      configuredGeminiApiKey = key.trim();
    } catch (_) {}
  }

  /// Static helper to resolve effective Gemini API key across sources
  static Future<String?> getEffectiveApiKeyStatic() async {
    if (configuredGeminiApiKey != null && configuredGeminiApiKey!.isNotEmpty) {
      return configuredGeminiApiKey;
    }
    if (envGeminiApiKey.isNotEmpty) {
      return envGeminiApiKey;
    }
    return await getStoredGeminiApiKey();
  }

  final String baseUrl;
  final String? customBaseUrl;
  final String? geminiApiKey;
  final String modelName;
  final bool preferGemini;
  final bool enableLocalFallback;
  final http.Client _client;

  AiSafetyService({
    this.customBaseUrl,
    this.geminiApiKey,
    String? modelName,
    bool? preferGemini,
    this.enableLocalFallback = true,
    http.Client? client,
  })  : baseUrl = customBaseUrl ?? defaultBaseUrl,
        modelName = modelName ?? configuredGeminiModel ?? defaultGeminiModel,
        preferGemini = preferGemini ?? (customBaseUrl == null),
        _client = client ?? http.Client();

  /// Resolves the API key checking constructor parameter, static config,
  /// dart-define environment variable, and SharedPreferences.
  Future<String?> getEffectiveApiKey() async {
    if (geminiApiKey != null && geminiApiKey!.isNotEmpty) {
      return geminiApiKey;
    }
    return await getEffectiveApiKeyStatic();
  }

  /// Sends verified trip telemetry to Gemini Flash API directly,
  /// with automatic fallback to local backend or offline deterministic analysis.
  Future<AiSafetyReport> generateTripSafetyReport({
    required TripModel trip,
    List<AlertModel>? alerts,
    String languageMode = 'tanglish',
  }) async {
    // Filter alerts to those that occurred during this specific trip
    final tripAlerts = (alerts ?? []).where((a) {
      return a.timestamp.isAfter(trip.startTime.subtract(const Duration(minutes: 1))) &&
          a.timestamp.isBefore(trip.endTime.add(const Duration(minutes: 1)));
    }).toList();

    // 1. If preferGemini is false (e.g. customBaseUrl was passed for tests/backend), call legacy backend directly
    if (!preferGemini) {
      return await _callLegacyBackend(trip: trip, tripAlerts: tripAlerts);
    }

    // 2. Direct Gemini Flash Path
    final effectiveKey = await getEffectiveApiKey();
    if (effectiveKey != null && effectiveKey.isNotEmpty) {
      try {
        final geminiReport = await _callGeminiFlash(
          trip: trip,
          tripAlerts: tripAlerts,
          apiKey: effectiveKey,
          languageMode: languageMode,
        );
        return geminiReport;
      } catch (e) {
        debugPrint('[AiSafetyService] Gemini Flash API failed: $e');
        if (customBaseUrl != null) {
          return await _callLegacyBackend(trip: trip, tripAlerts: tripAlerts);
        }
        if (enableLocalFallback) {
          return _generateLocalSafetyReport(
            trip: trip,
            tripAlerts: tripAlerts,
            languageMode: languageMode,
          );
        }
        rethrow;
      }
    }

    // 3. If Gemini preferred but no key configured: generate local report or try backend
    if (enableLocalFallback) {
      return _generateLocalSafetyReport(
        trip: trip,
        tripAlerts: tripAlerts,
        languageMode: languageMode,
      );
    }

    return await _callLegacyBackend(trip: trip, tripAlerts: tripAlerts);
  }

  /// Direct REST call to Google Gemini Flash API (`generateContent`)
  Future<AiSafetyReport> _callGeminiFlash({
    required TripModel trip,
    required List<AlertModel> tripAlerts,
    required String apiKey,
    String languageMode = 'tanglish',
  }) async {
    final startTime = DateTime.now();
    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelName:generateContent?key=$apiKey',
    );

    final prompt = _buildGeminiSafetyPrompt(
      trip: trip,
      tripAlerts: tripAlerts,
      languageMode: languageMode,
    );

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'response_mime_type': 'application/json',
        'temperature': 0.2,
      }
    };

    final response = await _client
        .post(
          endpoint,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 15));

    final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000.0;

    if (response.statusCode == 200) {
      final decodedResponse = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = decodedResponse['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('Gemini returned empty candidates list.');
      }

      final content = candidates[0]['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        throw Exception('Gemini candidate had no text parts.');
      }

      final rawText = (parts[0]['text'] ?? '').toString();
      final reportMap = _cleanAndParseJson(rawText);

      return AiSafetyReport.fromJson(
        reportMap,
        defaultModel: modelName,
        inferenceTimeSec: elapsed,
      );
    } else {
      final err = response.body;
      throw Exception('Gemini API Error (HTTP ${response.statusCode}): $err');
    }
  }

  /// Builds strictly grounded telemetry prompt with Thanglish / English support and Few-Shot exemplars
  String _buildGeminiSafetyPrompt({
    required TripModel trip,
    required List<AlertModel> tripAlerts,
    String languageMode = 'tanglish',
  }) {
    final distKm = (trip.distance / 1000.0).toStringAsFixed(2);
    final durMin = (trip.duration / 60.0).toStringAsFixed(1);
    final avgSpeed = trip.avgSpeed.toStringAsFixed(1);

    // Deep Telemetry Metrics
    final startHour = trip.startTime.hour;
    final timeOfDay = startHour >= 6 && startHour < 12
        ? 'Morning Rush / Commute'
        : (startHour >= 12 && startHour < 17
            ? 'Daylight Afternoon'
            : (startHour >= 17 && startHour < 21
                ? 'Evening Peak & Dusk'
                : 'Night-time Driving (Low Visibility & Headlight Glare Risk)'));

    final durationCategory = trip.duration < 900
        ? 'Short sprint (< 15 mins)'
        : (trip.duration <= 3600 ? 'Medium transit (15-60 mins)' : 'Extended highway cruise (> 60 mins)');
    final speedProfile = trip.avgSpeed < 25.0
        ? 'Dense stop-and-go city traffic'
        : (trip.avgSpeed <= 60.0 ? 'Suburban cruising' : 'High-speed expressway / highway');

    // Mathematical Safety Score computation
    int safetyScore = 100;
    for (final a in tripAlerts) {
      final sev = a.severity.toLowerCase();
      if (sev == 'critical') {
        safetyScore -= 25;
      } else if (sev == 'warning') {
        safetyScore -= 10;
      } else {
        safetyScore -= 5;
      }
    }
    if (trip.avgSpeed > 80.0) safetyScore -= 10;
    if (safetyScore < 15) safetyScore = 15;

    final alertSummaries = tripAlerts.map((a) {
      final details = <String>[];
      if (a.distance != null) details.add('${a.distance!.toStringAsFixed(0)}m');
      if (a.ttc != null) details.add('TTC: ${a.ttc!.toStringAsFixed(1)}s');
      final extra = details.isNotEmpty ? ' (${details.join(', ')})' : '';
      return '[${a.severity.toUpperCase()}] ${a.message}$extra';
    }).toList();

    final isTanglish = languageMode.toLowerCase() != 'english';

    return '''
You are an expert AI Vehicle Safety Analyst for the NeuroDrive smart driver assistance system.
Analyze the following recorded vehicle trip telemetry and generate a strictly factual, structured driving safety report.

Observed Trip Facts:
- Distance: $distKm km
- Duration: $durMin minutes ($durationCategory)
- Average Speed: $avgSpeed km/h ($speedProfile)
- Time of Day: $timeOfDay
- Evaluated Safety Score: $safetyScore / 100
- Safety Alerts Count: ${tripAlerts.length}
- Alert Details: ${alertSummaries.isEmpty ? 'None recorded' : alertSummaries.join('; ')}

PROMPTING METHOD: FEW-SHOT TELEMETRY SAFETY ANALYSIS
Study these exemplars demonstrating how to deeply analyze telemetry without generic canned responses:

[EXEMPLAR 1 - Urban Commute with Forward Hazard]
Facts: 12.4 km in 28 mins, Avg Speed 26.5 km/h, 2 warnings (TTC 2.1s, 15m), Night-time.
Output JSON:
{
  "trip_summary": "Intha night-time trip-la car 12.40 km distance-ah 28.0 minutes-la stop-and-go traffic-la 26.5 km/h avg speed-la cover pannirukku. Drive-la 2 safety alerts record aagirukku, athula forward collision risk TTC 2.1s-ku koraiva vanthurukku.",
  "recorded_safety_events": ["[WARNING] Forward collision warning (15m, TTC: 2.1s)"],
  "data_supported_observations": {
    "distance_km": 12.4,
    "duration_minutes": 28.0,
    "average_speed_kmh": 26.5,
    "total_alerts": 2,
    "safety_score": 75,
    "telemetry_completeness": "Complete",
    "risk_level": "medium"
  },
  "practical_recommendations": "1. Night driving-la visibility koraiva irukkurathala front vehicle kitta minimum 3-4 seconds headway gap maintain pannunga. 2. Sudden deceleration spot pannumbothu early-aa brake pedal touch panni tailgating avoid pannunga.",
  "risk_level": "medium",
  "warnings": []
}

[EXEMPLAR 2 - Clean Highway Cruise]
Facts: 45.0 km in 40 mins, Avg Speed 67.5 km/h, 0 alerts, Daytime.
Output JSON:
{
  "trip_summary": "Car 45.00 km highway distance-ah 40.0 minutes-la smooth-aa 67.5 km/h avg speed-la cover pannirukku. Safety alerts edhum illai, consistent cruising speed maintain aagirukku.",
  "recorded_safety_events": [],
  "data_supported_observations": {
    "distance_km": 45.0,
    "duration_minutes": 40.0,
    "average_speed_kmh": 67.5,
    "total_alerts": 0,
    "safety_score": 100,
    "telemetry_completeness": "Complete",
    "risk_level": "low"
  },
  "practical_recommendations": "Super driving! Clean record maintain pannirukkeenga. Long highway journey-la speed limit adhere panni, 2 hours-ku orumurai short break edunga.",
  "risk_level": "low",
  "warnings": []
}

Strict Rules:
1. Grounding: Do NOT hallucinate or claim unrecorded events (no imaginary crashes, fatalities, fake weather, or pedestrian collisions not in the data).
2. Risk Level: Determine risk level strictly as "low", "medium", or "high":
   - "high": Any critical severity alerts, TTC < 2.5s, or total alerts >= 3.
   - "medium": 1-2 caution or warning alerts without critical emergencies.
   - "low": 0 alerts, safe normal cruising.
3. Language:
   ${isTanglish
      ? "Write 'trip_summary' and 'practical_recommendations' in clear, natural, friendly Thanglish (Tamil words written using the English alphabet, very popular in Tamil Nadu, e.g. 'Intha trip-la car 15.4 km travel pannirukku. Munnala pora vehicle kitta safe following distance maintain pannunga.'). Keep it easy to understand for Tamil drivers."
      : "Write 'trip_summary' and 'practical_recommendations' in clear, concise professional English."}

Output MUST be ONLY valid JSON matching this exact structure:
{
  "trip_summary": "Concise factual summary of trip telemetry and driving conditions",
  "recorded_safety_events": ${jsonEncode(alertSummaries)},
  "data_supported_observations": {
    "distance_km": ${double.parse(distKm)},
    "duration_minutes": ${double.parse(durMin)},
    "average_speed_kmh": ${double.parse(avgSpeed)},
    "total_alerts": ${tripAlerts.length},
    "safety_score": $safetyScore,
    "telemetry_completeness": "Complete",
    "risk_level": "low|medium|high"
  },
  "practical_recommendations": "Actionable driving tips based strictly on the telemetry facts",
  "risk_level": "low|medium|high",
  "warnings": []
}
''';
  }

  /// Parses JSON and strips optional markdown code wrappers
  Map<String, dynamic> _cleanAndParseJson(String rawText) {
    var text = rawText.trim();
    if (text.startsWith('```json')) {
      text = text.substring(7);
    } else if (text.startsWith('```')) {
      text = text.substring(3);
    }
    if (text.endsWith('```')) {
      text = text.substring(0, text.length - 3);
    }
    text = text.trim();
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// 100% Offline / Local Deterministic Safety Analyst Engine
  AiSafetyReport generateLocalDeterministicReport({
    required TripModel trip,
    required List<AlertModel> tripAlerts,
    String languageMode = 'tanglish',
  }) {
    return _generateLocalSafetyReport(
      trip: trip,
      tripAlerts: tripAlerts,
      languageMode: languageMode,
    );
  }

  AiSafetyReport _generateLocalSafetyReport({
    required TripModel trip,
    required List<AlertModel> tripAlerts,
    String languageMode = 'tanglish',
  }) {
    final distKm = double.parse((trip.distance / 1000.0).toStringAsFixed(2));
    final durMin = double.parse((trip.duration / 60.0).toStringAsFixed(1));
    final avgSpeed = double.parse(trip.avgSpeed.toStringAsFixed(1));
    final alertCount = tripAlerts.length;

    final hasCritical = tripAlerts.any((a) => a.severity.toLowerCase() == 'critical');
    final hasWarning = tripAlerts.any((a) => a.severity.toLowerCase() == 'warning');

    String riskLevel = 'low';
    if (hasCritical || alertCount >= 3) {
      riskLevel = 'high';
    } else if (hasWarning || alertCount >= 1) {
      riskLevel = 'medium';
    }

    // Mathematical Safety Score computation
    int safetyScore = 100;
    for (final a in tripAlerts) {
      final sev = a.severity.toLowerCase();
      if (sev == 'critical') {
        safetyScore -= 25;
      } else if (sev == 'warning') {
        safetyScore -= 10;
      } else {
        safetyScore -= 5;
      }
    }
    if (avgSpeed > 80.0) safetyScore -= 10;
    if (safetyScore < 15) safetyScore = 15;

    final startHour = trip.startTime.hour;
    final isNight = startHour < 6 || startHour >= 19;
    final isLongTrip = trip.duration > 3600;

    final alertSummaries = tripAlerts.map((a) {
      final details = <String>[];
      if (a.distance != null) details.add('${a.distance!.toStringAsFixed(0)}m');
      if (a.ttc != null) details.add('TTC: ${a.ttc!.toStringAsFixed(1)}s');
      final extra = details.isNotEmpty ? ' (${details.join(', ')})' : '';
      return '[${a.severity.toUpperCase()}] ${a.message}$extra';
    }).toList();

    final isTanglish = languageMode.toLowerCase() != 'english';

    String tripSummary;
    String practicalRecommendations;

    if (isTanglish) {
      final recList = <String>[];

      // 1. Dynamic Speed & Pacing Advisory
      if (avgSpeed > 80.0) {
        recList.add('1. [Speed Control]: High-speed highway transit ($avgSpeed km/h) observe aagirukku. Excessive speed-la stopping distance quadruples. Speed limit-ai adhere panni 80-90 km/h kulla maintain pannunga.');
      } else if (avgSpeed > 50.0) {
        recList.add('1. [Highway Pacing]: Highway cruising speed ($avgSpeed km/h) steady-aa maintain aagirukku. Multi-lane highway-la lane change pannum bothu minimum 3 seconds munnala turn indicators podunga.');
      } else if (avgSpeed > 25.0) {
        recList.add('1. [City Pacing]: Safe city driving habits maintain aaguthu. Intersections mattrum pedestrian crossings kitta smooth deceleration follow pannunga.');
      } else {
        recList.add('1. [Traffic Management]: Low-speed stop-and-go congestion ($avgSpeed km/h) observe aagirukku. Clutch riding avoid pannunga, gentle throttle inputs moolam fuel efficiency-ai improve pannalam.');
      }

      // 2. Dynamic Headway & Hazard Avoidance Advisory
      if (hasCritical) {
        recList.add('2. [Collision Buffer]: Critical collision warning record aagirukku! Munnala pora vehicle kitta minimum 3-second gap maintain pannunga. Speed control panni brake alert-ku quick-aa react pannunga. Sudden acceleration avoid pannunga.');
      } else if (alertCount > 0) {
        recList.add('2. [Headway Distance]: Traffic-la safe following distance maintain pannunga. Sudden braking avoid pannina safe-aa irukkum. Forward scanning 100 meters munnala maintain pannunga.');
      } else {
        recList.add('2. [Hazard Awareness]: Super driving! Clean record maintain pannirukkeenga. Idhey maadhiri safe distance and speed limit follow pannunga.');
      }

      // 3. Dynamic Environmental & Time-of-Day Advisory
      if (startHour >= 22 || startHour < 5) {
        recList.add('3. [Midnight Advisory]: Midnight / late-night drive ($startHour:00 hrs). Drowsiness risk high-aa irukkurathala fresh air circulation maintain pannunga, opposite vehicles kitta headlights-ai low beam switch pannunga.');
      } else if (startHour >= 5 && startHour < 7) {
        recList.add('3. [Dawn Advisory]: Early morning dawn drive. Low sun angle glare and morning mist visibility-ai baadhikkum. Clean windscreen mattrum sun visors use pannunga.');
      } else if (startHour >= 7 && startHour < 10) {
        recList.add('3. [Morning Commute]: Morning peak traffic envelope. School zones mattrum bus stops kitta extra buffer space maintain pannunga.');
      } else if (startHour >= 12 && startHour < 16) {
        recList.add('3. [Midday Advisory]: Afternoon high road surface temperature-naala tyre heat buildup aagum. Cold tyre pressure-ai periodically monitor pannunga.');
      } else if (startHour >= 17 && startHour < 20) {
        recList.add('3. [Dusk Advisory]: Evening sunset transition time. Ambient visibility drop aagum bothu low-beam headlights-ai early-aa switch on pannunga.');
      } else {
        recList.add('3. [Night Advisory]: Night driving-la lighting koraiva irunthuchu. Oncoming high beam glare avoid panna road-oda left white line-ai visual anchor-aa use pannunga.');
      }

      // 4. Dynamic Endurance & Trip Care Advisory
      if (isLongTrip || distKm >= 60.0) {
        recList.add('4. [Endurance]: 1 hour-ku mela continuous drive pannirukkeenga, regular rest breaks edunga (every 90-120 km or 2 hours).');
      } else if (distKm < 3.0) {
        recList.add('4. [Short Trip Care]: Short commute ($distKm km). Cold-start engine wear reduce panna periodic battery health check ensure pannunga.');
      } else {
        recList.add('4. [Efficiency]: Balanced commuter distance ($distKm km). Smooth throttle pacing mattrum engine coasting moolam 15% extra mileage save pannalam.');
      }

      practicalRecommendations = recList.join('\n');

      if (alertCount == 0) {
        final timeNote = isNight ? ' Night time drive-la road glare and visibility careful-aa handle pannirukkeenga.' : '';
        tripSummary = 'Car $distKm km distance-ah $durMin minutes-la $avgSpeed km/h avg speed-la smoothly cover pannirukku. Safety alerts edhum illai.$timeNote';
      } else {
        final sevDetail = hasCritical ? 'Critical collision alert TTC < 2.5s vandhathu' : '$alertCount proximity warning(s) vandhadhu';
        final nightNote = isNight ? ' Night driving-la lighting koraiva irunthuchu.' : '';
        tripSummary = 'Car $distKm km distance-ah $durMin minutes-la travel pannirukku (avg speed $avgSpeed km/h). Drive-la $alertCount safety alert(s) record aagirukku ($sevDetail).$nightNote';
      }
    } else {
      final recList = <String>[];

      if (avgSpeed > 80.0) {
        recList.add('1. [Speed Control]: High-speed cruise ($avgSpeed km/h) recorded. Braking distance increases quadratically with velocity; regulate cruising speed within 80-90 km/h.');
      } else if (avgSpeed > 50.0) {
        recList.add('1. [Highway Pacing]: Stable highway pacing ($avgSpeed km/h). Observe designated multi-lane etiquette and indicate turns 3 seconds prior to lane changes.');
      } else {
        recList.add('1. [Urban Pacing]: Regulated city driving ($avgSpeed km/h). Maintain progressive braking pressure approaching intersections and pedestrian crossings.');
      }

      if (hasCritical) {
        recList.add('2. [Headway Buffer]: Critical proximity events detected. Maintain a minimum 3-second following gap and decelerate promptly upon forward alerts.');
      } else if (alertCount > 0) {
        recList.add('2. [Following Distance]: Maintain vigilant following distance and observe speed thresholds in congested traffic.');
      } else {
        recList.add('2. [Headway Awareness]: Excellent driving behavior. Continue maintaining safe headway distance and speed adherence.');
      }

      if (startHour >= 22 || startHour < 6) {
        recList.add('3. [Night Advisory]: Night-time transit ($startHour:00 hrs). Dip high beams for oncoming vehicles and maintain fresh cabin airflow to prevent drowsiness.');
      } else if (startHour >= 6 && startHour < 10) {
        recList.add('3. [Morning Commute]: Morning commuter hours. Watch for school zones and unpredictable two-wheeler filtering.');
      } else {
        recList.add('3. [Environmental]: Standard daytime lighting. Scan 12-15 seconds ahead along your forward trajectory.');
      }

      if (isLongTrip || distKm >= 60.0) {
        recList.add('4. [Endurance]: Extended continuous driving detected; schedule rest breaks to prevent fatigue.');
      } else {
        recList.add('4. [Fuel Economy]: Balanced trip distance ($distKm km). Progressive throttle application yields optimal fuel efficiency.');
      }

      practicalRecommendations = recList.join('\n');

      if (alertCount == 0) {
        tripSummary = 'The vehicle completed $distKm km in $durMin minutes at an average speed of $avgSpeed km/h with zero safety alerts.';
      } else {
        tripSummary = 'The vehicle traveled $distKm km in $durMin minutes at an average speed of $avgSpeed km/h, with $alertCount safety alert(s) recorded.';
      }
    }

    return AiSafetyReport(
      success: true,
      model: 'neuro-local-analyst',
      tripSummary: tripSummary,
      recordedSafetyEvents: alertSummaries,
      dataSupportedObservations: {
        'distance_km': distKm,
        'duration_minutes': durMin,
        'average_speed_kmh': avgSpeed,
        'total_alerts': alertCount,
        'safety_score': safetyScore,
        'telemetry_completeness': 'Complete',
        'risk_level': riskLevel,
      },
      practicalRecommendations: practicalRecommendations,
      riskLevel: riskLevel,
      warnings: const ['Generated with local deterministic engine. Set Gemini API key in settings for Google Gemini 1.5 Flash cloud analysis.'],
      inferenceTimeSec: 0.05,
    );
  }


  /// Sends request to candidate legacy Python backend URLs
  Future<AiSafetyReport> _callLegacyBackend({
    required TripModel trip,
    required List<AlertModel> tripAlerts,
  }) async {
    final Map<String, dynamic> requestPayload = {
      'distance_km': double.parse((trip.distance / 1000.0).toStringAsFixed(2)),
      'duration_minutes': double.parse((trip.duration / 60.0).toStringAsFixed(1)),
      'avg_speed_kmh': double.parse(trip.avgSpeed.toStringAsFixed(1)),
      'alert_count': tripAlerts.length,
      'alerts': tripAlerts.map((a) {
        return {
          'severity': a.severity,
          'message': a.message,
          if (a.distance != null) 'distance': a.distance,
          if (a.ttc != null) 'ttc': a.ttc,
        };
      }).toList(),
    };

    final urlsToTry = [baseUrl, ...candidateBaseUrls.where((u) => u != baseUrl)];
    Exception? lastException;

    for (final url in urlsToTry) {
      final endpoint = Uri.parse('$url/api/ai-trip-safety-report');
      try {
        final response = await _client
            .post(
              endpoint,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode(requestPayload),
            )
            .timeout(const Duration(seconds: 75));

        if (response.statusCode == 200) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          if (decoded['success'] == true) {
            return AiSafetyReport.fromJson(decoded);
          } else {
            throw Exception(decoded['error'] ?? 'API returned failure status.');
          }
        } else if (response.statusCode == 400) {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          throw Exception('Validation Error: ${decoded['error'] ?? response.body}');
        } else if (response.statusCode == 503) {
          throw Exception('AI Model Engine Unavailable: The backend inference service is currently busy or loading.');
        } else {
          throw Exception('Server returned HTTP ${response.statusCode}: ${response.body}');
        }
      } on SocketException catch (e) {
        lastException = Exception('Connection failed: Unable to reach AI Backend at $url. Ensure uvicorn server is running. (${e.message})');
        continue;
      } on TimeoutException {
        lastException = Exception('Request timeout connecting to $url. Please retry.');
        continue;
      } on FormatException {
        throw Exception('Invalid response format: Received unparseable data from backend.');
      } catch (e) {
        if (e is Exception) {
          final msg = e.toString();
          if (msg.contains('Validation Error') || msg.contains('AI Model Engine Unavailable')) {
            rethrow;
          }
        }
        lastException = Exception('Unexpected error communicating with AI Analyst: $e');
      }
    }

    if (lastException != null) throw lastException;
    throw Exception('Unable to reach AI backend server on any candidate URLs: $urlsToTry');
  }

  /// Checks if backend server is online and healthy.
  Future<bool> checkHealth() async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}
