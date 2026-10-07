import 'package:flutter/material.dart';

class GlassesScreen extends StatefulWidget {
  const GlassesScreen({super.key});

  @override
  State<GlassesScreen> createState() => _GlassesScreenState();
}

class _GlassesScreenState extends State<GlassesScreen> {
  bool _isConnected = false;

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Glasses'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              // Smart Glasses Graphic Container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: const Color(0xFF112240),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: primaryColor.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.visibility_rounded,
                      size: 100,
                      color: _isConnected ? primaryColor : const Color(0xFF8892B0),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'NeuroDrive Glasses',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isConnected ? 'Connected via BLE' : 'Not Connected',
                      style: TextStyle(
                        color: _isConnected ? Colors.greenAccent : const Color(0xFF8892B0),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Connect Bluetooth Button
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    setState(() => _isConnected = !_isConnected);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_isConnected ? 'Searching & Pairing NeuroDrive Glasses...' : 'Disconnected from Glasses.'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bluetooth_rounded),
                  label: Text(_isConnected ? 'Disconnect' : 'Connect'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isConnected ? Colors.redAccent : const Color(0xFF0088FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 6,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Status Cards List
              _buildInfoTile(
                icon: Icons.battery_charging_full_rounded,
                title: 'Battery Status',
                value: _isConnected ? '85%' : '--',
                primaryColor: primaryColor,
              ),
              _buildInfoTile(
                icon: Icons.cell_tower_rounded,
                title: 'Connection Status',
                value: _isConnected ? 'Active' : 'Not Connected',
                primaryColor: primaryColor,
              ),
              _buildInfoTile(
                icon: Icons.devices_rounded,
                title: 'Device Name',
                value: 'NeuroDrive Glasses',
                primaryColor: primaryColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String value,
    required Color primaryColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF112240),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryColor),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
