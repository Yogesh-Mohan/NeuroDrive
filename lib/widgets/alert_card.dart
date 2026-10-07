import 'package:flutter/material.dart';

enum AlertSeverity { high, medium, low }

class AlertCard extends StatelessWidget {
  final String title;
  final String time;
  final String details;
  final AlertSeverity severity;

  const AlertCard({
    super.key,
    required this.title,
    required this.time,
    required this.details,
    required this.severity,
  });

  Color _getSeverityColor() {
    switch (severity) {
      case AlertSeverity.high:
        return const Color(0xFFFF5252);
      case AlertSeverity.medium:
        return const Color(0xFFFFB74D);
      case AlertSeverity.low:
        return const Color(0xFF4FC3F7);
    }
  }

  String _getSeverityLabel() {
    switch (severity) {
      case AlertSeverity.high:
        return 'CRITICAL';
      case AlertSeverity.medium:
        return 'WARNING';
      case AlertSeverity.low:
        return 'INFO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getSeverityColor();
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              severity == AlertSeverity.high
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _getSeverityLabel(),
                        style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  style: const TextStyle(
                    color: Color(0xFF8892B0),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  time,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
