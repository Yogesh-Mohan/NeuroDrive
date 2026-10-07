import 'package:flutter/material.dart';

class LiveDrivingScreen extends StatefulWidget {
  const LiveDrivingScreen({super.key});

  @override
  State<LiveDrivingScreen> createState() => _LiveDrivingScreenState();
}

class _LiveDrivingScreenState extends State<LiveDrivingScreen> {
  bool _isDriveModeOn = false;
  bool _isFollowingLocation = true;

  void _toggleDriveMode() {
    setState(() {
      _isDriveModeOn = !_isDriveModeOn;
    });
  }

  void _recenterMap() {
    setState(() {
      _isFollowingLocation = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Map centered on vehicle placeholder'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Driving Mode'),
        actions: [
          IconButton(
            icon: Icon(
              _isDriveModeOn ? Icons.stop_circle_rounded : Icons.play_circle_fill_rounded,
              color: _isDriveModeOn ? const Color(0xFFFF5252) : primaryColor,
              size: 28,
            ),
            onPressed: _toggleDriveMode,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top HUD Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: theme.colorScheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildHudItem('SPEED', _isDriveModeOn ? '0' : '--', 'KM/H', primaryColor),
                  Container(height: 30, width: 1, color: Colors.white12),
                  _buildHudItem('HEADING', _isDriveModeOn ? 'N 0°' : '--', '', Colors.white),
                  Container(height: 30, width: 1, color: Colors.white12),
                  _buildHudItem('GPS STATUS', _isDriveModeOn ? 'STANDBY' : 'NOT CONNECTED', '', 
                    _isDriveModeOn ? const Color(0xFFFFB74D) : const Color(0xFF8892B0)),
                ],
              ),
            ),

            // Main Map Canvas Container (Prepared for OpenStreetMap / flutter_map)
            Expanded(
              child: Stack(
                children: [
                  // Map Background Placeholder Grid
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Color(0xFF0B192C),
                    ),
                    child: Stack(
                      children: [
                        // Stylized Grid Overlay for Automotive HUD look
                        Positioned.fill(
                          child: CustomPaint(
                            painter: GridPainter(color: primaryColor.withValues(alpha: 0.05)),
                          ),
                        ),
                        // Vehicle Position Marker Placeholder
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: primaryColor, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: primaryColor.withValues(alpha: 0.3),
                                      blurRadius: 20,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.navigation_rounded,
                                  color: primaryColor,
                                  size: 40,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: const Text(
                                  'Map Container Placeholder\n(Ready for OpenStreetMap / flutter_map)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF8892B0),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Floating Map Action Controls
                  Positioned(
                    bottom: 20,
                    right: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'follow_btn',
                          onPressed: () {
                            setState(() => _isFollowingLocation = !_isFollowingLocation);
                          },
                          backgroundColor: _isFollowingLocation ? primaryColor : theme.colorScheme.surface,
                          child: Icon(
                            Icons.center_focus_strong_rounded,
                            color: _isFollowingLocation ? Colors.black : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 10),
                        FloatingActionButton(
                          heroTag: 'recenter_btn',
                          onPressed: _recenterMap,
                          backgroundColor: theme.colorScheme.surface,
                          child: Icon(Icons.my_location_rounded, color: primaryColor),
                        ),
                      ],
                    ),
                  ),

                  // Drive Mode Floating Status Badge
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isDriveModeOn ? primaryColor : Colors.grey,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isDriveModeOn ? const Color(0xFF00E676) : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isDriveModeOn ? 'DRIVE MODE ON' : 'DRIVE MODE OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHudItem(String label, String value, String unit, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8892B0),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(
                unit,
                style: const TextStyle(
                  color: Color(0xFF8892B0),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class GridPainter extends CustomPainter {
  final Color color;
  GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
