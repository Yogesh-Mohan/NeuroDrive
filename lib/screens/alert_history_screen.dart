import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/services/alert_service.dart';
import '../core/services/alert_priority_assistant.dart';
import '../widgets/sync_status_badge.dart';

class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  final AlertService _alertService = AlertService();
  final AlertPriorityAssistant _priorityAssistant = AlertPriorityAssistant();
  List<PrioritizedAlert> _prioritizedAlerts = [];
  bool _isLoading = true;
  bool _isAiAssisted = false;
  String _summaryExplanation = '';

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _isLoading = true);
    try {
      final loaded = await _alertService.getAlerts();
      final result = await _priorityAssistant.prioritizeAlerts(loaded);

      if (mounted) {
        setState(() {
          _prioritizedAlerts = result.prioritizedAlerts;
          _isAiAssisted = result.isAiAssisted;
          _summaryExplanation = result.summaryExplanation;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _clearAlerts() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF112240),
        title: const Text('Clear All Alerts', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to clear your safety alerts log? This cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8892B0))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _alertService.clearAllAlerts();
      await _loadAlerts();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Alerts Log', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
            child: SyncStatusBadge(onSyncCompleted: _loadAlerts),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            tooltip: 'Clear Alerts',
            onPressed: _prioritizedAlerts.isNotEmpty ? _clearAlerts : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _loadAlerts,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: primaryColor))
            : _prioritizedAlerts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 72,
                            color: primaryColor.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No Safety Alerts Logged',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Alerts triggered during driving will appear here and sync automatically.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF8892B0),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: primaryColor,
                    backgroundColor: const Color(0xFF112240),
                    onRefresh: _loadAlerts,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _prioritizedAlerts.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // Priority Assistant Banner
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(0xFF112240),
                                  _isAiAssisted
                                      ? const Color(0xFF1D2D50)
                                      : const Color(0xFF0F1E36),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: _isAiAssisted
                                    ? primaryColor.withValues(alpha: 0.6)
                                    : Colors.white24,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _isAiAssisted ? Icons.auto_awesome_rounded : Icons.shield_rounded,
                                  color: primaryColor,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _isAiAssisted
                                                ? 'AI Priority Assistant Active'
                                                : 'Deterministic Safety Prioritization',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: primaryColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              '${_prioritizedAlerts.length} Events',
                                              style: const TextStyle(
                                                color: primaryColor,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _summaryExplanation,
                                        style: const TextStyle(
                                          color: Color(0xFF8892B0),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final item = _prioritizedAlerts[index - 1];
                        final alert = item.alert;
                        final isCritical = item.priority == AlertPriorityLevel.critical;
                        final isHigh = item.priority == AlertPriorityLevel.high;
                        final isMedium = item.priority == AlertPriorityLevel.medium;

                        final alertColor = isCritical
                            ? Colors.redAccent
                            : (isHigh
                                ? Colors.orangeAccent
                                : (isMedium ? const Color(0xFFFFD54F) : primaryColor));

                        final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(alert.timestamp);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF112240),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: alertColor.withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                isCritical ? Icons.warning_rounded : Icons.warning_amber_rounded,
                                color: alertColor,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          alert.alertType.replaceAll('_', ' '),
                                          style: TextStyle(
                                            color: alertColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            if (!alert.isSynced) ...[
                                              const Tooltip(
                                                message: 'Stored locally, pending cloud sync',
                                                child: Icon(Icons.cloud_off_rounded, size: 14, color: Colors.orangeAccent),
                                              ),
                                              const SizedBox(width: 4),
                                            ],
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: alertColor.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '${item.priorityLabel.toUpperCase()} (${item.priorityScore})',
                                                style: TextStyle(
                                                  color: alertColor,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      alert.message,
                                      style: const TextStyle(color: Colors.white, fontSize: 13),
                                    ),
                                    const SizedBox(height: 6),
                                    // Factual Priority Reason
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black26,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'Why: ${item.priorityReason}',
                                        style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          dateStr,
                                          style: const TextStyle(color: Color(0xFF8892B0), fontSize: 11),
                                        ),
                                        if (item.audioVoicePrompt.isNotEmpty)
                                          Row(
                                            children: [
                                              const Icon(Icons.volume_up_rounded, size: 12, color: Color(0xFF00D2FF)),
                                              const SizedBox(width: 4),
                                              Text(
                                                '"${item.audioVoicePrompt}"',
                                                style: const TextStyle(
                                                  color: Color(0xFF00D2FF),
                                                  fontSize: 10,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                    if (alert.distance != null || alert.ttc != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Distance: ${alert.distance?.toStringAsFixed(1) ?? "--"}m • TTC: ${alert.ttc?.toStringAsFixed(1) ?? "--"}s',
                                        style: const TextStyle(color: Color(0xFF00D2FF), fontSize: 11),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
