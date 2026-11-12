import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../core/models/trip_model.dart';
import '../core/models/alert_model.dart';
import '../core/services/ai_safety_service.dart';
import '../core/services/alert_service.dart';
import '../core/services/trip_report_pdf_service.dart';

class TripDetailsScreen extends StatefulWidget {
  final TripModel trip;
  final List<AlertModel> allAlerts;
  final AiSafetyService? aiSafetyService; // Injectable for testing
  final Future<Directory> Function()? getDocsDirectory; // Injectable for testing

  const TripDetailsScreen({
    super.key,
    required this.trip,
    this.allAlerts = const [],
    this.aiSafetyService,
    this.getDocsDirectory,
  });

  @override
  State<TripDetailsScreen> createState() => _TripDetailsScreenState();
}

class _TripDetailsScreenState extends State<TripDetailsScreen> {
  late final AiSafetyService _aiService;
  bool _isGenerating = false;
  AiSafetyReport? _report;
  String? _errorMessage;
  List<AlertModel> _loadedAlerts = [];

  @override
  void initState() {
    super.initState();
    _aiService = widget.aiSafetyService ?? AiSafetyService();
    _loadedAlerts = List.from(widget.allAlerts);
    if (_loadedAlerts.isEmpty) {
      _fetchTripAlerts();
    }
  }

  Future<void> _fetchTripAlerts() async {
    try {
      final all = await AlertService().getAlerts();
      if (mounted && all.isNotEmpty) {
        setState(() {
          _loadedAlerts = all;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (widget.aiSafetyService == null) {
      _aiService.dispose();
    }
    super.dispose();
  }

  /// Filters alerts that occurred during this specific trip's time window.
  List<AlertModel> get _tripAlerts {
    final list = _loadedAlerts.isNotEmpty ? _loadedAlerts : widget.allAlerts;
    return list.where((a) {
      if (a.tripId != null && a.tripId == widget.trip.tripId) {
        return true;
      }
      return a.timestamp.isAfter(widget.trip.startTime.subtract(const Duration(minutes: 2))) &&
          a.timestamp.isBefore(widget.trip.endTime.add(const Duration(minutes: 2)));
    }).toList();
  }

  Future<void> _showApiKeyDialog() async {
    final currentKey = await AiSafetyService.getEffectiveApiKeyStatic() ?? '';
    final controller = TextEditingController(text: currentKey);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF112240),
        title: const Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: Color(0xFF00D2FF), size: 22),
            SizedBox(width: 8),
            Text('Gemini Flash API Key', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Google AI Studio-la irundhu free Gemini API key-ah enter pannunga (1-second cloud reports).',
              style: TextStyle(color: Color(0xFF8892B0), fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'AIzaSy...',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: const Color(0xFF0B192C),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D2FF),
              foregroundColor: Colors.black,
            ),
            onPressed: () async {
              await AiSafetyService.saveGeminiApiKey(controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Gemini API Key saved successfully!')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _generateReport() async {
    if (_isGenerating) return; // Prevent duplicate concurrent requests

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final report = await _aiService.generateTripSafetyReport(
        trip: widget.trip,
        alerts: _tripAlerts,
        languageMode: 'tanglish',
      );

      if (mounted) {
        setState(() {
          _report = report;
          _isGenerating = false;
        });
      }
    } catch (e) {
      debugPrint('AI Report Generation Error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);
    const cardColor = Color(0xFF112240);
    const darkBg = Color(0xFF0A192F);

    final startDt = widget.trip.startTime;
    final endDt = widget.trip.endTime;
    final dateStr = DateFormat('EEEE, dd MMMM yyyy').format(startDt);
    final startTimeStr = DateFormat('hh:mm a').format(startDt);
    final endTimeStr = DateFormat('hh:mm a').format(endDt);

    final distKm = widget.trip.distanceKm.toStringAsFixed(2);
    final durationStr = widget.trip.formattedDuration;
    final speedStr = '${widget.trip.avgSpeed.toStringAsFixed(1)} km/h';

    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        title: const Text('Trip Details', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: cardColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trip Header & Date
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          dateStr,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (widget.trip.isSynced)
                          const Row(
                            children: [
                              Icon(Icons.cloud_done_rounded, size: 16, color: Colors.greenAccent),
                              SizedBox(width: 4),
                              Text('Synced', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                            ],
                          )
                        else
                          const Row(
                            children: [
                              Icon(Icons.cloud_off_rounded, size: 16, color: Colors.orangeAccent),
                              SizedBox(width: 4),
                              Text('Local only', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$startTimeStr - $endTimeStr',
                      style: const TextStyle(color: Color(0xFF8892B0), fontSize: 13),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Telemetry Metrics Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      label: 'Distance',
                      value: '$distKm km',
                      icon: Icons.route_rounded,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      label: 'Duration',
                      value: durationStr,
                      icon: Icons.timer_outlined,
                      color: const Color(0xFF64FFDA),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      label: 'Avg Speed',
                      value: speedStr,
                      icon: Icons.speed_rounded,
                      color: const Color(0xFFFFB74D),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Recorded Safety Alerts Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shield_outlined, color: primaryColor, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Recorded Safety Events',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _tripAlerts.isEmpty
                                ? Colors.greenAccent.withValues(alpha: 0.15)
                                : Colors.orangeAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_tripAlerts.length} Alerts',
                            style: TextStyle(
                              color: _tripAlerts.isEmpty ? Colors.greenAccent : Colors.orangeAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_tripAlerts.isEmpty)
                      const Text(
                        'No safety warnings or proximity alerts were recorded during this trip.',
                        style: TextStyle(color: Color(0xFF8892B0), fontSize: 13),
                      )
                    else
                      Column(
                        children: _tripAlerts.map((a) {
                          final isCritical = a.severity == 'critical';
                          final isWarning = a.severity == 'warning';
                          final alertColor = isCritical
                              ? Colors.redAccent
                              : (isWarning ? Colors.orangeAccent : primaryColor);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B192C),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: alertColor.withValues(alpha: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: alertColor, size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    a.message,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                if (a.distance != null)
                                  Text('${a.distance!.toStringAsFixed(0)}m', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // AI Safety Analyst Action / Report Section
              _buildAiSafetySection(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF112240),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8892B0), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildAiSafetySection() {
    const primaryColor = Color(0xFF00D2FF);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF112240),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _report != null ? primaryColor.withValues(alpha: 0.6) : Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with AI Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded, color: primaryColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Trip Safety Report',
                      style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _report != null
                          ? 'Powered by ${_report!.model}'
                          : 'Powered by Google Gemini Flash AI',
                      style: const TextStyle(color: Color(0xFF8892B0), fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.key_rounded, color: primaryColor, size: 18),
                tooltip: 'Configure Gemini API Key',
                onPressed: _showApiKeyDialog,
              ),
              if (_report != null)
                _buildRiskBadge(_report!.riskLevel),
            ],
          ),

          const SizedBox(height: 16),

          // Loading State
          if (_isGenerating)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: primaryColor),
                    const SizedBox(height: 16),
                    const Text(
                      'Analyzing trip telemetry with Gemini Flash AI...',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Instant 1-second cloud inference & Thanglish safety report',
                      style: TextStyle(color: Color(0xFF8892B0), fontSize: 11),
                    ),
                  ],
                ),
              ),
            )
          // Error State
          else if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'Report Generation Failed',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _generateReport,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry Analysis'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            )
          // Report Content Display
          else if (_report != null)
            _buildReportContent(_report!)
          // Initial Action State
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Run Google Gemini Flash AI analysis on this trip to generate an intelligent safety evaluation, factual observations, and personalized driving recommendations in Thanglish.',
                  style: TextStyle(color: Color(0xFF8892B0), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _generateReport,
                    icon: const Icon(Icons.psychology_rounded, size: 20),
                    label: const Text(
                      'Generate AI Safety Report',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: const Color(0xFF0A192F),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 4,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildRiskBadge(String riskLevel) {
    Color bg;
    Color fg;
    String label;

    switch (riskLevel.toLowerCase()) {
      case 'high':
        bg = Colors.redAccent.withValues(alpha: 0.2);
        fg = Colors.redAccent;
        label = 'HIGH RISK';
        break;
      case 'medium':
      case 'moderate':
        bg = Colors.orangeAccent.withValues(alpha: 0.2);
        fg = Colors.orangeAccent;
        label = 'MEDIUM RISK';
        break;
      default:
        bg = Colors.greenAccent.withValues(alpha: 0.2);
        fg = Colors.greenAccent;
        label = 'LOW RISK';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildReportContent(AiSafetyReport report) {
    const primaryColor = Color(0xFF00D2FF);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Warnings (if partial telemetry)
        if (report.warnings.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report.warnings.first,
                    style: const TextStyle(color: Colors.amber, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

        // Section 1: Trip Summary
        _buildReportSectionHeader('Trip Summary', Icons.notes_rounded),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B192C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Text(
            report.tripSummary,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          ),
        ),

        const SizedBox(height: 16),

        // Section 2: Data-Supported Observations
        _buildReportSectionHeader('Data-Supported Observations', Icons.analytics_outlined),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B192C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFactRow('Distance Covered', '${report.dataSupportedObservations['distance_km']} km'),
              _buildFactRow('Duration', '${report.dataSupportedObservations['duration_minutes']} min'),
              _buildFactRow('Average Speed', '${report.dataSupportedObservations['average_speed_kmh']} km/h'),
              _buildFactRow('Alert Count', '${report.dataSupportedObservations['total_alerts']}'),
              _buildFactRow('Completeness', '${report.dataSupportedObservations['telemetry_completeness']}'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Section 3: Practical Recommendations
        _buildReportSectionHeader('Practical Recommendations', Icons.recommend_rounded),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline_rounded, color: primaryColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  report.practicalRecommendations,
                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Download / Export Report Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            key: const Key('download_report_button'),
            onPressed: () => _downloadOrExportReport(report),
            icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.black, size: 20),
            label: const Text(
              'Download Trip Safety Report',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00D2FF),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Re-generate button & metadata
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (report.inferenceTimeSec != null)
              Text(
                'Inference: ${report.inferenceTimeSec!.toStringAsFixed(2)}s',
                style: const TextStyle(color: Color(0xFF8892B0), fontSize: 11),
              ),
            TextButton.icon(
              onPressed: _generateReport,
              icon: const Icon(Icons.refresh_rounded, size: 16, color: primaryColor),
              label: const Text('Re-analyze', style: TextStyle(color: primaryColor, fontSize: 12)),
            ),
          ],
        ),

        // Scientific / Safety Disclaimer
        const Divider(color: Colors.white12, height: 20),
        const Text(
          'Disclaimer: This analysis is generated by an AI sequence-to-sequence model using trip telemetry. It is provided for driver awareness and does not represent an official mechanical diagnosis.',
          style: TextStyle(color: Color(0xFF8892B0), fontSize: 10, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  void _showReportViewerModal(BuildContext context, String fullReportText) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF112240),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.description_rounded, color: Color(0xFF00D2FF), size: 22),
                          SizedBox(width: 8),
                          Text(
                            'Trip Safety Report',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        onPressed: () => Navigator.pop(bctx),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A192F),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: SelectableText(
                          fullReportText,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'monospace',
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00D2FF),
                            side: const BorderSide(color: Color(0xFF00D2FF)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: fullReportText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Full report copied to clipboard!'),
                                backgroundColor: Color(0xFF00D2FF),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy Text'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00D2FF),
                            foregroundColor: const Color(0xFF0A192F),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.pop(bctx),
                          child: const Text('Done', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _downloadOrExportReport(AiSafetyReport report) async {
    try {
      final safeScore = report.dataSupportedObservations['safety_score'] ?? 'N/A';
      final dist = report.dataSupportedObservations['distance_km'] ?? (widget.trip.distance / 1000.0).toStringAsFixed(1);
      final dur = report.dataSupportedObservations['duration_minutes'] ?? (widget.trip.duration / 60.0).toStringAsFixed(1);
      final spd = report.dataSupportedObservations['average_speed_kmh'] ?? widget.trip.avgSpeed.toStringAsFixed(1);
      final alerts = report.dataSupportedObservations['total_alerts'] ?? _tripAlerts.length;
      final timeOfDay = report.dataSupportedObservations['time_of_day'] ?? 'Standard';

      final buffer = StringBuffer();
      buffer.writeln('========================================================');
      buffer.writeln('          NEURODRIVE AI TRIP SAFETY REPORT              ');
      buffer.writeln('========================================================');
      buffer.writeln('Trip ID:       ${widget.trip.tripId}');
      buffer.writeln('Date & Time:   ${DateFormat('yyyy-MM-dd HH:mm').format(widget.trip.startTime)}');
      buffer.writeln('AI Model:      ${report.model}');
      buffer.writeln('Risk Level:    ${report.riskLevel.toUpperCase()}');
      buffer.writeln('Safety Score:  $safeScore / 100');
      buffer.writeln('--------------------------------------------------------');
      buffer.writeln('--- TRIP TELEMETRY ---');
      buffer.writeln('Total Distance:     $dist km');
      buffer.writeln('Duration:           $dur minutes');
      buffer.writeln('Average Speed:      $spd km/h');
      buffer.writeln('Time of Day:        $timeOfDay');
      buffer.writeln('Recorded Alerts:    $alerts events');
      buffer.writeln('Telemetry Status:   ${report.dataSupportedObservations['telemetry_completeness'] ?? 'Complete'}');
      buffer.writeln('--------------------------------------------------------');
      buffer.writeln('--- TRIP SUMMARY ---');
      buffer.writeln(report.tripSummary);
      buffer.writeln('--------------------------------------------------------');
      buffer.writeln('--- PRACTICAL RECOMMENDATIONS ---');
      buffer.writeln(report.practicalRecommendations);
      buffer.writeln('========================================================');
      buffer.writeln('Generated by NeuroDrive ADAS Copilot');

      final reportText = buffer.toString();

      // Copy to clipboard for instant sharing
      try {
        await Clipboard.setData(ClipboardData(text: reportText)).timeout(const Duration(milliseconds: 150));
      } catch (e) {
        debugPrint('[TripDetails] Clipboard notice: $e');
      }

      // Generate professional PDF bytes
      Uint8List? pdfBytes;
      try {
        pdfBytes = await TripReportPdfService.generateTripReportPdf(
          trip: widget.trip,
          report: report,
          alerts: _tripAlerts,
        );
      } catch (pdfErr) {
        debugPrint('[TripDetails] PDF generation note: $pdfErr');
      }

      // Priority storage destinations:
      // 1. Injected directory (for unit testing)
      // 2. Android public Downloads folder (/storage/emulated/0/Download)
      // 3. getDownloadsDirectory()
      // 4. getExternalStorageDirectory()
      // 5. getApplicationDocumentsDirectory()
      final pdfFileName = 'NeuroDrive_TripReport_${widget.trip.tripId}.pdf';
      final txtFileName = 'NeuroDrive_TripReport_${widget.trip.tripId}.txt';
      String savedPdfPath = '';
      String savedTxtPath = '';
      bool savedSuccessfully = false;
      const nativeChannel = MethodChannel('com.neurodrive.app/native_service');

      // 1. Try Native Android MediaStore Downloads (Public /storage/emulated/0/Download)
      if (pdfBytes != null && !kIsWeb && Platform.isAndroid && widget.getDocsDirectory == null) {
        try {
          final res = await nativeChannel.invokeMethod<String>('savePdfToDownloads', {
            'fileName': pdfFileName,
            'bytes': pdfBytes,
          });
          if (res != null && res.isNotEmpty) {
            savedPdfPath = res;
            savedSuccessfully = true;
            debugPrint('[TripDetails] PDF saved to device Downloads via MediaStore: $savedPdfPath');
          }
        } catch (nativeErr) {
          debugPrint('[TripDetails] Native MediaStore download notice: $nativeErr');
        }
      }

      final candidateDirs = <Directory>[];

      if (widget.getDocsDirectory != null) {
        try {
          candidateDirs.add(await widget.getDocsDirectory!());
        } catch (_) {}
      } else {
        if (!kIsWeb && Platform.isAndroid) {
          try {
            candidateDirs.add(Directory('/storage/emulated/0/Download'));
          } catch (_) {}
        }

        try {
          final d = await getDownloadsDirectory();
          if (d != null) candidateDirs.add(d);
        } catch (_) {}

        try {
          final ext = await getExternalStorageDirectory();
          if (ext != null) candidateDirs.add(ext);
        } catch (_) {}

        try {
          candidateDirs.add(await getApplicationDocumentsDirectory());
        } catch (_) {}
      }

      for (final dir in candidateDirs) {
        try {
          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }
          if (pdfBytes != null && savedPdfPath.isEmpty) {
            final pdfFile = File('${dir.path}/$pdfFileName');
            pdfFile.writeAsBytesSync(pdfBytes, flush: true);
            savedPdfPath = pdfFile.path;
          }
          final txtFile = File('${dir.path}/$txtFileName');
          txtFile.writeAsStringSync(reportText, flush: true);
          savedTxtPath = txtFile.path;
          savedSuccessfully = true;
          break;
        } catch (e) {
          debugPrint('[TripDetails] File writing attempted at ${dir.path} failed: $e');
        }
      }

      if (!mounted) return;

      final effectivePath = savedPdfPath.isNotEmpty ? savedPdfPath : savedTxtPath;
      final effectiveName = savedPdfPath.isNotEmpty ? pdfFileName : txtFileName;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF112240),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF00D2FF), size: 24),
              SizedBox(width: 8),
              Text(
                'Report Downloaded',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D2FF).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF00D2FF).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF00D2FF), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      savedPdfPath.isNotEmpty ? 'PDF FORMAT READY (.pdf)' : 'REPORT SAVED',
                      style: const TextStyle(color: Color(0xFF00D2FF), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Trip Safety Report has been generated in PDF format and saved to your device.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (savedSuccessfully && effectivePath.isNotEmpty) ...[
                const Text(
                  'Saved Location:',
                  style: TextStyle(color: Color(0xFF8892B0), fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A192F),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: SelectableText(
                    effectivePath.contains('Download') ? 'Downloads/$effectiveName\n($effectivePath)' : effectivePath,
                    style: const TextStyle(color: Color(0xFF00D2FF), fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D2FF).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.content_copy_rounded, color: Color(0xFF00D2FF), size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Full report text copied to Clipboard for instant sharing.',
                        style: TextStyle(color: Color(0xFF00D2FF), fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (savedPdfPath.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00D2FF),
                      side: const BorderSide(color: Color(0xFF00D2FF)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () async {
                      try {
                        await nativeChannel.invokeMethod('openPdfFile', {'filePath': savedPdfPath});
                      } catch (openErr) {
                        debugPrint('[TripDetails] Native open PDF notice: $openErr');
                      }
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open PDF in Device Viewer', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00D2FF),
                    foregroundColor: const Color(0xFF0A192F),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _showReportViewerModal(context, reportText);
                  },
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text('View Full Report Now', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(color: Color(0xFF00D2FF), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('[TripDetails] Download failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildReportSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF00D2FF)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildFactRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
