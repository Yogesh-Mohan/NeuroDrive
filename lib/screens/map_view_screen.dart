import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../core/services/location_service.dart';
import '../core/services/safety_engine.dart';
import '../core/services/notification_service.dart';
import '../core/services/trip_service.dart';
import '../core/models/road_damage_model.dart';
import '../core/services/road_damage_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../widgets/copilot_sheet.dart';
import '../widgets/neural_copilot_orb.dart';
import 'trip_details_screen.dart';
import '../core/models/v2v_telemetry.dart';
import '../core/services/v2v_radar_service.dart';
import 'v2v_radar_screen.dart';

class SearchResult {
  final LatLng latLng;
  final String title;
  final String? subtitle;
  final double? distanceKm;

  const SearchResult({
    required this.latLng,
    required this.title,
    this.subtitle,
    this.distanceKm,
  });
}

class RouteProgressResult {
  final List<LatLng> remainingPoints;
  final int newProgressIndex;
  final double remainingDistanceMeters;
  final bool hasArrived;

  const RouteProgressResult({
    required this.remainingPoints,
    required this.newProgressIndex,
    required this.remainingDistanceMeters,
    required this.hasArrived,
  });
}

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  /// Dynamically computes remaining forward route points from the vehicle's position to destination,
  /// trimming away the traversed route polyline behind the vehicle.
  static RouteProgressResult computeRemainingRoutePoints({
    required LatLng vehiclePos,
    required List<LatLng> fullRoute,
    int currentProgressIndex = 0,
    double maxCorridorMeters = 150.0,
    double arrivalThresholdMeters = 35.0,
  }) {
    if (fullRoute.isEmpty) {
      return const RouteProgressResult(
        remainingPoints: [],
        newProgressIndex: 0,
        remainingDistanceMeters: 0.0,
        hasArrived: true,
      );
    }

    if (fullRoute.length == 1) {
      final d = Geolocator.distanceBetween(
        vehiclePos.latitude,
        vehiclePos.longitude,
        fullRoute.first.latitude,
        fullRoute.first.longitude,
      );
      if (d <= arrivalThresholdMeters) {
        return const RouteProgressResult(
          remainingPoints: [],
          newProgressIndex: 0,
          remainingDistanceMeters: 0.0,
          hasArrived: true,
        );
      }
      return RouteProgressResult(
        remainingPoints: [vehiclePos, fullRoute.first],
        newProgressIndex: 0,
        remainingDistanceMeters: d,
        hasArrived: false,
      );
    }

    // Check if vehicle has arrived near the final destination
    final distToDestination = Geolocator.distanceBetween(
      vehiclePos.latitude,
      vehiclePos.longitude,
      fullRoute.last.latitude,
      fullRoute.last.longitude,
    );

    if (distToDestination <= arrivalThresholdMeters) {
      return RouteProgressResult(
        remainingPoints: const [],
        newProgressIndex: fullRoute.length - 1,
        remainingDistanceMeters: 0.0,
        hasArrived: true,
      );
    }

    final int n = fullRoute.length;
    final int safeCurrentIdx = currentProgressIndex.clamp(0, n - 2);

    // Search window: check slightly behind to prevent issues from GPS jitter,
    // and up to 50 segments ahead.
    final int startSeg = math.max(0, safeCurrentIdx - 2);
    final int endSeg = math.min(n - 2, safeCurrentIdx + 50);

    int bestSegmentIndex = safeCurrentIdx;
    double minScore = double.infinity;
    double bestT = 0.0;
    double bestSegDist = double.infinity;

    for (int i = startSeg; i <= endSeg; i++) {
      final pA = fullRoute[i];
      final pB = fullRoute[i + 1];

      final latRad = (pA.latitude + pB.latitude) / 2.0 * (math.pi / 180.0);
      const metersPerDegLat = 111132.95;
      final metersPerDegLng = 111412.84 * math.cos(latRad);

      final dx = (pB.longitude - pA.longitude) * metersPerDegLng;
      final dy = (pB.latitude - pA.latitude) * metersPerDegLat;
      final segLenSq = dx * dx + dy * dy;

      double t = 0.0;
      double projLat = pA.latitude;
      double projLng = pA.longitude;

      if (segLenSq > 1e-4) {
        final wx = (vehiclePos.longitude - pA.longitude) * metersPerDegLng;
        final wy = (vehiclePos.latitude - pA.latitude) * metersPerDegLat;
        t = (wx * dx + wy * dy) / segLenSq;
        final tClamped = t.clamp(0.0, 1.0);
        projLat = pA.latitude + tClamped * (pB.latitude - pA.latitude);
        projLng = pA.longitude + tClamped * (pB.longitude - pA.longitude);
      }

      final distToSeg = Geolocator.distanceBetween(
        vehiclePos.latitude,
        vehiclePos.longitude,
        projLat,
        projLng,
      );

      // Distance penalty based on distance from currentProgressIndex
      // Prevents premature skipping of hairpin turns or parallel highways
      final indexDiff = (i - safeCurrentIdx).abs();
      final score = distToSeg + (indexDiff * 3.0);

      if (score < minScore) {
        minScore = score;
        bestSegmentIndex = i;
        bestT = t;
        bestSegDist = distToSeg;
      }
    }

    int newProgressIndex = safeCurrentIdx;
    List<LatLng> remaining = [];

    // If vehicle is within corridor, advance progress index
    if (bestSegDist <= maxCorridorMeters) {
      if (bestT >= 0.85) {
        newProgressIndex = math.min(n - 1, bestSegmentIndex + 1);
      } else {
        newProgressIndex = bestSegmentIndex;
      }
    } else {
      // Off-corridor: retain existing progress index
      newProgressIndex = safeCurrentIdx;
    }

    // Determine forward route coordinates starting right from vehicle's real-time position
    if (newProgressIndex >= n - 1) {
      if (distToDestination <= arrivalThresholdMeters * 1.5) {
        return RouteProgressResult(
          remainingPoints: const [],
          newProgressIndex: n - 1,
          remainingDistanceMeters: 0.0,
          hasArrived: true,
        );
      }
      remaining = [vehiclePos, fullRoute.last];
    } else {
      final int forwardWaypointIdx = (bestT >= 0.85 && bestSegmentIndex + 2 < n)
          ? bestSegmentIndex + 2
          : bestSegmentIndex + 1;

      remaining = [
        vehiclePos,
        ...fullRoute.sublist(math.min(forwardWaypointIdx, n - 1)),
      ];
    }

    // Compute remaining distance
    double remainingDistance = 0.0;
    for (int i = 0; i < remaining.length - 1; i++) {
      remainingDistance += Geolocator.distanceBetween(
        remaining[i].latitude,
        remaining[i].longitude,
        remaining[i + 1].latitude,
        remaining[i + 1].longitude,
      );
    }

    return RouteProgressResult(
      remainingPoints: remaining,
      newProgressIndex: newProgressIndex,
      remainingDistanceMeters: remainingDistance,
      hasArrived: false,
    );
  }

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> with TickerProviderStateMixin {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionStreamSubscription;

  // In-Drive Forward Radar HUD
  bool _isRadarOverlayOn = true;
  late final AnimationController _radarSweepController;

  // Real GPS coordinate
  LatLng? _userPos;
  Position? _currentPosition;
  Position? _startPosition;

  bool _followUser = true;
  String _gpsStatus = 'Getting current location...';
  double _heading = 0.0;
  double _currentSpeedKmh = 0.0;

  // Route Planning Variables
  final Set<Polyline> _polylines = {};
  Marker? _destinationMarker;
  String? _routeDistance;
  String? _routeDuration;
  String? _destinationTitle;
  bool _isFetchingRoute = false;
  int _currentRouteProgressIndex = 0;
  double? _initialRouteDistanceMeters;
  double? _initialRouteDurationSeconds;

  // Road Damage Heatmap & Advance Alert Variables
  final RoadDamageService _roadDamageService = RoadDamageService();
  List<RoadDamageModel> _allRoadDamage = [];
  List<RoadDamageModel> _routeDamage = [];
  final Set<Circle> _damageHeatmapCircles = {};
  final Set<Marker> _damageMarkers = {};
  bool _showDamageHeatmap = true;
  final Set<String> _alertedDamageIds = {};
  RoadDamageModel? _activeAdvanceAlert;
  Timer? _advanceAlertDismissTimer;
  final FlutterTts _flutterTts = FlutterTts();
  List<LatLng> _currentRoutePolylineCoordinates = [];

  // Start Location Selection Variables
  LatLng? _customStartPos;
  String? _startLocationTitle;
  Marker? _startMarker;

  // Driving & Trip Tracking
  bool _isDriveModeOn = false;
  bool _isSavingTrip = false;
  DateTime? _startTime;
  double _totalDistanceMeters = 0.0;
  Timer? _durationTimer;
  Duration _currentDuration = Duration.zero;

  final TripService _tripService = TripService();
  final SafetyEngine _safetyEngine = SafetyEngine();
  SafetyStatus _currentSafetyStatus = SafetyStatus(
    riskLevel: RiskLevel.safe,
    message: 'Ready to drive',
  );

  @override
  void initState() {
    super.initState();
    _radarSweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    V2VRadarService().initialize(initialMode: V2VConnectionMode.localEsp32);
    _startLocationTracking();
    _loadRoadDamageDataset();
    _initTts();
  }

  void _initTts() {
    try {
      _flutterTts.setSpeechRate(0.48);
      _flutterTts.setVolume(1.0);
    } catch (_) {}
  }

  Future<void> _loadRoadDamageDataset() async {
    try {
      final records = await _roadDamageService.getRoadDamageRecords();
      if (mounted) {
        setState(() {
          _allRoadDamage = records;
        });
        debugPrint('[MapViewScreen] Loaded ${_allRoadDamage.length} active road damage records.');
        _updateHeatmapAndMarkers();
      }
    } catch (e) {
      debugPrint('[MapViewScreen] Road damage load note: $e');
    }
  }

  @override
  void dispose() {
    _radarSweepController.dispose();
    _positionStreamSubscription?.cancel();
    _durationTimer?.cancel();
    _advanceAlertDismissTimer?.cancel();
    _flutterTts.stop();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    final hasPermission = await _locationService.handlePermissions();
    if (!hasPermission) {
      if (mounted) {
        setState(() {
          _gpsStatus = 'Location permission required';
        });
      }
      return;
    }

    final initialPos = await _locationService.getCurrentLocation();
    if (initialPos != null && mounted) {
      _updateLocationState(initialPos);
    }

    _positionStreamSubscription = _locationService.getLocationStream()?.listen(
      (Position position) {
        if (mounted) {
          _updateLocationState(position);
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _gpsStatus = 'GPS is disabled';
          });
        }
      },
    );
  }

  void _updateLocationState(Position position) {
    final speed = _locationService.calculateSpeedKmh(
      position,
      _currentPosition,
    );

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
    if (_isDriveModeOn) {
      NotificationService().handleSafetyStatus(
        status,
        currentPosition: position,
      );
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

    // Check upcoming road damage hazards along active navigation route
    if (_routeDamage.isNotEmpty && _userPos != null) {
      final upcoming = _roadDamageService.checkUpcomingHazard(
        vehiclePos: _userPos!,
        routeHazards: _routeDamage,
        alreadyAlertedIds: _alertedDamageIds,
        warningDistanceMeters: 250.0,
      );

      if (upcoming != null) {
        _triggerAdvanceDamageAlert(upcoming);
      }
    }

    // Dynamic Route Polyline Trimming:
    // As vehicle moves forward, clear traversed path behind vehicle so only
    // the remaining route ahead is rendered (turn-by-turn navigation style)
    if (_isDriveModeOn &&
        _currentRoutePolylineCoordinates.isNotEmpty &&
        _userPos != null) {
      _trimTraversedRoutePolyline(_userPos!, _currentSpeedKmh);
    }

    if (_followUser && _mapController != null) {
      try {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: _userPos!,
              zoom: _isDriveModeOn ? 18.0 : 17.5,
              bearing: _heading,
              tilt: _isDriveModeOn ? 45.0 : 0.0,
            ),
          ),
        );
      } catch (e) {
        // Camera update safely skipped if screen is locked or app is in background
        debugPrint('[MapViewScreen] Background camera update skipped: $e');
      }
    }
  }

  void _trimTraversedRoutePolyline(LatLng userPos, double currentSpeedKmh) {
    if (_currentRoutePolylineCoordinates.length < 2) return;

    final result = MapViewScreen.computeRemainingRoutePoints(
      vehiclePos: userPos,
      fullRoute: _currentRoutePolylineCoordinates,
      currentProgressIndex: _currentRouteProgressIndex,
    );

    _currentRouteProgressIndex = result.newProgressIndex;

    if (result.hasArrived || result.remainingPoints.isEmpty) {
      setState(() {
        _polylines.removeWhere((p) => p.polylineId == const PolylineId('route'));
        _routeDistance = '0 m';
        _routeDuration = 'Arrived';
      });
      try {
        _flutterTts.speak('You have arrived at your destination.');
      } catch (_) {}
      return;
    }

    final dist = result.remainingDistanceMeters;
    final formattedDist = dist < 1000
        ? '${dist.round()} m'
        : '${(dist / 1000).toStringAsFixed(1)} km';

    String? formattedDuration;
    if (_initialRouteDistanceMeters != null &&
        _initialRouteDistanceMeters! > 0 &&
        _initialRouteDurationSeconds != null) {
      final ratio = (dist / _initialRouteDistanceMeters!).clamp(0.0, 1.5);
      final remainingSec = (_initialRouteDurationSeconds! * ratio).round();
      final int mins = (remainingSec / 60).round();
      if (mins < 1) {
        formattedDuration = '1 min';
      } else if (mins < 60) {
        formattedDuration = '$mins min';
      } else {
        final hours = mins ~/ 60;
        final remainingMins = mins % 60;
        formattedDuration = '${hours}h ${remainingMins}m';
      }
    }

    setState(() {
      _routeDistance = formattedDist;
      if (formattedDuration != null) {
        _routeDuration = formattedDuration;
      }
      _polylines.removeWhere((p) => p.polylineId == const PolylineId('route'));
      if (result.remainingPoints.length >= 2) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            color: const Color(0xFF00D2FF),
            width: 6,
            points: result.remainingPoints,
          ),
        );
      }
    });
  }

  void _recenterMap() {
    if (_userPos == null) return;

    setState(() {
      _followUser = true;
    });

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _userPos!,
            zoom: _isDriveModeOn ? 18.0 : 17.5,
            bearing: _heading,
            tilt: _isDriveModeOn ? 45.0 : 0.0,
          ),
        ),
      );
    }
  }

  void _clearRoute() {
    ScaffoldMessenger.of(context).clearSnackBars();
    setState(() {
      _polylines.clear();
      _destinationMarker = null;
      _startMarker = null;
      _customStartPos = null;
      _startLocationTitle = null;
      _damageHeatmapCircles.clear();
      _damageMarkers.clear();
      _routeDamage.clear();
      _alertedDamageIds.clear();
      _activeAdvanceAlert = null;
      _routeDistance = null;
      _routeDuration = null;
      _destinationTitle = null;
      _currentRoutePolylineCoordinates.clear();
      _currentRouteProgressIndex = 0;
      _initialRouteDistanceMeters = null;
      _initialRouteDurationSeconds = null;
    });
    _updateHeatmapAndMarkers();
    _recenterMap();
  }

  Future<void> _startDriving() async {
    ScaffoldMessenger.of(context).clearSnackBars();
    if (_destinationMarker == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose a destination before starting the drive.'),
        ),
      );
      return;
    }

    if (_currentPosition == null) {
      final position = await _locationService.getCurrentLocation();
      if (!mounted || position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Waiting for GPS location. Please enable location and try again.',
              ),
            ),
          );
        }
        return;
      }
      _updateLocationState(position);
    }

    setState(() {
      _isDriveModeOn = true;
      _isRadarOverlayOn = true;
      _followUser = true;
      _startTime = DateTime.now();
      _totalDistanceMeters = 0.0;
      _currentDuration = Duration.zero;
      _startPosition = _currentPosition;
      _currentRouteProgressIndex = 0;
      _startMarker = null;
    });

    if (_userPos != null && _currentRoutePolylineCoordinates.isNotEmpty) {
      _trimTraversedRoutePolyline(_userPos!, _currentSpeedKmh);
    }

    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentDuration = DateTime.now().difference(_startTime!);
        });
      }
    });

    if (_userPos != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _userPos!,
            zoom: 18.0,
            bearing: _heading,
            tilt: 45.0,
          ),
        ),
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.navigation_rounded, color: Color(0xFF00D2FF)),
            const SizedBox(width: 8),
            Text(
              _destinationTitle != null
                  ? 'Navigating to $_destinationTitle'
                  : 'Drive mode active!',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF112240),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _stopDrivingAndSave() async {
    if (_isSavingTrip) return;

    _durationTimer?.cancel();

    final pos = _currentPosition ?? _startPosition;
    final startLat =
        _startPosition?.latitude ??
        pos?.latitude ??
        _userPos?.latitude ??
        13.0827;
    final startLng =
        _startPosition?.longitude ??
        pos?.longitude ??
        _userPos?.longitude ??
        80.2707;
    final endLat =
        _currentPosition?.latitude ??
        pos?.latitude ??
        _userPos?.latitude ??
        13.0827;
    final endLng =
        _currentPosition?.longitude ??
        pos?.longitude ??
        _userPos?.longitude ??
        80.2707;

    if (_startTime == null) {
      setState(() {
        _isDriveModeOn = false;
        _currentSpeedKmh = 0.0;
      });
      return;
    }

    final durationSec = _currentDuration.inSeconds > 0
        ? _currentDuration.inSeconds
        : DateTime.now().difference(_startTime!).inSeconds;

    setState(() {
      _isSavingTrip = true;
    });

    try {
      final now = DateTime.now();
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
            : 'Trip saved locally (synced)!';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncMsg),
            backgroundColor: const Color(0xFF112240),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
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
    } catch (e) {
      debugPrint('Error saving trip: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trip save notice: ${e.toString()}'),
            backgroundColor: const Color(0xFF112240),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingTrip = false;
          _isDriveModeOn = false;
          _currentSpeedKmh = 0.0;
        });

        // Reset camera angle to regular top-down
        if (_userPos != null && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: _userPos!,
                zoom: 17.0,
                bearing: _heading,
                tilt: 0.0,
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _fetchAndDrawRoute(
    LatLng destination, {
    String? title,
    LatLng? startPoint,
    String? startTitle,
  }) async {
    final effectiveStart = startPoint ?? _customStartPos ?? _userPos;
    if (effectiveStart == null) return;

    setState(() {
      _isFetchingRoute = true;
      _polylines.clear();
      _damageHeatmapCircles.clear();
      _damageMarkers.clear();
      _routeDamage.clear();
      _alertedDamageIds.clear();
      _activeAdvanceAlert = null;
      _destinationTitle = title;
      if (startTitle != null) {
        _startLocationTitle = startTitle;
      }
      if (startPoint != null) {
        _customStartPos = startPoint;
        _startMarker = Marker(
          markerId: const MarkerId('start_location'),
          position: startPoint,
          infoWindow: InfoWindow(title: startTitle ?? 'Start Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        );
      }
      _destinationMarker = Marker(
        markerId: const MarkerId('destination'),
        position: destination,
        infoWindow: InfoWindow(title: title ?? 'Destination'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      );
      _routeDistance = null;
      _routeDuration = null;
    });

    try {
      final double directDistMeters = Geolocator.distanceBetween(
        effectiveStart.latitude,
        effectiveStart.longitude,
        destination.latitude,
        destination.longitude,
      );

      // OSRM Public Driving routing
      final String url =
          'https://router.project-osrm.org/route/v1/driving/'
          '${effectiveStart.longitude},${effectiveStart.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=geojson';

      List<LatLng> polylineCoordinates = [];
      double distanceMeters = directDistMeters;
      double durationSeconds = (directDistMeters / 6.0); // Default estimate ~20km/h for short campus

      try {
        final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['routes'] != null && data['routes'].isNotEmpty) {
            final route = data['routes'][0];
            distanceMeters = route['distance'].toDouble();
            durationSeconds = route['duration'].toDouble();

            final geometry = route['geometry'];
            final List coordinates = geometry['coordinates'];
            polylineCoordinates = coordinates.map((coord) {
              return LatLng(coord[1].toDouble(), coord[0].toDouble());
            }).toList();
          }
        }
      } catch (e) {
        debugPrint('OSRM routing network notice: $e');
      }

      // Campus / Short Distance Fallback:
      // If OSRM returns too few points or cannot route inside campus (< 1.5 km), draw direct pathway
      if (polylineCoordinates.length < 2) {
        polylineCoordinates = [effectiveStart, destination];
      } else {
        // Guarantee route starts exactly at effectiveStart and ends exactly at destination marker
        if (polylineCoordinates.first != effectiveStart) {
          polylineCoordinates.insert(0, effectiveStart);
        }
        if (polylineCoordinates.last != destination) {
          polylineCoordinates.add(destination);
        }
      }

      // Format distance
      if (distanceMeters < 1000) {
        _routeDistance = '${distanceMeters.round()} m';
      } else {
        _routeDistance = '${(distanceMeters / 1000).toStringAsFixed(1)} km';
      }

      // Format duration
      final int mins = (durationSeconds / 60).round();
      if (mins < 1) {
        _routeDuration = '1 min';
      } else if (mins < 60) {
        _routeDuration = '$mins min';
      } else {
        final hours = mins ~/ 60;
        final remainingMins = mins % 60;
        _routeDuration = '${hours}h ${remainingMins}m';
      }

      _currentRoutePolylineCoordinates = polylineCoordinates;
      _initialRouteDistanceMeters = distanceMeters;
      _initialRouteDurationSeconds = durationSeconds;
      _currentRouteProgressIndex = 0;

      // Filter road damage along route within 100m corridor with guaranteed coverage
      if (_allRoadDamage.isEmpty) {
        await _loadRoadDamageDataset();
      }

      if (polylineCoordinates.isNotEmpty) {
        _routeDamage = _roadDamageService.filterDamageAlongRoute(
          routePoints: polylineCoordinates,
          allDamage: _allRoadDamage,
          corridorMeters: 100.0,
          ensureRouteCoverage: true,
        );
        for (final rd in _routeDamage) {
          if (!_allRoadDamage.any((d) => d.damageId == rd.damageId)) {
            _allRoadDamage.add(rd);
          }
        }
        debugPrint('[MapViewScreen] Filtered ${_routeDamage.length} road hazards along route (100m corridor).');
      } else {
        _routeDamage = [];
      }

      setState(() {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            color: const Color(0xFF00D2FF),
            width: 6,
            points: polylineCoordinates,
          ),
        );
      });

      if (_isDriveModeOn && _userPos != null) {
        _trimTraversedRoutePolyline(_userPos!, _currentSpeedKmh);
      }

      _updateHeatmapAndMarkers();

      // Fit map camera to show both start and destination
      if (_mapController != null && polylineCoordinates.isNotEmpty && !_isDriveModeOn) {
        double minLat = polylineCoordinates[0].latitude;
        double maxLat = polylineCoordinates[0].latitude;
        double minLng = polylineCoordinates[0].longitude;
        double maxLng = polylineCoordinates[0].longitude;

        for (var point in polylineCoordinates) {
          if (point.latitude < minLat) minLat = point.latitude;
          if (point.latitude > maxLat) maxLat = point.latitude;
          if (point.longitude < minLng) minLng = point.longitude;
          if (point.longitude > maxLng) maxLng = point.longitude;
        }

        // For very short distance (< 200m), pad bounds to prevent extreme camera zoom-in
        final double latDiff = (maxLat - minLat).abs();
        final double lngDiff = (maxLng - minLng).abs();
        if (latDiff < 0.002 || lngDiff < 0.002) {
          final centerLat = (minLat + maxLat) / 2;
          final centerLng = (minLng + maxLng) / 2;
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(centerLat, centerLng),
                zoom: 17.5,
              ),
            ),
          );
        } else {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngBounds(
              LatLngBounds(
                southwest: LatLng(minLat, minLng),
                northeast: LatLng(maxLat, maxLng),
              ),
              60.0,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isFetchingRoute = false;
        });
      }
    }
  }

  void _updateHeatmapAndMarkers() {
    _damageHeatmapCircles.clear();
    _damageMarkers.clear();

    if (!_showDamageHeatmap) {
      if (mounted) setState(() {});
      return;
    }

    // When an active route is drawn, prioritize damage along the route between start & destination!
    final bool hasActiveRoute = _currentRoutePolylineCoordinates.isNotEmpty && _routeDamage.isNotEmpty;
    final damageList = hasActiveRoute ? _routeDamage : _allRoadDamage;
    if (damageList.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    final routeDamageIds = _routeDamage.map((d) => d.damageId).toSet();

    for (final damage in damageList) {
      final isOnCurrentRoute = routeDamageIds.contains(damage.damageId);
      Color circleColor;
      BitmapDescriptor markerHue;
      double outerRadius;
      double innerRadius;

      switch (damage.severity.toLowerCase()) {
        case 'high':
          circleColor = Colors.redAccent;
          markerHue = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
          outerRadius = isOnCurrentRoute ? 3000.0 : 2200.0;
          innerRadius = isOnCurrentRoute ? 800.0 : 500.0;
          break;
        case 'medium':
        case 'moderate':
          circleColor = Colors.orangeAccent;
          markerHue = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
          outerRadius = isOnCurrentRoute ? 2400.0 : 1600.0;
          innerRadius = isOnCurrentRoute ? 600.0 : 350.0;
          break;
        default:
          circleColor = Colors.amberAccent;
          markerHue = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
          outerRadius = isOnCurrentRoute ? 1800.0 : 1200.0;
          innerRadius = isOnCurrentRoute ? 400.0 : 250.0;
      }

      // Outer Heatmap Glow Circle (Visible at high-level state/district zoom)
      _damageHeatmapCircles.add(
        Circle(
          circleId: CircleId('glow_${damage.damageId}'),
          center: LatLng(damage.latitude, damage.longitude),
          radius: outerRadius,
          fillColor: circleColor.withValues(alpha: isOnCurrentRoute ? 0.35 : 0.22),
          strokeColor: circleColor.withValues(alpha: isOnCurrentRoute ? 0.70 : 0.40),
          strokeWidth: isOnCurrentRoute ? 2 : 1,
        ),
      );

      // Inner Core Circle (High intensity hotspot)
      _damageHeatmapCircles.add(
        Circle(
          circleId: CircleId('core_${damage.damageId}'),
          center: LatLng(damage.latitude, damage.longitude),
          radius: innerRadius,
          fillColor: circleColor.withValues(alpha: isOnCurrentRoute ? 0.65 : 0.45),
          strokeColor: circleColor.withValues(alpha: 0.90),
          strokeWidth: 2,
        ),
      );

      // Interactive Marker for individual damage details
      _damageMarkers.add(
        Marker(
          markerId: MarkerId('damage_marker_${damage.damageId}'),
          position: LatLng(damage.latitude, damage.longitude),
          icon: markerHue,
          infoWindow: InfoWindow(
            title: '${isOnCurrentRoute ? "⚠️ ON ROUTE: " : ""}${damage.severity.toUpperCase()} Pothole',
            snippet: '${damage.district} • Tap for details',
            onTap: () => _showDamageDetailsModal(damage),
          ),
          onTap: () => _showDamageDetailsModal(damage),
        ),
      );
    }

    if (mounted) setState(() {});
  }

  void _triggerAdvanceDamageAlert(RoadDamageModel hazard) {
    _alertedDamageIds.add(hazard.damageId);
    _advanceAlertDismissTimer?.cancel();

    setState(() {
      _activeAdvanceAlert = hazard;
    });

    final distStr = hazard.distanceToVehicleMeters?.toStringAsFixed(0) ?? '200';
    final spokenMsg = "Caution: ${hazard.severity} severity pothole ahead in $distStr meters. Please reduce speed.";
    try {
      _flutterTts.speak(spokenMsg);
    } catch (_) {}

    // Post high-priority notification with vibration and sound for background driving & lock screen
    NotificationService().showRoadDamageAlertNotification(
      title: '⚠️ ${hazard.severity.toUpperCase()} POTHOLE AHEAD ($distStr m)',
      body: '${hazard.district} • Please reduce speed to avoid vehicle damage.',
      severity: hazard.severity,
    );

    // Auto dismiss HUD alert banner after 8 seconds
    _advanceAlertDismissTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) {
        setState(() {
          _activeAdvanceAlert = null;
        });
      }
    });
  }

  void _showDamageDetailsModal(RoadDamageModel damage) {
    Color sevColor;
    switch (damage.severity.toLowerCase()) {
      case 'high':
        sevColor = Colors.redAccent;
        break;
      case 'medium':
      case 'moderate':
        sevColor = Colors.orangeAccent;
        break;
      default:
        sevColor = Colors.amberAccent;
    }

    final double? distFromVehicle = _userPos != null
        ? Geolocator.distanceBetween(
            _userPos!.latitude,
            _userPos!.longitude,
            damage.latitude,
            damage.longitude,
          )
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF112240),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: sevColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.warning_amber_rounded, color: sevColor, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ROAD DAMAGE HAZARD',
                            style: TextStyle(
                              color: sevColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            '${damage.severity.toUpperCase()} SEVERITY POTHOLE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'VERIFIED',
                      style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A192F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  children: [
                    _buildModalRow('District', damage.district),
                    _buildModalRow(
                      'GPS Coordinates',
                      '${damage.latitude.toStringAsFixed(5)}, ${damage.longitude.toStringAsFixed(5)}',
                    ),
                    if (damage.distanceToRouteCorridorMeters != null)
                      _buildModalRow(
                        'Route Corridor Offset',
                        '${damage.distanceToRouteCorridorMeters!.toStringAsFixed(1)} m from centerline',
                      ),
                    if (distFromVehicle != null)
                      _buildModalRow(
                        'Distance from Vehicle',
                        distFromVehicle < 1000
                            ? '${distFromVehicle.toStringAsFixed(0)} m away'
                            : '${(distFromVehicle / 1000).toStringAsFixed(2)} km away',
                      ),
                    _buildModalRow('Source', damage.source),
                    _buildModalRow('Status', damage.status.toUpperCase()),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: sevColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sevColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, color: sevColor, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        damage.severity.toLowerCase() == 'high'
                            ? 'Severe road crater. Slow down to under 30 km/h and avoid sudden braking.'
                            : 'Road depression detected. Maintain firm steering and keep safe following distance.',
                        style: TextStyle(color: sevColor, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1F4068),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 11)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _openStartLocationPicker() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF112240),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Select Start Location',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.my_location_rounded, color: Color(0xFF00D2FF)),
              title: const Text('My Current GPS Location', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _userPos != null
                    ? '${_userPos!.latitude.toStringAsFixed(4)}, ${_userPos!.longitude.toStringAsFixed(4)}'
                    : 'Use device live GPS',
                style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12),
              ),
              onTap: () => Navigator.pop(ctx, 'current'),
            ),
            ListTile(
              leading: const Icon(Icons.search_rounded, color: Colors.greenAccent),
              title: const Text('Search Start Location in Tamil Nadu', style: TextStyle(color: Colors.white)),
              subtitle: const Text('Choose any city, junction or address', style: TextStyle(color: Color(0xFF8892B0), fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'search'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    if (choice == 'current') {
      setState(() {
        _customStartPos = null;
        _startLocationTitle = 'My Location';
        _startMarker = null;
      });
      if (_destinationMarker != null) {
        await _fetchAndDrawRoute(
          _destinationMarker!.position,
          title: _destinationTitle,
        );
      }
    } else if (choice == 'search') {
      if (!mounted) return;
      final selectedResult = await showSearch<SearchResult?>(
        context: context,
        delegate: LocationSearchDelegate(currentPosition: _userPos),
      );
      if (selectedResult != null) {
        setState(() {
          _customStartPos = selectedResult.latLng;
          _startLocationTitle = selectedResult.title;
        });
        if (_destinationMarker != null) {
          await _fetchAndDrawRoute(
            _destinationMarker!.position,
            title: _destinationTitle,
            startPoint: selectedResult.latLng,
            startTitle: selectedResult.title,
          );
        } else {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(selectedResult.latLng, 16.0),
          );
        }
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      body: SafeArea(
        child: Stack(
          children: [
            // Google Maps
            if (_userPos != null)
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: _userPos!,
                  zoom: 17.5,
                  bearing: _heading,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                onCameraMoveStarted: () {
                  setState(() {
                    _followUser = false;
                  });
                },
                zoomControlsEnabled: false,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                polylines: _polylines,
                circles: _showDamageHeatmap ? _damageHeatmapCircles : const {},
                markers: {
                  ?_startMarker,
                  ?_destinationMarker,
                  Marker(
                    markerId: const MarkerId('real_time_user_location'),
                    position: _userPos!,
                    rotation: _heading,
                    anchor: const Offset(0.5, 0.5),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueCyan,
                    ),
                  ),
                  if (_showDamageHeatmap) ..._damageMarkers,
                },
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_gpsStatus == 'Getting current location...')
                      const CircularProgressIndicator(color: primaryColor),
                    const SizedBox(height: 16),
                    Text(
                      _gpsStatus,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // Top Start & Destination Search Panel (Only shown when NOT in active drive mode)
            if (!_isDriveModeOn)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF112240).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Start Location Row
                      InkWell(
                        onTap: _openStartLocationPicker,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.trip_origin_rounded,
                                  color: Colors.greenAccent,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'START LOCATION',
                                      style: TextStyle(
                                        color: Color(0xFF8892B0),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    Text(
                                      _startLocationTitle ?? 'Current GPS Location',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.edit_location_alt_rounded,
                                color: Color(0xFF8892B0),
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(color: Colors.white12, height: 12),
                      // Destination Row
                      InkWell(
                        onTap: () async {
                          LatLng? origin = _customStartPos ?? _userPos;
                          if (origin == null && _currentPosition != null) {
                            origin = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
                          }
                          if (origin == null) {
                            try {
                              final p = await _locationService.getCurrentLocation();
                              if (p != null) {
                                origin = LatLng(p.latitude, p.longitude);
                                _userPos = origin;
                              }
                            } catch (_) {}
                          }
                          if (!context.mounted) return;
                          final selectedResult = await showSearch<SearchResult?>(
                            context: context,
                            delegate: LocationSearchDelegate(currentPosition: origin),
                          );
                          if (selectedResult != null) {
                            setState(() {
                              _followUser = false;
                            });
                            await _fetchAndDrawRoute(
                              selectedResult.latLng,
                              title: selectedResult.title,
                              startPoint: _customStartPos,
                              startTitle: _startLocationTitle,
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.location_on_rounded,
                                  color: primaryColor,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'DESTINATION',
                                      style: TextStyle(
                                        color: Color(0xFF8892B0),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                    Text(
                                      _destinationTitle ?? 'Search destination in Tamil Nadu...',
                                      style: TextStyle(
                                        color: _destinationTitle != null
                                            ? Colors.white
                                            : const Color(0xFF8892B0),
                                        fontSize: 13,
                                        fontWeight: _destinationTitle != null
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (_destinationTitle != null)
                                GestureDetector(
                                  onTap: _clearRoute,
                                  child: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                                )
                              else
                                const Icon(Icons.search_rounded, color: primaryColor, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Top Turn-by-Turn Navigation Header (When DRIVING)
            if (_isDriveModeOn)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF112240).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.navigation_rounded,
                          color: primaryColor,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _destinationTitle != null
                                  ? 'TO: $_destinationTitle'
                                  : 'DRIVING IN PROGRESS',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _routeDistance != null && _routeDuration != null
                                  ? 'Est: $_routeDuration ($_routeDistance)'
                                  : 'Turn-by-turn navigation active',
                              style: const TextStyle(
                                color: Color(0xFF8892B0),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Advance Road Damage Warning HUD Banner
            if (_activeAdvanceAlert != null)
              Positioned(
                top: _isDriveModeOn ? 85 : 125,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _activeAdvanceAlert!.severity.toLowerCase() == 'high'
                        ? const Color(0xFF8B0000).withValues(alpha: 0.95)
                        : const Color(0xFFB45309).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _activeAdvanceAlert!.severity.toLowerCase() == 'high'
                          ? Colors.redAccent
                          : Colors.amberAccent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: Colors.black26,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'POTHOLE: ${_activeAdvanceAlert!.severity.toUpperCase()}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black38,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_activeAdvanceAlert!.distanceToVehicleMeters?.toStringAsFixed(0) ?? '200'}m ahead',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_activeAdvanceAlert!.district} • Slow down to avoid vehicle damage',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                        onPressed: () {
                          setState(() {
                            _activeAdvanceAlert = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),

            // Right Map Controls
            if (_userPos != null)
              Positioned(
                right: 16,
                bottom: _isDriveModeOn
                    ? (_isRadarOverlayOn ? 335 : 180)
                    : (_routeDistance != null ? 140 : 20),
                child: Column(
                  children: [
                    if (_isDriveModeOn) ...[
                      FloatingActionButton.small(
                        heroTag: 'map_radar_toggle_btn',
                        onPressed: () {
                          setState(() {
                            _isRadarOverlayOn = !_isRadarOverlayOn;
                          });
                        },
                        backgroundColor: _isRadarOverlayOn
                            ? const Color(0xFF00FF88)
                            : const Color(0xFF112240),
                        tooltip: _isRadarOverlayOn ? 'Turn Radar OFF' : 'Turn Radar ON',
                        child: Icon(
                          Icons.radar_rounded,
                          color: _isRadarOverlayOn ? const Color(0xFF0A192F) : const Color(0xFF00FF88),
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FloatingActionButton.small(
                      heroTag: 'heatmap_toggle',
                      onPressed: () {
                        setState(() {
                          _showDamageHeatmap = !_showDamageHeatmap;
                          _updateHeatmapAndMarkers();
                        });
                      },
                      backgroundColor: _showDamageHeatmap
                          ? Colors.redAccent
                          : const Color(0xFF112240),
                      tooltip: 'Toggle Road Damage Heatmap',
                      child: Icon(
                        Icons.whatshot_rounded,
                        color: _showDamageHeatmap ? Colors.white : Colors.redAccent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      heroTag: 'zoom_in',
                      onPressed: () {
                        _mapController?.animateCamera(CameraUpdate.zoomIn());
                      },
                      backgroundColor: const Color(0xFF112240),
                      child: const Icon(Icons.add_rounded, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    FloatingActionButton.small(
                      heroTag: 'zoom_out',
                      onPressed: () {
                        _mapController?.animateCamera(CameraUpdate.zoomOut());
                      },
                      backgroundColor: const Color(0xFF112240),
                      child: const Icon(
                        Icons.remove_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'recenter',
                      onPressed: _recenterMap,
                      backgroundColor: _followUser
                          ? primaryColor
                          : const Color(0xFF112240),
                      child: Icon(
                        Icons.my_location_rounded,
                        color: _followUser ? Colors.white : primaryColor,
                      ),
                    ),
                  ],
                ),
              ),

            // Route Preview Card with "START DRIVING" button (When NOT driving)
            if (!_isDriveModeOn &&
                _routeDuration != null &&
                _routeDistance != null)
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A192F).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.directions_car_rounded,
                            color: primaryColor,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _destinationTitle ?? 'Route Destination',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$_routeDuration • $_routeDistance',
                                  style: const TextStyle(
                                    color: Color(0xFF8892B0),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white54,
                            ),
                            onPressed: _clearRoute,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (_routeDamage.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.whatshot_rounded, color: Colors.redAccent, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_routeDamage.length} Road Hazards on Route (50m corridor)\n${_routeDamage.where((d) => d.severity.toLowerCase() == "high").length} High • ${_routeDamage.where((d) => d.severity.toLowerCase() == "medium" || d.severity.toLowerCase() == "moderate").length} Medium • ${_routeDamage.where((d) => d.severity.toLowerCase() == "low").length} Low',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.greenAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Clear Route: 0 Road Hazards in 50m corridor',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _startDriving,
                          icon: const Icon(
                            Icons.navigation_rounded,
                            color: Colors.black,
                          ),
                          label: const Text(
                            'START DRIVING',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              letterSpacing: 1.1,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Live In-Map Forward Radar Cockpit HUD (When DRIVING & RADAR ON)
            if (_isDriveModeOn && _isRadarOverlayOn)
              Positioned(
                bottom: 185,
                left: 16,
                right: 16,
                child: StreamBuilder<V2VTelemetry>(
                  stream: V2VRadarService().telemetryStream,
                  initialData: V2VRadarService().latestTelemetry,
                  builder: (context, snapshot) {
                    final telemetry = snapshot.data ?? V2VTelemetry.initial();
                    final isCritical = telemetry.status == 'CRITICAL';
                    final isCaution = telemetry.status == 'CAUTION';
                    final radarStatusColor = isCritical
                        ? const Color(0xFFFF3366)
                        : (isCaution ? const Color(0xFFFFB74D) : const Color(0xFF00FF88));

                    final distM = (telemetry.distanceCm / 100.0);

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF071422).withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: radarStatusColor.withValues(alpha: 0.7),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: radarStatusColor.withValues(alpha: 0.2),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Top Status Bar
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: radarStatusColor,
                                  boxShadow: [
                                    BoxShadow(
                                      color: radarStatusColor,
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'FORWARD RADAR (CAR AHEAD)',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 1.0,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: radarStatusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: radarStatusColor, width: 0.8),
                                ),
                                child: Text(
                                  telemetry.status,
                                  style: TextStyle(
                                    color: radarStatusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => setState(() => _isRadarOverlayOn = false),
                                child: const Icon(Icons.close, color: Colors.white60, size: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Center Content: Left Mini Sweeping Arc + Right Distance readout
                          Row(
                            children: [
                              // Animated Radar Arc
                              SizedBox(
                                width: 140,
                                height: 85,
                                child: AnimatedBuilder(
                                  animation: _radarSweepController,
                                  builder: (context, child) {
                                    return CustomPaint(
                                      painter: RadarArcPainter(
                                        sweepProgress: _radarSweepController.value,
                                        distanceCm: telemetry.distanceCm,
                                        statusColor: radarStatusColor,
                                        useCentimeters: true,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Live Distance Display
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Text(
                                      'DISTANCE TO CAR',
                                      style: TextStyle(
                                        color: Color(0xFF88A0C0),
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          distM.toStringAsFixed(2),
                                          style: TextStyle(
                                            color: radarStatusColor,
                                            fontSize: 26,
                                            fontWeight: FontWeight.bold,
                                            height: 1.0,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'm',
                                          style: TextStyle(
                                            color: radarStatusColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          '(${telemetry.distanceCm.toStringAsFixed(1)} cm)',
                                          style: TextStyle(
                                            color: radarStatusColor.withValues(alpha: 0.7),
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isCritical
                                          ? '⚠️ TOO CLOSE! BRAKE NOW'
                                          : (isCaution ? '⚡ PROXIMITY CAUTION' : '✅ SAFE GAP AHEAD'),
                                      style: TextStyle(
                                        color: radarStatusColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

            // Live Driving Navigation HUD (When DRIVING)
            if (_isDriveModeOn)
              Positioned(
                bottom: 20,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A192F).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          // Speedometer
                          Column(
                            children: [
                              Text(
                                _currentSpeedKmh.toStringAsFixed(0),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  height: 1.0,
                                ),
                              ),
                              const Text(
                                'KM/H',
                                style: TextStyle(
                                  color: Color(0xFF8892B0),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            height: 36,
                            width: 1,
                            color: Colors.white12,
                          ),
                          // Time Elapsed
                          Column(
                            children: [
                              Text(
                                _formatDuration(_currentDuration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'TIME',
                                style: TextStyle(
                                  color: Color(0xFF8892B0),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            height: 36,
                            width: 1,
                            color: Colors.white12,
                          ),
                          // Distance Covered
                          Column(
                            children: [
                              Text(
                                (_totalDistanceMeters / 1000).toStringAsFixed(
                                  2,
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text(
                                'KM COVERED',
                                style: TextStyle(
                                  color: Color(0xFF8892B0),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // Safety Indicator
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    _currentSafetyStatus.riskLevel ==
                                        RiskLevel.safe
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : _currentSafetyStatus.riskLevel ==
                                          RiskLevel.warning
                                    ? Colors.orange.withValues(alpha: 0.15)
                                    : Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _currentSafetyStatus.riskLevel ==
                                            RiskLevel.safe
                                        ? Icons.check_circle_rounded
                                        : Icons.warning_amber_rounded,
                                    size: 16,
                                    color:
                                        _currentSafetyStatus.riskLevel ==
                                            RiskLevel.safe
                                        ? Colors.greenAccent
                                        : _currentSafetyStatus.riskLevel ==
                                              RiskLevel.warning
                                        ? Colors.orangeAccent
                                        : Colors.redAccent,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _currentSafetyStatus.message,
                                      style: TextStyle(
                                        color:
                                            _currentSafetyStatus.riskLevel ==
                                                RiskLevel.safe
                                            ? Colors.greenAccent
                                            : _currentSafetyStatus.riskLevel ==
                                                  RiskLevel.warning
                                            ? Colors.orangeAccent
                                            : Colors.redAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Radar Toggle Pill
                          InkWell(
                            onTap: () => setState(() => _isRadarOverlayOn = !_isRadarOverlayOn),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: _isRadarOverlayOn
                                    ? const Color(0xFF00FF88).withValues(alpha: 0.18)
                                    : const Color(0xFF112240),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _isRadarOverlayOn
                                      ? const Color(0xFF00FF88)
                                      : Colors.white24,
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.radar_rounded,
                                    size: 16,
                                    color: _isRadarOverlayOn
                                        ? const Color(0xFF00FF88)
                                        : Colors.white70,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _isRadarOverlayOn ? 'RADAR ON' : 'RADAR OFF',
                                    style: TextStyle(
                                      color: _isRadarOverlayOn
                                          ? const Color(0xFF00FF88)
                                          : Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Stop Driving Button
                          ElevatedButton.icon(
                            onPressed: _isSavingTrip
                                ? null
                                : _stopDrivingAndSave,
                            icon: _isSavingTrip
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.stop_rounded,
                                    color: Colors.white,
                                  ),
                            label: Text(
                              _isSavingTrip ? 'SAVING...' : 'END DRIVE',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent.shade700,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Loading indicator for route
            if (_isFetchingRoute)
              const Positioned(
                top: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: CircularProgressIndicator(color: primaryColor),
                ),
              ),

            // Futuristic Holographic Neural Orb (Draggable AI In-Car Copilot)
            NeuralCopilotOrb(
              initialOnLeft: true,
              initialYFraction: 0.42,
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (ctx) => CopilotSheet(
                    currentLocationName: null,
                    latitude: _userPos?.latitude,
                    longitude: _userPos?.longitude,
                    destinationName: _destinationTitle,
                    currentSpeedKmh: _currentSpeedKmh,
                    alertCount: 0,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// Hybrid Search Delegate returning SearchResult (Supports Proximity-Biased Search, Distance Sorting & Campus Landmarks)
class LocationSearchDelegate extends SearchDelegate<SearchResult?> {
  final LatLng? currentPosition;

  LocationSearchDelegate({this.currentPosition});

  // Local Campus POIs (MKCE Campus landmark fallbacks for instant precision)
  static final List<SearchResult> _campusPOIs = [
    const SearchResult(
      latLng: LatLng(11.0545, 78.0487),
      title: 'MKCE New Canteen',
      subtitle: 'MKCE Campus, Thalavapalayam',
    ),
    const SearchResult(
      latLng: LatLng(11.0543, 78.0483),
      title: 'MKCE Main Block & Admin',
      subtitle: 'MKCE Campus, Thalavapalayam',
    ),
    const SearchResult(
      latLng: LatLng(11.0549, 78.0490),
      title: 'MKCE Mechanical Block',
      subtitle: 'MKCE Campus, Thalavapalayam',
    ),
    const SearchResult(
      latLng: LatLng(11.0541, 78.0489),
      title: 'MKCE Library & Central Block',
      subtitle: 'MKCE Campus, Thalavapalayam',
    ),
    const SearchResult(
      latLng: LatLng(11.0538, 78.0478),
      title: 'MKCE Hostel & Sports Ground',
      subtitle: 'MKCE Campus, Thalavapalayam',
    ),
    const SearchResult(
      latLng: LatLng(11.0544, 78.0486),
      title: 'M. Kumarasamy College of Engineering (MKCE)',
      subtitle: 'Karur - Salem Highway',
    ),
  ];

  Future<List<SearchResult>> _getSuggestions(String input) async {
    final queryText = input.trim();
    if (queryText.isEmpty) return [];

    final List<SearchResult> results = [];
    final qLower = queryText.toLowerCase();

    // 1. Campus POIs: ONLY include if user is within 10km of MKCE campus OR query explicitly asks for MKCE
    bool isNearCampus = false;
    if (currentPosition != null) {
      final distToCampus = Geolocator.distanceBetween(
        currentPosition!.latitude,
        currentPosition!.longitude,
        11.0544,
        78.0486,
      );
      if (distToCampus < 10000) {
        isNearCampus = true;
      }
    }
    final isExplicitCampusQuery = qLower.contains('mkce') ||
        qLower.contains('kumarasamy') ||
        (isNearCampus && (qLower.contains('canteen') || qLower.contains('hostel') || qLower.contains('block') || qLower.contains('library')));

    if (isExplicitCampusQuery) {
      for (final poi in _campusPOIs) {
        if (poi.title.toLowerCase().contains(qLower) ||
            poi.subtitle?.toLowerCase().contains(qLower) == true ||
            (qLower.contains('mkce') && poi.title.toLowerCase().contains('canteen')) ||
            (qLower.contains('canteen') && poi.title.toLowerCase().contains('canteen'))) {
          double? distKm;
          if (currentPosition != null) {
            distKm = Geolocator.distanceBetween(
                  currentPosition!.latitude,
                  currentPosition!.longitude,
                  poi.latLng.latitude,
                  poi.latLng.longitude,
                ) /
                1000.0;
          }
          results.add(SearchResult(
            latLng: poi.latLng,
            title: poi.title,
            subtitle: poi.subtitle,
            distanceKm: distKm,
          ));
        }
      }
    }

    // 2. Fetch from OpenStreetMap Nominatim with strict localized viewbox first
    try {
      String osmQuery = queryText;
      if (qLower == 'mkce') {
        osmQuery = 'M Kumarasamy College of Engineering';
      }

      String osmUrlStr = 'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(osmQuery)}&format=json&addressdetails=1&limit=10&countrycodes=in';
      if (currentPosition != null) {
        // Bias search towards a ~35km bounding box around user position for guaranteed short-distance precision
        final delta = 0.32;
        final minLon = currentPosition!.longitude - delta;
        final maxLon = currentPosition!.longitude + delta;
        final minLat = currentPosition!.latitude - delta;
        final maxLat = currentPosition!.latitude + delta;
        osmUrlStr += '&viewbox=$minLon,$maxLat,$maxLon,$minLat&bounded=1';
      }

      var osmResp = await http.get(
        Uri.parse(osmUrlStr),
        headers: {'User-Agent': 'NeuroDrive_Flutter_App/1.0 (contact: support@neurodrive.app)'},
      ).timeout(const Duration(seconds: 4));

      var data = osmResp.statusCode == 200 ? (json.decode(osmResp.body) as List? ?? []) : [];
      // If localized bounded search yielded 0 results, fallback to nationwide search for long-distance queries
      if (data.isEmpty && currentPosition != null) {
        final fallbackUrl = 'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(osmQuery)}&format=json&addressdetails=1&limit=8&countrycodes=in';
        osmResp = await http.get(
          Uri.parse(fallbackUrl),
          headers: {'User-Agent': 'NeuroDrive_Flutter_App/1.0 (contact: support@neurodrive.app)'},
        ).timeout(const Duration(seconds: 4));
        if (osmResp.statusCode == 200) {
          data = json.decode(osmResp.body) as List? ?? [];
        }
      }

      for (final item in data) {
        final lat = double.tryParse(item['lat'].toString());
        final lng = double.tryParse(item['lon'].toString());
        final name = item['display_name']?.toString() ?? '';
        if (lat != null && lng != null && name.isNotEmpty) {
          final parts = name.split(',').map((p) => p.trim()).toList();
          final shortTitle = parts.isNotEmpty ? parts.first : name;
          final sub = parts.length > 1 ? parts.sublist(1, parts.length > 3 ? 3 : parts.length).join(', ') : null;

          double? distKm;
          if (currentPosition != null) {
            distKm = Geolocator.distanceBetween(
                  currentPosition!.latitude,
                  currentPosition!.longitude,
                  lat,
                  lng,
                ) /
                1000.0;
          }

          final isDuplicate = results.any((r) {
            final closeCoords = (r.latLng.latitude - lat).abs() < 0.002 && (r.latLng.longitude - lng).abs() < 0.002;
            final sameTitle = r.title.toLowerCase() == shortTitle.toLowerCase();
            return closeCoords || sameTitle;
          });

          if (!isDuplicate) {
            results.add(SearchResult(
              latLng: LatLng(lat, lng),
              title: shortTitle,
              subtitle: sub,
              distanceKm: distKm,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('OSM search error: $e');
    }

    // 3. Fetch from Photon Komoot (filtered strictly to India)
    try {
      String photonUrl = 'https://photon.komoot.io/api/?q=${Uri.encodeComponent(queryText)}&limit=10';
      if (currentPosition != null) {
        photonUrl += '&lat=${currentPosition!.latitude}&lon=${currentPosition!.longitude}';
      }
      final photonResp = await http.get(
        Uri.parse(photonUrl),
        headers: {'User-Agent': 'NeuroDrive_Flutter_App/1.0 (contact: support@neurodrive.app)'},
      ).timeout(const Duration(seconds: 4));

      if (photonResp.statusCode == 200) {
        final pData = json.decode(photonResp.body);
        final features = pData['features'] as List? ?? [];
        for (final f in features) {
          final props = f['properties'] as Map<String, dynamic>? ?? {};
          final coords = f['geometry']?['coordinates'] as List?;
          final name = props['name']?.toString() ?? '';
          final country = props['country']?.toString().toLowerCase() ?? '';
          final countryCode = props['countrycode']?.toString().toUpperCase() ?? '';

          // Reject foreign locations (e.g. South Dakota, Germany, etc.)
          final isIndia = countryCode == 'IN' || country.contains('india') || country.isEmpty;
          if (!isIndia) continue;

          if (name.isNotEmpty && coords != null && coords.length >= 2) {
            final lng = (coords[0] as num).toDouble();
            final lat = (coords[1] as num).toDouble();
            final city = props['city'] ?? props['district'] ?? props['town'] ?? props['county'] ?? '';
            final state = props['state'] ?? '';
            final street = props['street'] ?? '';

            final subtitleParts = <String>[];
            if (street.isNotEmpty) subtitleParts.add(street);
            if (city.isNotEmpty) subtitleParts.add(city);
            if (state.isNotEmpty && subtitleParts.isEmpty) subtitleParts.add(state);
            final sub = subtitleParts.join(', ');

            double? distKm;
            if (currentPosition != null) {
              distKm = Geolocator.distanceBetween(
                    currentPosition!.latitude,
                    currentPosition!.longitude,
                    lat,
                    lng,
                  ) /
                  1000.0;
            }

            final isDuplicate = results.any((r) {
              final closeCoords = (r.latLng.latitude - lat).abs() < 0.002 && (r.latLng.longitude - lng).abs() < 0.002;
              final sameTitle = r.title.toLowerCase() == name.toLowerCase();
              return closeCoords || sameTitle;
            });

            if (!isDuplicate) {
              results.add(SearchResult(
                latLng: LatLng(lat, lng),
                title: name,
                subtitle: sub.isNotEmpty ? sub : null,
                distanceKm: distKm,
              ));
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Photon search error: $e');
    }

    // 4. Sort results by distance ascending so short-distance / nearby locations always appear first!
    if (currentPosition != null) {
      results.sort((a, b) {
        final distA = a.distanceKm ?? 99999.0;
        final distB = b.distanceKm ?? 99999.0;
        return distA.compareTo(distB);
      });
    }

    return results;
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    return ThemeData(
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF112240),
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: TextStyle(color: Colors.white54),
      ),
      textTheme: const TextTheme(
        titleLarge: TextStyle(color: Colors.white, fontSize: 18),
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
          },
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSuggestionsList();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSuggestionsList();
  }

  Widget _buildSuggestionsList() {
    if (query.isEmpty) {
      return Container(
        color: const Color(0xFF0A192F),
        child: const Center(
          child: Text(
            'Start typing to search nearby or destination...\n(e.g., Chennai Central, Airport, MKCE, Canteen)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8892B0), height: 1.5),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF0A192F),
      child: FutureBuilder<List<SearchResult>>(
        future: _getSuggestions(query),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00D2FF)),
            );
          }
          if (snapshot.hasError ||
              !snapshot.hasData ||
              snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No locations found.\nTip: Check spelling or try searching a nearby landmark.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8892B0), height: 1.5),
              ),
            );
          }

          final suggestions = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: suggestions.length,
            separatorBuilder: (ctx, i) => const Divider(color: Colors.white10, height: 1),
            itemBuilder: (context, index) {
              final result = suggestions[index];
              final dist = result.distanceKm;
              final distLabel = dist != null
                  ? (dist < 1.0 ? '${(dist * 1000).round()} m' : '${dist.toStringAsFixed(1)} km')
                  : null;

              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00D2FF).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on_rounded,
                    color: Color(0xFF00D2FF),
                    size: 22,
                  ),
                ),
                title: Text(
                  result.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: result.subtitle != null
                    ? Text(
                        result.subtitle!,
                        style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                trailing: distLabel != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF112240),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF00D2FF).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          distLabel,
                          style: const TextStyle(
                            color: Color(0xFF00D2FF),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
                onTap: () {
                  close(context, result);
                },
              );
            },
          );
        },
      ),
    );
  }
}

