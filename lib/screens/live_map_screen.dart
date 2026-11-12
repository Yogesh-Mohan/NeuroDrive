import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../core/constants/app_routes.dart';
import '../core/services/location_service.dart';
import '../core/services/safety_engine.dart';
import '../core/services/notification_service.dart';
import '../core/models/trip_model.dart';
import '../core/services/trip_service.dart';
import '../widgets/sos_dialog_helper.dart';
import 'trip_details_screen.dart';
import '../widgets/copilot_sheet.dart';

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

  // Destination & In-Drive Copilot Tracking
  String? _destinationName;
  LatLng? _destinationLatLng;
  double? _distanceRemainingKm;
  double? _etaMinutes;
  int _alertCount = 0;
  final List<String> _recentAlerts = [];

  // Preset Popular Destinations
  static const Map<String, LatLng> _presetDestinations = {
    'Chennai Airport': LatLng(12.9941, 80.1709),
    'Marina Beach': LatLng(13.0499, 80.2824),
    'Chennai Central': LatLng(13.0827, 80.2754),
    'Tambaram Station': LatLng(12.9249, 80.1479),
    'OMR IT Corridor': LatLng(12.8797, 80.2268),
  };

  void _setDestination(String name, LatLng latLng) {
    setState(() {
      _destinationName = name;
      _destinationLatLng = latLng;
      _updateEta();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Destination set: $name'),
        backgroundColor: const Color(0xFF00E5FF),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _clearDestination() {
    setState(() {
      _destinationName = null;
      _destinationLatLng = null;
      _distanceRemainingKm = null;
      _etaMinutes = null;
    });
  }

  void _updateEta() {
    if (_destinationLatLng == null) return;
    final distMeters = Geolocator.distanceBetween(
      _userPos.latitude,
      _userPos.longitude,
      _destinationLatLng!.latitude,
      _destinationLatLng!.longitude,
    );
    final distKm = distMeters / 1000.0;
    // Estimate ETA using current speed or default 35 km/h urban speed
    final effectiveSpeed = _currentSpeedKmh > 10.0 ? _currentSpeedKmh : 35.0;
    final hours = distKm / effectiveSpeed;
    final mins = (hours * 60.0).clamp(1.0, 1000.0);

    setState(() {
      _distanceRemainingKm = distKm;
      _etaMinutes = mins;
    });
  }

  void _openCopilotSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CopilotSheet(
        currentLocationName: null,
        latitude: _userPos.latitude,
        longitude: _userPos.longitude,

        destinationName: _destinationName,
        distanceRemainingKm: _distanceRemainingKm,
        etaMinutes: _etaMinutes,
        currentSpeedKmh: _currentSpeedKmh,
        alertCount: _alertCount,
        recentAlerts: _recentAlerts,
      ),
    );
  }

  // Trip Tracking Variables
  final TripService _tripService = TripService();
  bool _isSavingTrip = false;
  DateTime? _startTime;
  double _totalDistanceMeters = 0.0;
  Timer? _durationTimer;
  Duration _currentDuration = Duration.zero;
  Position? _startPosition;
  bool _isFixingLocation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startDriveAutomatically();
    });
  }

  @override
  void dispose() {
    if (_isDriveModeOn && !_isSavingTrip) {
      _saveTrip();
    }
    _positionStreamSubscription?.cancel();
    _durationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _startDriveAutomatically() async {
    if (_isDriveModeOn) return;

    setState(() {
      _gpsStatus = 'Fixing Location...';
      _isFixingLocation = true;
    });

    final hasPermission = await _locationService.handlePermissions();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _gpsStatus = 'Permission Denied';
          _isFixingLocation = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission required for Drive Mode'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    // Acquire GPS location
    final initialPos = await _locationService.getCurrentLocation();
    if (initialPos != null && mounted) {
      _updateLocationState(initialPos);
      _recenterMap();
    }

    if (!mounted) return;

    setState(() {
      _isDriveModeOn = true;
      _followUser = true;
      _gpsStatus = 'Connected';
      _isFixingLocation = false;
      // Reset Trip
      _startTime = DateTime.now();
      _totalDistanceMeters = 0.0;
      _currentDuration = Duration.zero;
      _startPosition = initialPos;
    });

    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentDuration = DateTime.now().difference(_startTime!);
        });
      }
    });

    // Start continuous listening
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = _locationService.getLocationStream()?.listen(
      (Position position) {
        _updateLocationState(position);
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _gpsStatus = 'Error/Lost Signal';
          });
        }
      },
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
              SizedBox(width: 10),
              Text('Location fixed. Drive Mode started!'),
            ],
          ),
          backgroundColor: Color(0xFF112240),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
      await _startDriveAutomatically();
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
    NotificationService().handleSafetyStatus(
      status,
      currentPosition: position,
    );

    if (status.riskLevel == RiskLevel.warning || status.riskLevel == RiskLevel.critical) {
      _alertCount++;
      _recentAlerts.add("[${status.riskLevel.name.toUpperCase()}] ${status.message}");
      if (_recentAlerts.length > 10) _recentAlerts.removeAt(0);
    }

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
    _updateEta();

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

  Future<TripModel?> _saveTrip() async {
    if (_isSavingTrip) return null; // Prevent duplicate concurrent saves

    final pos = _currentPosition ?? _startPosition;
    final startLat = _startPosition?.latitude ?? pos?.latitude ?? _userPos.latitude;
    final startLng = _startPosition?.longitude ?? pos?.longitude ?? _userPos.longitude;
    final endLat = _currentPosition?.latitude ?? pos?.latitude ?? _userPos.latitude;
    final endLng = _currentPosition?.longitude ?? pos?.longitude ?? _userPos.longitude;

    if (_startTime == null) {
      debugPrint('Trip has no startTime, cannot save.');
      return null;
    }

    final durationSec = _currentDuration.inSeconds > 0
        ? _currentDuration.inSeconds
        : DateTime.now().difference(_startTime!).inSeconds;

    _isSavingTrip = true;
    final now = DateTime.now();

    try {
      final trip = await _tripService.saveCompletedTrip(
        startTime: _startTime!,
        endTime: now,
        distanceMeters: _totalDistanceMeters,
        durationSeconds: durationSec > 0 ? durationSec : 1,
        startLat: startLat,
        startLng: startLng,
        endLat: endLat,
        endLng: endLng,
        avgSpeedKmh: _currentSpeedKmh,
      );

      if (mounted) {
        final syncMsg = trip.isSynced
            ? 'Trip saved to Cloud Firestore!'
            : 'Trip saved locally in History (sync pending)!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncMsg),
            backgroundColor: const Color(0xFF112240),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'AI REPORT',
              textColor: const Color(0xFF00D2FF),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TripDetailsScreen(trip: trip),
                  ),
                );
              },
            ),
          ),
        );
      }
      return trip;
    } catch (e) {
      debugPrint('Failed to save trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trip saved locally. Notice: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: const Color(0xFF112240),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    } finally {
      _isSavingTrip = false;
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  Future<void> _handleBackPress() async {
    if (_isDriveModeOn) {
      _positionStreamSubscription?.cancel();
      _durationTimer?.cancel();
      await _saveTrip();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackPress();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBackPress,
        ),
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

            // Top Fixing Location Feedback Banner
            if (_isFixingLocation)
              Positioned(
                top: 16,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF112240).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00D2FF), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00D2FF).withValues(alpha: 0.35),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D2FF)),
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Fixing GPS Location...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Top Destination Bar (NeuroCopilot)
            Positioned(
              top: 16,
              left: 16,
              right: 170, // Leave space for GPS status on right
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1B2A).withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.navigation_rounded, color: Color(0xFF00E5FF), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _destinationName != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'TO: ',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  ' km • ETA m',
                                  style: const TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : const Text(
                              'Destination: Set Dest',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.add_location_alt_rounded, color: Color(0xFF00E5FF), size: 20),
                      padding: EdgeInsets.zero,
                      tooltip: 'Choose Destination',
                      color: const Color(0xFF132238),
                      onSelected: (val) {
                        if (val == 'CLEAR') {
                          _clearDestination();
                        } else if (_presetDestinations.containsKey(val)) {
                          _setDestination(val, _presetDestinations[val]!);
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(
                          enabled: false,
                          child: Text(
                            'Select Destination:',
                            style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                          ),
                        ),
                        ..._presetDestinations.entries.map(
                          (e) => PopupMenuItem(
                            value: e.key,
                            child: Text(e.key, style: const TextStyle(color: Colors.white, fontSize: 13)),
                          ),
                        ),
                        if (_destinationName != null)
                          const PopupMenuItem(
                            value: 'CLEAR',
                            child: Text('Clear Destination', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
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

            // Floating Control Buttons (Recenter & Emergency SOS)
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
                  const SizedBox(height: 12),
                  // NeuroCopilot AI Floating Trigger
                  FloatingActionButton(
                    heroTag: 'copilot_live_btn',
                    onPressed: _openCopilotSheet,
                    backgroundColor: const Color(0xFF00E5FF),
                    elevation: 8,
                    child: const Icon(Icons.psychology_rounded, color: Color(0xFF0D1B2A), size: 30),
                  ),
                  const SizedBox(height: 12),
                  FloatingActionButton(
                    heroTag: 'sos_live_map_btn',
                    onPressed: () => SosDialogHelper.showSosConfirmationDialog(
                      context,
                      currentPosition: _currentPosition,
                    ),
                    backgroundColor: const Color(0xFFFF5252),
                    elevation: 6,
                    child: const Icon(Icons.emergency_share_rounded, color: Colors.white, size: 28),
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
                    if (_isDriveModeOn) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            await _toggleDriveMode();
                          },
                          icon: const Icon(Icons.stop_circle_rounded, color: Colors.white, size: 22),
                          label: const Text(
                            'END DRIVE & SAVE TRIP',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF4D4D),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                    ],
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
