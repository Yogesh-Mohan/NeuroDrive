import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'ai_safety_service.dart';
import 'location_service.dart';

/// Available Prompt Engineering Techniques
enum PromptMethod {
  zeroShot,
  oneShot,
  fewShot,
}

/// Structured response from the NeuroCopilot in-drive assistant.
class AiCopilotAnswer {
  final bool success;
  final String answer;
  final String intent;
  final String audioTts;
  final String? actionableRecommendation;
  final bool isLocalFallback;
  final String promptMethod;
  final String? exemplar;

  const AiCopilotAnswer({
    required this.success,
    required this.answer,
    required this.intent,
    required this.audioTts,
    this.actionableRecommendation,
    this.isLocalFallback = false,
    this.promptMethod = 'few-shot',
    this.exemplar,
  });
}


/// Service orchestrating driver query processing, backend AI inference,
/// local deterministic fallback, and voice TTS audio delivery.
class AiCopilotService {
  static final AiCopilotService _instance = AiCopilotService._internal();
  factory AiCopilotService() => _instance;
  AiCopilotService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  http.Client? customClient;

  Future<void> initTts({String languageMode = 'tanglish'}) async {
    try {
      await _flutterTts.setSpeechRate(0.48); // Natural, clear driver pace
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);
      
      // Select best dialect: en-IN pronounces Tanglish (Tamil written in English) accurately
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        if (languageMode == 'tanglish') {
          await _flutterTts.setLanguage("en-IN");
        } else {
          await _flutterTts.setLanguage("en-US");
        }
      }
    } catch (e) {
      debugPrint('[AiCopilot] TTS init notice: $e');
    }
  }

  Future<void> speak(String text, {String languageMode = 'tanglish'}) async {
    try {
      await initTts(languageMode: languageMode);
      await _flutterTts.stop();
      if (text.isNotEmpty) {
        await _flutterTts.speak(text);
      }
    } catch (e) {
      debugPrint('[AiCopilot] TTS speak error: $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _flutterTts.stop();
    } catch (_) {}
  }

  /// Determines the optimal prompt engineering technique based on the user's intent.
  PromptMethod selectPromptMethod(String query) {
    final q = query.toLowerCase();

    // Few-Shot: Complex driving safety, emergency, hazard, overtaking, turn rules, vehicle maintenance
    if (q.contains('danger') ||
        q.contains('accident') ||
        q.contains('crash') ||
        q.contains('brake') ||
        q.contains('hazard') ||
        q.contains('rain') ||
        q.contains('fog') ||
        q.contains('emergency') ||
        q.contains('overtake') ||
        q.contains('tire') ||
        q.contains('tyre') ||
        q.contains('puncture') ||
        q.contains('night') ||
        q.contains('gap') ||
        q.contains('distance maintain') ||
        q.contains('traffic rule')) {
      return PromptMethod.fewShot;
    }

    // One-Shot: Direct telemetry & vehicle status checks (speed, arrival ETA, location, alerts)
    if (q.contains('speed') ||
        q.contains('fast') ||
        q.contains('slow') ||
        q.contains('where') ||
        q.contains('location') ||
        q.contains('enga') ||
        q.contains('place') ||
        q.contains('map') ||
        q.contains('chennai') ||
        q.contains('eta') ||
        q.contains('reach') ||
        q.contains('time') ||
        q.contains('destination') ||
        q.contains('alert') ||
        q.contains('warning')) {
      return PromptMethod.oneShot;
    }

    // Zero-Shot: Open-ended chit-chat, greetings, identity, driver tips, general questions
    return PromptMethod.zeroShot;
  }

  /// Sends the driver query with current telemetry to the backend or Gemini Flash API,
  /// seamlessly falling back to local deterministic intelligence if offline.
  Future<AiCopilotAnswer> askCopilot({
    required String query,
    String? currentLocationName,
    double? latitude,
    double? longitude,
    String? destinationName,
    double? distanceRemainingKm,
    double? etaMinutes,
    double currentSpeedKmh = 0.0,
    int alertCount = 0,
    List<String> recentAlerts = const [],
    String languageMode = 'tanglish', // 'tanglish' | 'english'
  }) async {
    // If coordinates are missing, fetch from live GPS
    double? lat = latitude;
    double? lng = longitude;
    if (lat == null || lng == null) {
      try {
        final pos = await LocationService().getCurrentLocation();
        lat = pos?.latitude;
        lng = pos?.longitude;
      } catch (_) {}
    }

    // Reverse geocode if location is raw coordinates or unspecified
    String effectiveLocation = currentLocationName ?? '';
    if ((effectiveLocation.isEmpty || effectiveLocation.startsWith('GPS') || effectiveLocation.contains(RegExp(r'\d+\.\d{3,}'))) && lat != null && lng != null) {
      try {
        effectiveLocation = await LocationService().reverseGeocode(lat, lng);
      } catch (_) {
        effectiveLocation = 'Chennai';
      }
    }
    if (effectiveLocation.isEmpty || effectiveLocation == 'Current GPS Location') {
      effectiveLocation = 'Chennai Area';
    }

    final chosenMethod = selectPromptMethod(query);

    final payload = {
      'user_query': query,
      'current_location_name': effectiveLocation,
      'current_latitude': lat,
      'current_longitude': lng,
      'destination_name': destinationName,
      'distance_remaining_km': distanceRemainingKm,
      'eta_minutes': etaMinutes,
      'current_speed_kmh': currentSpeedKmh,
      'alert_count': alertCount,
      'recent_alerts': recentAlerts,
      'language_mode': languageMode,
      'prompt_method': chosenMethod.name,
    };

    final client = customClient ?? http.Client();

    // 1. Direct Google Gemini Flash Copilot Call
    final apiKey = await AiSafetyService.getEffectiveApiKeyStatic();
    if (apiKey != null && apiKey.isNotEmpty) {
      try {
        final geminiAnswer = await _askGeminiCopilot(
          client: client,
          apiKey: apiKey,
          query: query,
          currentLocationName: effectiveLocation,
          latitude: lat,
          longitude: lng,
          destinationName: destinationName,
          distanceRemainingKm: distanceRemainingKm,
          etaMinutes: etaMinutes,
          currentSpeedKmh: currentSpeedKmh,
          alertCount: alertCount,
          recentAlerts: recentAlerts,
          languageMode: languageMode,
          promptMethod: chosenMethod,
        );
        if (geminiAnswer != null) {
          return geminiAnswer;
        }
      } catch (e) {
        debugPrint('[AiCopilot] Gemini direct inference error: $e');
      }
    }

    // 2. Try candidate backend URLs
    for (final base in AiSafetyService.candidateBaseUrls) {
      try {
        final uri = Uri.parse('$base/api/ai-copilot');
        final response = await client
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final answer = AiCopilotAnswer(
            success: data['success'] as bool? ?? true,
            answer: data['answer']?.toString() ?? '',
            intent: data['intent']?.toString() ?? 'general',
            audioTts: data['audio_tts']?.toString() ?? data['answer']?.toString() ?? '',
            actionableRecommendation: data['actionable_recommendation']?.toString(),
            isLocalFallback: false,
            promptMethod: chosenMethod.name,
          );
          return answer;
        }
      } catch (e) {
        debugPrint('[AiCopilot] Backend $base unreachable: $e. Trying fallback/next.');
      }
    }

    // 100% Offline / Local Fallback Engine
    return _generateLocalFallback(
      query: query,
      currentLocationName: effectiveLocation,
      latitude: latitude,
      longitude: longitude,
      destinationName: destinationName,
      distanceRemainingKm: distanceRemainingKm,
      etaMinutes: etaMinutes,
      currentSpeedKmh: currentSpeedKmh,
      alertCount: alertCount,
      recentAlerts: recentAlerts,
      languageMode: languageMode,
      promptMethod: chosenMethod,
    );
  }


  /// High-precision local fallback engine ensuring driver never loses copilot features offline.
  AiCopilotAnswer _generateLocalFallback({
    required String query,
    String? currentLocationName,
    double? latitude,
    double? longitude,
    String? destinationName,
    double? distanceRemainingKm,
    double? etaMinutes,
    double currentSpeedKmh = 0.0,
    int alertCount = 0,
    List<String> recentAlerts = const [],
    String languageMode = 'tanglish',
    PromptMethod promptMethod = PromptMethod.zeroShot,
  }) {
    final q = query.toLowerCase().trim();
    final isTanglish = languageMode.toLowerCase() != 'english';
    
    // Clean human-friendly location string without raw coordinate dumps
    String loc = currentLocationName ?? '';
    if (loc.isEmpty || loc.startsWith('GPS') || loc.contains(RegExp(r'\d+\.\d{3,}'))) {
      loc = 'Chennai Road';
    }
    final speedInt = currentSpeedKmh.round();

    // 1. Greetings (Hi, Hello, Vanakkam)
    if (q.contains('hi') || q.contains('hello') || q.contains('vanakkam') || q.contains('hey') || q.contains('hai')) {
      final ans = isTanglish
          ? 'Vanakkam! Naan unga NeuroCopilot. Ungalukku drive-la eppadi help pannanum? Location, ETA, speed, or driving tips pathi kelunga!'
          : 'Hello! I am NeuroCopilot, your AI driving companion. How can I assist you today?';
      final aud = isTanglish ? 'Vanakkam! Naan unga NeuroCopilot. Eppadi help pannanum?' : 'Hello! How can I assist you today?';
      return AiCopilotAnswer(
        success: true,
        answer: ans,
        intent: 'greeting',
        audioTts: aud,
        actionableRecommendation: 'Focus on the road',
        isLocalFallback: true,
        promptMethod: promptMethod.name,
      );
    }

    // 2. Identity
    if (q.contains('who are you') || q.contains('yar ne') || q.contains('yaaru') || q.contains('name')) {
      final ans = isTanglish
          ? 'Naan unga NeuroCopilot AI! Neenga drive pannumbothu live route, speed, and safety alerts monitor panni guide pannuven.'
          : 'I am NeuroCopilot AI, your in-drive companion monitoring road safety, routes, and alerts.';
      final aud = isTanglish ? 'Naan unga NeuroCopilot AI. Unga in-drive companion.' : 'I am NeuroCopilot, your in-drive assistant.';
      return AiCopilotAnswer(
        success: true,
        answer: ans,
        intent: 'identity',
        audioTts: aud,
        actionableRecommendation: 'AI Companion Active',
        isLocalFallback: true,
        promptMethod: promptMethod.name,
      );
    }

    // 3. Chit-chat (Epdi iruka)
    if (q.contains('how are you') || q.contains('epdi iruka') || q.contains('nallamuka')) {
      final ans = isTanglish
          ? 'Naan romba nalla irukken! Unga telemetry systems ellame perfectly active-aa irukku. Namma safe-aa travel pannalam.'
          : 'I am doing great and vehicle sensors are fully operational!';
      final aud = isTanglish ? 'Naan nalla irukken! Systems perfectly active.' : 'I am doing great!';
      return AiCopilotAnswer(
        success: true,
        answer: ans,
        intent: 'chitchat',
        audioTts: aud,
        actionableRecommendation: 'Systems Normal',
        isLocalFallback: true,
        promptMethod: promptMethod.name,
      );
    }

    // 4. Gratitude
    if (q.contains('thanks') || q.contains('thank you') || q.contains('nandri') || q.contains('super')) {
      final ans = isTanglish
          ? 'Romba nandri! Road mela dhyanam vechi, safe-aa drive pannunga.'
          : "You're very welcome! Keep your eyes on the road and stay safe.";
      final aud = isTanglish ? 'Romba nandri! Safe-aa drive pannunga.' : 'You are welcome!';
      return AiCopilotAnswer(
        success: true,
        answer: ans,
        intent: 'chitchat',
        audioTts: aud,
        actionableRecommendation: 'Stay Alert',
        isLocalFallback: true,
        promptMethod: promptMethod.name,
      );
    }

    // 5. Speed Intent
    if (q.contains('speed') || q.contains('fast') || q.contains('vegama') || q.contains('slow')) {
      final ans = isTanglish
          ? 'Unga current driving speed $speedInt km/h. Speed limit kulla safe-aa maintain pannunga.\n\n💡 One-Shot Example:\nQ: "Speed check?" ➔ A: "Current speed $speedInt km/h is safe for city roads."'
          : 'Your current speed is $speedInt km/h. Please stay within designated speed limits.\n\n💡 One-Shot Example:\nQ: "Speed check?" ➔ A: "Current speed $speedInt km/h is safe for city roads."';
      final aud = isTanglish ? 'Current speed $speedInt km/h.' : 'Speed is $speedInt km/h.';
      return AiCopilotAnswer(
        success: true,
        answer: ans,
        intent: 'speed',
        audioTts: aud,
        actionableRecommendation: 'Maintain safe speed',
        isLocalFallback: true,
        promptMethod: 'one-shot',
        exemplar: 'User: "Current speed check?" ➔ AI: "Current speed $speedInt km/h is within city road limits."',
      );
    }

    // 6. Safety Hazards & Driving Rules (Few-shot context)
    if (q.contains('danger') ||
        q.contains('accident') ||
        q.contains('brake') ||
        q.contains('hazard') ||
        q.contains('rain') ||
        q.contains('fog') ||
        q.contains('tire') ||
        q.contains('tyre') ||
        q.contains('overtake') ||
        q.contains('gap') ||
        q.contains('tip') ||
        q.contains('advice') ||
        q.contains('guide')) {
      final ans = isTanglish
          ? 'Safety advisory: Munnadi pora vehicle kitta minimum 3-seconds safe gap vidunga, turning-la indicator use panna marakathinga. Sudden braking avoid pannunga.\n\n💡 Few-Shot Safety Example:\nQ: "Front car close-aa iruntha enna seiyanum?" ➔ A: "Immediate-aa accelerate release panni 4s gap maintain pannunga."'
          : 'Safety advisory: Maintain a minimum 3-second buffer distance with vehicles ahead and check blind spots before changing lanes.\n\n💡 Few-Shot Safety Example:\nQ: "Vehicle too close ahead?" ➔ A: "Release accelerator and maintain 4-second gap."';
      final aud = isTanglish ? 'Munnadi vehicle kitta minimum 3-seconds gap vidunga.' : 'Maintain 3-second safe distance.';
      return AiCopilotAnswer(
        success: true,
        answer: ans,
        intent: 'safety',
        audioTts: aud,
        actionableRecommendation: 'Follow 3-second rule',
        isLocalFallback: true,
        promptMethod: 'few-shot',
        exemplar: '1. Collision Risk ➔ 4s gap\n2. Heavy Rain ➔ Wipers & low beam 40 km/h\n3. Night Drive ➔ Hazard lights off, headlights low-beam',
      );
    }

    // 7. Location Intent - Speaks human-readable place name, NEVER raw lat/long
    if (q.contains('where') ||
        q.contains('location') ||
        q.contains('enga') ||
        q.contains('place') ||
        q.contains('chennai') ||
        q.contains('map')) {
      final ans = isTanglish
          ? 'Neenga ippo $loc kitta $speedInt km/h speed-la drive panreenga.\n\n💡 One-Shot Example:\nQ: "Naa ippo enga irukan?" ➔ A: "Neenga ippo $loc kitta safe cruising speed-la irukkeenga."'
          : 'You are currently near $loc, traveling at $speedInt km/h.\n\n💡 One-Shot Example:\nQ: "Where am I currently?" ➔ A: "You are currently near $loc at $speedInt km/h."';
      final aud = isTanglish ? 'Neenga ippo $loc kitta irukkeenga.' : 'You are near $loc.';
      return AiCopilotAnswer(
        success: true,
        answer: ans,
        intent: 'location',
        audioTts: aud,
        actionableRecommendation: isTanglish ? 'GPS navigation active-aa irukku.' : 'GPS tracking active.',
        isLocalFallback: true,
        promptMethod: 'one-shot',
        exemplar: 'User: "Naa enga irukan?" ➔ AI: "Neenga ippo $loc kitta $speedInt km/h speed-la travel panreenga."',
      );
    }

    // 8. ETA / Destination Intent
    if (q.contains('eta') ||
        q.contains('reach') ||
        q.contains('time') ||
        q.contains('neram') ||
        q.contains('evlo') ||
        q.contains('destination') ||
        q.contains('distance') ||
        q.contains('seruvom')) {
      if (destinationName != null && destinationName.isNotEmpty) {
        final etaStr = etaMinutes != null ? '${etaMinutes.round()} minutes' : 'Calculating';
        final distStr = distanceRemainingKm != null ? '${distanceRemainingKm.toStringAsFixed(1)} km' : '';
        final ans = isTanglish
            ? '$destinationName reach aaga innum $distStr ($etaStr) aagum.\n\n💡 One-Shot Example:\nQ: "Destination reach aaga evlo neram?" ➔ A: "Destination innum $distStr ($etaStr) aagum."'
            : '$destinationName is $distStr away. Estimated arrival in $etaStr.\n\n💡 One-Shot Example:\nQ: "How long to destination?" ➔ A: "Destination is $distStr away, ETA $etaStr."';
        return AiCopilotAnswer(
          success: true,
          answer: ans,
          intent: 'eta',
          audioTts: isTanglish ? '$destinationName reach aaga innum $distStr aagum.' : ans,
          actionableRecommendation: isTanglish ? 'Safe following distance maintain pannunga.' : 'Maintain steady speed.',
          isLocalFallback: true,
          promptMethod: 'one-shot',
          exemplar: 'User: "ETA evlo neram?" ➔ AI: "$destinationName innum $distStr ($etaStr) aagum."',
        );
      } else {
        final ans = isTanglish
            ? 'Innum destination set pannala. Map-la destination select pannunga.'
            : 'Destination is not set yet. Please select a destination on the map.';
        return AiCopilotAnswer(
          success: true,
          answer: ans,
          intent: 'eta',
          audioTts: ans,
          actionableRecommendation: isTanglish ? 'Select destination on map.' : 'Set destination in map.',
          isLocalFallback: true,
          promptMethod: 'one-shot',
          exemplar: 'User: "ETA?" ➔ AI: "Please select destination on map."',
        );
      }
    }

    // 9. Alerts Intent
    if (q.contains('alert') || q.contains('warning') || q.contains('ethana') || q.contains('how many')) {
      if (alertCount == 0) {
        final ans = isTanglish
            ? 'Ithuvaraikkum entha safety alerts-um illa. Unga driving romba safe-aa irukku!\n\n💡 One-Shot Example:\nQ: "Alerts ethana?" ➔ A: "Zero alerts, drive safe-aa proceed pannunga."'
            : 'Zero safety alerts recorded so far. Excellent driving!\n\n💡 One-Shot Example:\nQ: "Alert count?" ➔ A: "Zero alerts, safe driving record maintained."';
        return AiCopilotAnswer(
          success: true,
          answer: ans,
          intent: 'alerts',
          audioTts: ans,
          actionableRecommendation: isTanglish ? 'Smooth driving continue pannunga.' : 'Keep up the smooth driving.',
          isLocalFallback: true,
          promptMethod: 'one-shot',
          exemplar: 'User: "Alerts ethana?" ➔ AI: "Zero alerts recorded so far."',
        );
      } else {
        final ans = isTanglish
            ? 'Ithuvaraikkum $alertCount safety alerts vanthurukku. Safe buffer maintain pannunga.\n\n💡 One-Shot Example:\nQ: "Alerts ethana?" ➔ A: "$alertCount safety alerts recorded. Munnadi vehicle kitta safe gap vidunga."'
            : 'Total of $alertCount safety alerts recorded so far. Increase following distance.\n\n💡 One-Shot Example:\nQ: "Alert count?" ➔ A: "$alertCount alerts recorded. Increase headway distance."';
        return AiCopilotAnswer(
          success: true,
          answer: ans,
          intent: 'alerts',
          audioTts: isTanglish ? 'Total $alertCount safety alerts record aagirukku.' : 'Total of $alertCount alerts recorded.',
          actionableRecommendation: isTanglish ? 'Munnadi vehicle kitta safe gap vidunga.' : 'Maintain safety buffer.',
          isLocalFallback: true,
          promptMethod: 'one-shot',
          exemplar: 'User: "Alerts ethana?" ➔ AI: "Total $alertCount safety alerts recorded."',
        );
      }
    }

    // 10. Default / Dynamic General Query Response
    final ans = isTanglish
        ? 'Unga kelvikku pathil: Ippo namma $loc kitta $speedInt km/h speed-la drive panrom. $alertCount alerts irukku. Safe-aa concentrate panni drive pannunga!'
        : 'Regarding your question: We are currently near $loc at $speedInt km/h with $alertCount alerts. Stay alert and drive safely!';
    return AiCopilotAnswer(
      success: true,
      answer: ans,
      intent: 'conversational',
      audioTts: isTanglish ? 'Speed $speedInt km/h. Enna thevaiyo kelunga!' : ans,
      actionableRecommendation: isTanglish ? 'Road mela focus veinga.' : 'Eyes on the road.',
      isLocalFallback: true,
      promptMethod: promptMethod.name,
      exemplar: promptMethod == PromptMethod.oneShot
          ? 'User: "Status check?" ➔ AI: "Traveling near $loc at $speedInt km/h safely."'
          : null,
    );
  }

  /// Sends a structured prompt to Google Gemini Flash API using Few-Shot, One-Shot, or Zero-Shot Prompting.
  Future<AiCopilotAnswer?> _askGeminiCopilot({
    required http.Client client,
    required String apiKey,
    required String query,
    String? currentLocationName,
    double? latitude,
    double? longitude,
    String? destinationName,
    double? distanceRemainingKm,
    double? etaMinutes,
    double currentSpeedKmh = 0.0,
    int alertCount = 0,
    List<String> recentAlerts = const [],
    String languageMode = 'tanglish',
    PromptMethod promptMethod = PromptMethod.zeroShot,
  }) async {
    final model = AiSafetyService.configuredGeminiModel ?? AiSafetyService.defaultGeminiModel;
    final endpoint = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
    );

    final isTanglish = languageMode.toLowerCase() != 'english';
    String loc = currentLocationName ?? '';
    if (loc.isEmpty || loc.startsWith('GPS') || loc.contains(RegExp(r'\d+\.\d{3,}'))) {
      loc = 'Chennai Highway';
    }
    final dest = destinationName ?? 'Not specified';
    final distRem = distanceRemainingKm != null ? '${distanceRemainingKm.toStringAsFixed(1)} km' : 'Unknown';
    final eta = etaMinutes != null ? '${etaMinutes.toStringAsFixed(0)} mins' : 'Unknown';

    final String prompt;
    if (promptMethod == PromptMethod.fewShot) {
      prompt = '''
You are NeuroCopilot, an expert in-car AI driving companion for the NeuroDrive application.
The driver asked: "$query"

Current Live Telemetry:
- Current Speed: ${currentSpeedKmh.round()} km/h
- Current Location: $loc
- Destination: $dest
- Distance Remaining: $distRem
- ETA: $eta
- Recent Alerts: $alertCount (${recentAlerts.join(', ')})

PROMPTING METHOD: FEW-SHOT PROMPTING
Study these high-quality exemplar turns carefully:

[EXAMPLE 1 - Forward Collision Risk]
User: "Munnadi pora lorry romba close-aa irukku, enna panrathu?"
Output:
{
  "answer": "Immediate-aa acceleration release panni 4-second gap maintain pannunga. Overtake panna rush pannatheenga.",
  "intent": "safety",
  "audio_tts": "Speed koraichu 4-second gap maintain pannunga.",
  "actionable_recommendation": "Increase following gap"
}

[EXAMPLE 2 - Weather / Night Visibility Hazard]
User: "Mazhai peyyuthu road theriyala, safe speed enna?"
Output:
{
  "answer": "Heavy rain-la wiper high-la vechi, low-beam headlights ON pannunga. Speed-ah 40 km/h kulla korainga. Hazard lights off-la veinga.",
  "intent": "safety",
  "audio_tts": "Headlights ON panni speed 40 km/h kulla maintain pannunga.",
  "actionable_recommendation": "Use low beam & wipers"
}

[EXAMPLE 3 - Chennai Location / Navigation Question]
User: "Namma Chennai-la enga irukkom?"
Output:
{
  "answer": "Neenga ippo $loc kitta ${currentSpeedKmh.round()} km/h speed-la drive panreenga. Route clear-aa irukku.",
  "intent": "location",
  "audio_tts": "Neenga ippo $loc kitta irukkeenga.",
  "actionable_recommendation": "Maintain safe headway"
}

Strict Rules:
1. Driver Safety: Keep answers clear, direct, and non-distracting for someone driving.
2. NEVER mention raw GPS coordinates or latitude/longitude numbers. Always use human-readable places like "$loc".
3. Language: ${isTanglish ? "Reply in natural, polite Thanglish (Tamil spoken words written using the English alphabet, very common in Tamil Nadu, e.g. 'Route clear-aa irukku. Speed 60-la maintain pannunga')." : "Reply in clear, professional English."}
4. Audio TTS: 'audio_tts' must be a very short 1-2 sentence spoken version for text-to-speech.

Return strictly valid JSON with this structure:
{
  "answer": "Clear copilot response for driver",
  "intent": "navigation|speed|safety|greeting|general",
  "audio_tts": "Concise spoken version",
  "actionable_recommendation": "Quick driving safety tip"
}
''';
    } else if (promptMethod == PromptMethod.oneShot) {
      prompt = '''
You are NeuroCopilot, an expert in-car AI driving companion for the NeuroDrive application.
The driver asked: "$query"

Current Live Telemetry:
- Current Speed: ${currentSpeedKmh.round()} km/h
- Current Location: $loc
- Destination: $dest
- Distance Remaining: $distRem
- ETA: $eta
- Recent Alerts: $alertCount (${recentAlerts.join(', ')})

PROMPTING METHOD: ONE-SHOT PROMPTING
Exemplar:
User: "Current speed safe-aa irukka?"
Output:
{
  "answer": "Unga current speed ${currentSpeedKmh.round()} km/h. City road speed limit kulla perfectly safe-aa cruising panreenga.",
  "intent": "speed",
  "audio_tts": "Speed ${currentSpeedKmh.round()} km/h safe-aa irukku.",
  "actionable_recommendation": "Maintain steady pace"
}

Strict Rules:
1. Driver Safety: Keep answers clear and non-distracting for someone driving.
2. NEVER mention raw GPS coordinates or latitude/longitude numbers. Always use human-readable places like "$loc".
3. Language: ${isTanglish ? "Reply in natural, polite Thanglish (Tamil spoken words written using the English alphabet, very common in Tamil Nadu)." : "Reply in clear, professional English."}
4. Audio TTS: 'audio_tts' must be a very short 1-2 sentence spoken version for text-to-speech.

Return strictly valid JSON with this structure:
{
  "answer": "Clear copilot response for driver",
  "intent": "navigation|speed|safety|greeting|general",
  "audio_tts": "Concise spoken version",
  "actionable_recommendation": "Quick driving safety tip"
}
''';
    } else {
      // Zero-shot Prompting for general conversational & open-domain queries
      prompt = '''
You are NeuroCopilot, an intelligent in-car AI driving companion for the NeuroDrive application.
The driver asked: "$query"

Current Live Telemetry:
- Current Speed: ${currentSpeedKmh.round()} km/h
- Current Location: $loc
- Destination: $dest
- Distance Remaining: $distRem
- ETA: $eta
- Recent Alerts: $alertCount (${recentAlerts.join(', ')})

PROMPTING METHOD: ZERO-SHOT PROMPTING
Directly analyze the driver's query and provide an intelligent, accurate, and non-distracting response. Answer any kind of driving, vehicle mechanics, safety, route, traffic rules, or general question naturally.

Strict Rules:
1. Driver Safety: Keep answers clear, direct, and non-distracting for someone driving.
2. NEVER recite raw GPS latitude/longitude numbers. Always use human-readable places like "$loc".
3. Language: ${isTanglish ? "Reply in natural, polite Thanglish (Tamil spoken words written using the English alphabet, very common in Tamil Nadu, e.g. 'Vanakkam! Enna thevaiyo kelunga')." : "Reply in clear, professional English."}
4. Audio TTS: 'audio_tts' must be a very short 1-2 sentence spoken version for text-to-speech.

Return strictly valid JSON with this structure:
{
  "answer": "Clear copilot response for driver",
  "intent": "navigation|speed|safety|greeting|general",
  "audio_tts": "Concise spoken version",
  "actionable_recommendation": "Quick driving safety tip"
}
''';
    }

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
        'temperature': 0.3,
      }
    };

    final response = await client
        .post(
          endpoint,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>?;
      if (candidates != null && candidates.isNotEmpty) {
        final text = (candidates[0]['content']['parts'][0]['text'] ?? '').toString();
        var cleaned = text.trim();
        if (cleaned.startsWith('```json')) cleaned = cleaned.substring(7);
        if (cleaned.startsWith('```')) cleaned = cleaned.substring(3);
        if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3);
        final map = jsonDecode(cleaned.trim()) as Map<String, dynamic>;

        String? ex = map['exemplar']?.toString();
        if (ex == null && promptMethod == PromptMethod.oneShot) {
          ex = 'User: "Speed check?" ➔ AI: "Current speed ${currentSpeedKmh.round()} km/h is safe for city limits."';
        } else if (ex == null && promptMethod == PromptMethod.fewShot) {
          ex = '1. Collision Risk ➔ 4s gap\n2. Heavy Rain ➔ Wipers & low-beam 40 km/h\n3. Night Drive ➔ Hazard lights off';
        }

        return AiCopilotAnswer(
          success: true,
          answer: map['answer']?.toString() ?? '',
          intent: map['intent']?.toString() ?? 'general',
          audioTts: map['audio_tts']?.toString() ?? map['answer']?.toString() ?? '',
          actionableRecommendation: map['actionable_recommendation']?.toString(),
          isLocalFallback: false,
          promptMethod: promptMethod.name,
          exemplar: ex,
        );
      }
    }
    return null;
  }
}