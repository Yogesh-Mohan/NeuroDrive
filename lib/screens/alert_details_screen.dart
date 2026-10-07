import 'package:flutter/material.dart';

class AlertDetailsScreen extends StatelessWidget {
  const AlertDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alert Details'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Map Thumbnail with Danger Indicator
              Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B192C),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.map_rounded, size: 80, color: Colors.white10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.redAccent, width: 2),
                      ),
                      child: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Alert Telemetry Details List
              _buildDetailItem(Icons.calendar_today_rounded, '24 Sep 2026  10:32 AM', primaryColor),
              _buildDetailItem(Icons.location_on_rounded, 'Near NH-48, Chennai', primaryColor),
              _buildDetailItem(Icons.warning_rounded, 'Vehicle Approaching (Front)', Colors.redAccent),
              _buildDetailItem(Icons.straighten_rounded, 'Distance: 28 m', Colors.white),
              _buildDetailItem(Icons.speed_rounded, 'Relative Speed: 72 km/h', Colors.white),
              _buildDetailItem(Icons.directions_car_rounded, 'Your Speed: 65 km/h', Colors.white),

              const SizedBox(height: 24),

              // Dashcam Event Video Preview Box
              Container(
                height: 160,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.play_circle_fill_rounded, size: 60, color: primaryColor),
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('00:12', style: TextStyle(color: Colors.white, fontSize: 11)),
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

  Widget _buildDetailItem(IconData icon, String text, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 14),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
