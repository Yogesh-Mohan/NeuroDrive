import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/services/ai_copilot_service.dart';

/// Interactive In-Drive HUD Bottom Sheet for NeuroCopilot
class CopilotSheet extends StatefulWidget {
  final String? currentLocationName;
  final double? latitude;
  final double? longitude;
  final String? destinationName;
  final double? distanceRemainingKm;
  final double? etaMinutes;
  final double currentSpeedKmh;
  final int alertCount;
  final List<String> recentAlerts;

  const CopilotSheet({
    super.key,
    this.currentLocationName,
    this.latitude,
    this.longitude,
    this.destinationName,
    this.distanceRemainingKm,
    this.etaMinutes,
    required this.currentSpeedKmh,
    required this.alertCount,
    this.recentAlerts = const [],
  });

  @override
  State<CopilotSheet> createState() => _CopilotSheetState();
}

class _CopilotSheetState extends State<CopilotSheet> {
  final TextEditingController _queryController = TextEditingController();
  final AiCopilotService _copilotService = AiCopilotService();

  bool _isLoading = false;
  String _languageMode = 'tanglish'; // 'tanglish' | 'english'
  AiCopilotAnswer? _latestAnswer;
  bool _isSpeaking = false;
  late stt.SpeechToText _speech;
  bool _isListening = false;

  @override
  void initState() {
    super.initState();
    // Default welcome prompt
    _speech = stt.SpeechToText();
    _askDefaultPrompt();
  }

  @override
  void dispose() {
    if (_isListening) {
      _speech.stop();
    }
    _copilotService.stopSpeaking();
    _queryController.dispose();
    super.dispose();
  }


  Future<void> _toggleVoiceInput() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (val) {
          if (mounted) setState(() => _isListening = false);
        },
      );
      if (available) {
        if (mounted) setState(() => _isListening = true);
        _speech.listen(
          listenOptions: stt.SpeechListenOptions(localeId: _languageMode == 'tanglish' ? 'en_IN' : 'en_US'),
          onResult: (val) {
            if (mounted) {
              setState(() {
                _queryController.text = val.recognizedWords;
              });
              if (val.finalResult && val.recognizedWords.trim().isNotEmpty) {
                _handleAsk(val.recognizedWords);
              }
            }
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _askDefaultPrompt() {
    setState(() {
      _latestAnswer = AiCopilotAnswer(
        success: true,
        answer: _languageMode == 'tanglish'
            ? 'Vanakkam! Naan unga NeuroCopilot. Destination, Current Location, or Alerts pathi ethuvum kelunga!'
            : 'Welcome! I am your NeuroCopilot. Ask about ETA, location, or driving alerts hands-free.',
        intent: 'greeting',
        audioTts: '',
      );
    });
  }

  Future<void> _handleAsk(String query) async {
    if (query.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
    });

    try {
      final res = await _copilotService.askCopilot(
        query: query,
        currentLocationName: widget.currentLocationName,
        latitude: widget.latitude,
        longitude: widget.longitude,
        destinationName: widget.destinationName,
        distanceRemainingKm: widget.distanceRemainingKm,
        etaMinutes: widget.etaMinutes,
        currentSpeedKmh: widget.currentSpeedKmh,
        alertCount: widget.alertCount,
        recentAlerts: widget.recentAlerts,
        languageMode: _languageMode,
      );

      if (mounted) {
        setState(() {
          _latestAnswer = res;
          _isLoading = false;
          _isSpeaking = true;
        });
      }

      // Speak answer audibly
      await _copilotService.speak(res.audioTts);
      if (mounted) {
        setState(() {
          _isSpeaking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSpeaking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1B2A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: const Color(0xFF00E5FF).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header with AI Avatar & Language Toggle
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF0072FF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NeuroCopilot AI',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF00E676),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _isSpeaking
                              ? 'Speaking...'
                              : (_isLoading ? 'Thinking...' : 'Hands-Free Ready'),
                          style: TextStyle(
                            fontSize: 12,
                            color: _isSpeaking ? const Color(0xFF00E5FF) : Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Language Toggle (Tanglish / English)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1B2A4A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    _buildLangChip('Tanglish', 'tanglish'),
                    _buildLangChip('English', 'english'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // AI Response Bubble
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF132238),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.volume_up_rounded,
                          size: 18,
                          color: _isSpeaking ? const Color(0xFF00E5FF) : Colors.white54,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _latestAnswer?.isLocalFallback == true
                              ? 'LOCAL AI [${(_latestAnswer?.promptMethod ?? "one-shot").toUpperCase()}${_latestAnswer?.promptMethod == "one-shot" ? " (1 EXAMPLE)" : ""}]'
                              : 'GEMINI FLASH [${(_latestAnswer?.promptMethod ?? "few-shot").toUpperCase()}${_latestAnswer?.promptMethod == "one-shot" ? " (1 EXAMPLE)" : ""}]',
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w600,
                            color: _latestAnswer?.isLocalFallback == true ? const Color(0xFFFFB74D) : const Color(0xFF00E5FF),
                          ),
                        ),

                      ],
                    ),
                    if (_latestAnswer != null && _latestAnswer!.audioTts.isNotEmpty)
                      InkWell(
                        onTap: () => _copilotService.speak(_latestAnswer!.audioTts),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.replay_rounded, size: 18, color: Colors.white70),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF00E5FF),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Analyzing telemetry...', style: TextStyle(color: Colors.white70)),
                      ],
                    ),
                  )
                else
                  Text(
                    _latestAnswer?.answer ?? '',
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                if (_latestAnswer?.actionableRecommendation != null &&
                    _latestAnswer!.actionableRecommendation!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF00E5FF)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _latestAnswer!.actionableRecommendation!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF00E5FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (_latestAnswer?.exemplar != null || _latestAnswer?.promptMethod == 'one-shot') ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lightbulb_rounded, size: 14, color: Color(0xFF00E5FF)),
                            SizedBox(width: 6),
                            Text(
                              'ONE-SHOT PROMPT EXEMPLAR:',
                              style: TextStyle(
                                color: Color(0xFF00E5FF),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _latestAnswer?.exemplar ?? 'Exemplar: User asks for status ➔ AI answers with live telemetry and safe advice.',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (_latestAnswer?.promptMethod == 'few-shot') ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.psychology_rounded, size: 14, color: Colors.amber),
                            SizedBox(width: 6),
                            Text(
                              'FEW-SHOT PROMPT EXEMPLARS (3 Multi-Turn References):',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _latestAnswer?.exemplar ?? '1. Collision Hazard ➔ Decelerate & 4s gap\n2. Heavy Rain ➔ Wipers & low-beam 40 km/h\n3. Location ➔ Area name with zero GPS coordinates',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Quick Action Questions Pills
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickAction(
                  icon: Icons.location_on_rounded,
                  label: _languageMode == 'tanglish' ? 'Enga irukom?' : 'Where are we?',
                  query: _languageMode == 'tanglish' ? 'Namma epo enga irukom?' : 'Where are we right now?',
                ),
                const SizedBox(width: 8),
                _buildQuickAction(
                  icon: Icons.timer_rounded,
                  label: _languageMode == 'tanglish' ? 'ETA evlo neram?' : 'Remaining ETA?',
                  query: _languageMode == 'tanglish' ? 'Destination reach aaga evlo neram aagum?' : 'What is our ETA to destination?',
                ),
                const SizedBox(width: 8),
                _buildQuickAction(
                  icon: Icons.warning_amber_rounded,
                  label: _languageMode == 'tanglish' ? 'Evlo alerts?' : 'Alerts count?',
                  query: _languageMode == 'tanglish' ? 'Ithuvaraikum ethana alerts vanthurukku?' : 'How many safety alerts occurred so far?',
                ),
                const SizedBox(width: 8),
                _buildQuickAction(
                  icon: Icons.security_rounded,
                  label: _languageMode == 'tanglish' ? 'Safe-aa poroma?' : 'Driving check',
                  query: _languageMode == 'tanglish' ? 'Driving status safe-aa irukka?' : 'Is our driving condition safe?',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Text Input Field + Send / Speak
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _queryController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: _languageMode == 'tanglish'
                        ? 'Ask Copilot (e.g., ETA evlo, alerts ethana)...'
                        : 'Ask Copilot hands-free...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF132238),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (val) {
                    _handleAsk(val);
                    _queryController.clear();
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Mic Button for Speech-to-Speech
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? Colors.redAccent : const Color(0xFF132238),
                  border: Border.all(
                    color: _isListening ? Colors.redAccent : const Color(0xFF00E5FF).withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: IconButton(
                  icon: Icon(
                    _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                    color: _isListening ? Colors.white : const Color(0xFF00E5FF),
                  ),
                  onPressed: _toggleVoiceInput,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF0072FF)],
                  ),
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  onPressed: () {
                    _handleAsk(_queryController.text);
                    _queryController.clear();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLangChip(String label, String mode) {
    final isSelected = _languageMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          _languageMode = mode;
        });
        _speech = stt.SpeechToText();
    _askDefaultPrompt();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00E5FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isSelected ? const Color(0xFF0D1B2A) : Colors.white60,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required String query,
  }) {
    return InkWell(
      onTap: () => _handleAsk(query),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1B2A4A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF00E5FF)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
