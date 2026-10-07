import 'package:flutter/material.dart';

class OfflineMapsScreen extends StatelessWidget {
  const OfflineMapsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Maps'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // Cloud Offline Graphic
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF0088FF).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.cloud_download_rounded,
                  size: 80,
                  color: Color(0xFF0088FF),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Offline Mode',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'No internet connection. Core features are still available.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF8892B0),
                  fontSize: 14,
                ),
              ),

              const SizedBox(height: 32),

              // Checklist Items
              _buildCheckTile('GPS Location'),
              _buildCheckTile('Real-time Speed'),
              _buildCheckTile('Collision Alerts'),
              _buildCheckTile('Trip History (Local)'),
              _buildCheckTile('Maps (Offline)'),

              const SizedBox(height: 32),

              // Cloud Sync Notice Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF112240),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline_rounded, color: primaryColor, size: 22),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Data will be synced to cloud when internet is available.',
                        style: TextStyle(color: Color(0xFF8892B0), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckTile(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
