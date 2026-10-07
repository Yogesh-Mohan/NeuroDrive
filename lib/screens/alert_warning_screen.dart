import 'package:flutter/material.dart';

class AlertWarningScreen extends StatelessWidget {
  const AlertWarningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E0002),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header Brand
              const Text(
                'NeuroDrive',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00D2FF),
                  letterSpacing: 1.0,
                ),
              ),

              // Glowing Red Car Graphic & Warning Chevrons
              Column(
                children: [
                  const Icon(
                    Icons.directions_car_filled_rounded,
                    size: 90,
                    color: Color(0xFFFF3344),
                  ),
                  const SizedBox(height: 16),
                  Column(
                    children: [
                      Icon(Icons.keyboard_double_arrow_up_rounded, size: 48, color: const Color(0xFFFF3344).withValues(alpha: 0.9)),
                      Icon(Icons.keyboard_double_arrow_up_rounded, size: 48, color: const Color(0xFFFF3344).withValues(alpha: 0.6)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Vehicle Approaching',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFF3344),
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),

              // Metrics Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFF3344).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: const [
                        Text('Distance', style: TextStyle(color: Color(0xFF8892B0), fontSize: 13)),
                        SizedBox(height: 4),
                        Text('28 m', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Container(height: 36, width: 1, color: Colors.white24),
                    Column(
                      children: const [
                        Text('Relative Speed', style: TextStyle(color: Color(0xFF8892B0), fontSize: 13)),
                        SizedBox(height: 4),
                        Text('72 km/h', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),

              // Stay Alert Red Pill Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3344),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 10,
                    shadowColor: const Color(0xFFFF3344).withValues(alpha: 0.5),
                  ),
                  child: const Text(
                    'Stay Alert',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
