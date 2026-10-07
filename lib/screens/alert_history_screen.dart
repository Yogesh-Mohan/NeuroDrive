import 'package:flutter/material.dart';
import '../widgets/alert_card.dart';

class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  bool _showEmptyState = false;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Alerts Log'),
        actions: [
          IconButton(
            icon: Icon(_showEmptyState ? Icons.filter_alt_off : Icons.filter_alt),
            tooltip: 'Toggle Empty State Demo',
            onPressed: () => setState(() => _showEmptyState = !_showEmptyState),
          ),
        ],
      ),
      body: SafeArea(
        child: _showEmptyState
            ? Center(
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
                      'System will log warnings when safety threshold features are enabled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8892B0),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(20),
                children: const [
                  Text(
                    'Recent Notifications',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 14),
                  AlertCard(
                    title: 'System Initialized',
                    time: 'Today, 09:00 AM',
                    details: 'NeuroDrive safety engine loaded in Standby Mode.',
                    severity: AlertSeverity.low,
                  ),
                  AlertCard(
                    title: 'GPS Signal Pending',
                    time: 'Yesterday, 04:20 PM',
                    details: 'Location service requested. Awaiting satellite lock.',
                    severity: AlertSeverity.medium,
                  ),
                  AlertCard(
                    title: 'Collision Engine Notice',
                    time: '04 Oct 2026, 11:15 AM',
                    details: 'Placeholder alert format for future safety calculations.',
                    severity: AlertSeverity.high,
                  ),
                ],
              ),
      ),
    );
  }
}
