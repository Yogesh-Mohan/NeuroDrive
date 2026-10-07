import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/constants/app_routes.dart';
import '../core/services/location_service.dart';
import '../core/services/safety_engine.dart';
import '../core/services/notification_service.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  bool _isDriveModeOn = true;
  
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionSubscription;
  
  double _currentSpeed = 0.0;
  String _currentHeading = '--';
  String _gpsStatus = 'Searching';

  final SafetyEngine _safetyEngine = SafetyEngine();
  SafetyStatus _currentSafetyStatus = SafetyStatus(
    riskLevel: RiskLevel.safe, 
    message: 'Initializing...',
  );

  @override
  void initState() {
    super.initState();
    _startListening();
  }

  void _startListening() async {
    final hasPermission = await _locationService.handlePermissions();
    if (!hasPermission) {
      if (mounted) setState(() => _gpsStatus = 'Denied');
      return;
    }
    
    _positionSubscription = _locationService.getLocationStream()?.listen((Position position) {
      if (mounted) {
        final status = _safetyEngine.evaluateRisk(currentEgoPosition: position);
        NotificationService().handleSafetyStatus(status);
        
        setState(() {
          // Convert m/s to km/h
          double speedKmh = position.speed * 3.6;
          _currentSpeed = speedKmh < 1.0 ? 0.0 : speedKmh;
          _currentHeading = _getHeadingString(position.heading);
          _gpsStatus = 'Good';
          _currentSafetyStatus = status;
        });
      }
    });
  }

  String _getHeadingString(double heading) {
    if (heading < 0) return '--';
    if (heading >= 337.5 || heading < 22.5) return 'N';
    if (heading >= 22.5 && heading < 67.5) return 'NE';
    if (heading >= 67.5 && heading < 112.5) return 'E';
    if (heading >= 112.5 && heading < 157.5) return 'SE';
    if (heading >= 157.5 && heading < 202.5) return 'S';
    if (heading >= 202.5 && heading < 247.5) return 'SW';
    if (heading >= 247.5 && heading < 292.5) return 'W';
    if (heading >= 292.5 && heading < 337.5) return 'NW';
    return '--';
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const Icon(Icons.menu_rounded, color: Colors.white),
            const SizedBox(width: 16),
            const Text(
              'NeuroDrive',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, letterSpacing: 0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.alertHistory),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drive Mode Banner
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF112240),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: primaryColor.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.shield_rounded, color: Colors.greenAccent, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Drive Mode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            !_isDriveModeOn 
                                ? 'Safety monitoring is off' 
                                : _currentSafetyStatus.message,
                            style: TextStyle(
                              color: !_isDriveModeOn 
                                  ? const Color(0xFF8892B0) 
                                  : (_currentSafetyStatus.riskLevel == RiskLevel.critical 
                                      ? Colors.redAccent 
                                      : _currentSafetyStatus.riskLevel == RiskLevel.warning
                                          ? Colors.orangeAccent
                                          : const Color(0xFF8892B0)),
                              fontSize: 12,
                              fontWeight: _currentSafetyStatus.riskLevel != RiskLevel.safe ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _isDriveModeOn,
                      onChanged: (val) => setState(() => _isDriveModeOn = val),
                      activeTrackColor: Colors.green,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2x2 Telemetry Grid
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildMetricCard(
                    title: 'Current Speed',
                    value: _currentSpeed.toStringAsFixed(0),
                    unit: 'km/h',
                    icon: Icons.speed_rounded,
                    color: primaryColor,
                  ),
                  _buildMetricCard(
                    title: 'Direction',
                    value: _currentHeading,
                    unit: '',
                    icon: Icons.near_me_rounded,
                    color: primaryColor,
                  ),
                  _buildMetricCard(
                    title: 'GPS Signal',
                    value: _gpsStatus,
                    unit: '',
                    icon: Icons.signal_cellular_alt_rounded,
                    color: _gpsStatus == 'Good' ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                  _buildMetricCard(
                    title: 'Nearby Vehicles',
                    value: '12',
                    unit: '',
                    icon: Icons.directions_car_rounded,
                    color: primaryColor,
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Start Drive Large Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.liveMap);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0088FF),
                    foregroundColor: Colors.white,
                    elevation: 8,
                    shadowColor: const Color(0xFF0088FF).withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_arrow_rounded, size: 28),
                      SizedBox(width: 8),
                      Text(
                        'Start Drive',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF112240),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: const TextStyle(
                    color: Color(0xFF8892B0),
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF8892B0),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
