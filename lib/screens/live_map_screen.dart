import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/constants/app_routes.dart';
import '../core/services/location_service.dart';
import '../core/services/safety_engine.dart';
import '../core/services/notification_service.dart';

class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionStreamSubscription;

  LatLng _userPos = const LatLng(13.0827, 80.2707); // Default fallback coords
  bool _isDriveModeOn = false;
  bool _followUser = true;
  String _gpsStatus = 'Inactive';
  Position? _currentPosition;
  double _currentSpeedKmh = 0.0;
  double _heading = 0.0;
  
  final SafetyEngine _safetyEngine = SafetyEngine();
  SafetyStatus _currentSafetyStatus = SafetyStatus(
    riskLevel: RiskLevel.safe, 
    message: 'Initializing...',
  );

  // Trip Tracking Variables
  DateTime? _startTime;
  double _totalDistanceMeters = 0.0;
  Timer? _durationTimer;
  Duration _currentDuration = Duration.zero;
  Position? _startPosition;

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _durationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _toggleDriveMode() async {
    if (_isDriveModeOn) {
      // Turn OFF
      _positionStreamSubscription?.cancel();
      _durationTimer?.cancel();
      
      // Save Trip
      await _saveTrip();

      setState(() {
        _isDriveModeOn = false;
        _gpsStatus = 'Inactive';
        _currentSpeedKmh = 0.0;
        _heading = 0.0;
      });
    } else {
      // Turn ON
      setState(() {
        _gpsStatus = 'Connecting...';
      });

      final hasPermission = await _locationService.handlePermissions();
      if (!hasPermission) {
        setState(() {
          _gpsStatus = 'Permission Denied';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission required for Drive Mode')),
          );
        }
        return;
      }

      setState(() {
        _isDriveModeOn = true;
        _followUser = true;
        _gpsStatus = 'Connected';
        // Reset Trip
        _startTime = DateTime.now();
        _totalDistanceMeters = 0.0;
        _currentDuration = Duration.zero;
        _startPosition = null;
      });

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _currentDuration = DateTime.now().difference(_startTime!);
          });
        }
      });

      // Get initial location quickly
      final initialPos = await _locationService.getCurrentLocation();
      if (initialPos != null) {
        _updateLocationState(initialPos);
        _recenterMap();
      }

      // Start continuous listening
      _positionStreamSubscription = _locationService.getLocationStream()?.listen(
        (Position position) {
          _updateLocationState(position);
        },
        onError: (error) {
          setState(() {
            _gpsStatus = 'Error/Lost Signal';
          });
        },
      );
    }
  }

  void _updateLocationState(Position position) {
    if (!mounted) return;
    final speed = _locationService.calculateSpeedKmh(position, _currentPosition);
    
    double addedDistance = 0.0;
    if (_isDriveModeOn && _currentPosition != null) {
      addedDistance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        position.latitude,
        position.longitude,
      );
    }
    
    final status = _safetyEngine.evaluateRisk(currentEgoPosition: position);
    NotificationService().handleSafetyStatus(status);

    setState(() {
      _startPosition ??= position;
      _totalDistanceMeters += addedDistance;
      _currentPosition = position;
      _userPos = LatLng(position.latitude, position.longitude);
      _currentSpeedKmh = speed < 1.0 ? 0.0 : speed;
      _heading = position.heading;
      _gpsStatus = 'Connected';
      _currentSafetyStatus = status;
    });

    if (_followUser && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _userPos,
            zoom: 17.5,
            bearing: _heading,
            tilt: 45.0, // Tilted view for navigation feel
          ),
        ),
      );
    }
  }

  void _recenterMap() {
    setState(() {
      _followUser = true;
    });
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _userPos,
            zoom: 17.5,
            bearing: _heading,
            tilt: 45.0,
          ),
        ),
      );
    }
  }

  Future<void> _saveTrip() async {
    if (_startPosition == null || _currentPosition == null || _startTime == null) return;
    
    // Lowered to 5 meters for testing purposes (previously 50)
    if (_totalDistanceMeters < 5 && _currentDuration.inSeconds < 10) return; 

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return; // Don't save if not logged in

      final prefs = await SharedPreferences.getInstance();
      List<String> tripsStr = prefs.getStringList('neurodrive_trips_$uid') ?? [];
      
      final tripData = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'startTime': _startTime!.toIso8601String(),
        'endTime': DateTime.now().toIso8601String(),
        'durationSeconds': _currentDuration.inSeconds,
        'distanceMeters': _totalDistanceMeters,
        'startLat': _startPosition!.latitude,
        'startLng': _startPosition!.longitude,
        'endLat': _currentPosition!.latitude,
        'endLng': _currentPosition!.longitude,
      };

      tripsStr.add(json.encode(tripData));
      await prefs.setStringList('neurodrive_trips_$uid', tripsStr);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip saved successfully!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Failed to save trip: $e');
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('NeuroDrive', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _toggleDriveMode,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isDriveModeOn ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isDriveModeOn ? Colors.greenAccent : Colors.redAccent,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.circle, color: _isDriveModeOn ? Colors.greenAccent : Colors.redAccent, size: 8),
                    const SizedBox(width: 6),
                    Text(
                      _isDriveModeOn ? 'Drive: ON' : 'Drive: OFF',
                      style: TextStyle(
                        color: _isDriveModeOn ? Colors.greenAccent : Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.alertHistory),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Google Map Area
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _userPos,
                zoom: 16.5,
              ),
              onMapCreated: (controller) {
                _mapController = controller;
              },
              onCameraMoveStarted: () {
                if (_isDriveModeOn) {
                  setState(() {
                    _followUser = false;
                  });
                }
              },
              zoomControlsEnabled: false,
              myLocationEnabled: false, // Using custom marker for better styling
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: false,
              markers: {
                if (_currentPosition != null || !_isDriveModeOn)
                  Marker(
                    markerId: const MarkerId('user_vehicle'),
                    position: _userPos,
                    rotation: _heading,
                    anchor: const Offset(0.5, 0.5),
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                  ),
              },
            ),

            // Top GPS Status & Safety Warning
            Positioned(
              top: 16,
              right: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF112240).withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _gpsStatus == 'Connected' ? Icons.gps_fixed_rounded : Icons.gps_off_rounded,
                          color: _gpsStatus == 'Connected' ? Colors.greenAccent : Colors.white54,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'GPS: $_gpsStatus',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  if (_isDriveModeOn && _currentSafetyStatus.message.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _currentSafetyStatus.riskLevel == RiskLevel.critical
                            ? Colors.red.withValues(alpha: 0.9)
                            : _currentSafetyStatus.riskLevel == RiskLevel.warning
                                ? Colors.orange.withValues(alpha: 0.9)
                                : const Color(0xFF112240).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _currentSafetyStatus.riskLevel == RiskLevel.critical
                              ? Colors.redAccent
                              : _currentSafetyStatus.riskLevel == RiskLevel.warning
                                  ? Colors.orangeAccent
                                  : Colors.greenAccent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        _currentSafetyStatus.message,
                        style: TextStyle(
                          color: _currentSafetyStatus.riskLevel == RiskLevel.safe ? Colors.white70 : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Floating Control Buttons (Recenter)
            Positioned(
              right: 16,
              top: 110,
              child: Column(
                children: [
                  if (_isDriveModeOn && !_followUser)
                    FloatingActionButton.small(
                      heroTag: 'recenter_btn',
                      onPressed: _recenterMap,
                      backgroundColor: primaryColor,
                      child: const Icon(Icons.my_location_rounded, color: Colors.white),
                    )
                  else
                    FloatingActionButton.small(
                      heroTag: 'recenter_btn',
                      onPressed: _recenterMap,
                      backgroundColor: const Color(0xFF112240),
                      child: const Icon(Icons.my_location_rounded, color: primaryColor),
                    ),
                ],
              ),
            ),

            // Bottom Dashboard UI
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A192F).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildDashboardMetric(
                          _isDriveModeOn ? _currentSpeedKmh.toStringAsFixed(0) : '--',
                          'km/h',
                          'SPEED',
                          _isDriveModeOn ? Colors.white : Colors.white54,
                        ),
                        Container(height: 40, width: 1, color: Colors.white12),
                        _buildDashboardMetric(
                          _isDriveModeOn ? (_totalDistanceMeters / 1000).toStringAsFixed(1) : '--',
                          'km',
                          'DISTANCE',
                          _isDriveModeOn ? Colors.white : Colors.white54,
                        ),
                        Container(height: 40, width: 1, color: Colors.white12),
                        _buildDashboardMetric(
                          _isDriveModeOn ? _formatDuration(_currentDuration) : '--',
                          '',
                          'TIME',
                          _isDriveModeOn ? Colors.white : Colors.white54,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardMetric(String value, String unit, String label, Color valueColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: TextStyle(color: valueColor, fontSize: 32, fontWeight: FontWeight.bold)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 14)),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 11, letterSpacing: 1.2)),
      ],
    );
  }
}
