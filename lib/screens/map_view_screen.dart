import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../core/services/location_service.dart';

class MapViewScreen extends StatefulWidget {
  const MapViewScreen({super.key});

  @override
  State<MapViewScreen> createState() => _MapViewScreenState();
}

class _MapViewScreenState extends State<MapViewScreen> {
  GoogleMapController? _mapController;
  final LocationService _locationService = LocationService();
  StreamSubscription<Position>? _positionStreamSubscription;

  // No hardcoded coordinates! 
  // Map will only render once a real GPS coordinate is received.
  LatLng? _userPos; 
  
  bool _followUser = true;
  String _gpsStatus = 'Getting current location...';
  double _heading = 0.0;

  // Route Planning Variables
  final Set<Polyline> _polylines = {};
  Marker? _destinationMarker;
  String? _routeDistance;
  String? _routeDuration;
  bool _isFetchingRoute = false;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
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
    setState(() {
      _userPos = LatLng(position.latitude, position.longitude);
      _heading = position.heading;
      _gpsStatus = 'Connected';
    });

    if (_followUser && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: _userPos!,
            zoom: 17.5,
            bearing: _heading,
          ),
        ),
      );
    }
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
            zoom: 17.5,
            bearing: _heading,
          ),
        ),
      );
    }
  }

  Future<void> _fetchAndDrawRoute(LatLng destination) async {
    if (_userPos == null) return;

    setState(() {
      _isFetchingRoute = true;
      _polylines.clear();
      _destinationMarker = Marker(
        markerId: const MarkerId('destination'),
        position: destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      );
      _routeDistance = null;
      _routeDuration = null;
    });

    try {
      final String url = 'https://router.project-osrm.org/route/v1/driving/'
          '${_userPos!.longitude},${_userPos!.latitude};'
          '${destination.longitude},${destination.latitude}'
          '?overview=full&geometries=geojson';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final route = data['routes'][0];
          
          // Parse metrics
          final double distanceMeters = route['distance'].toDouble();
          final double durationSeconds = route['duration'].toDouble();
          
          if (distanceMeters < 1000) {
            _routeDistance = '${distanceMeters.round()} m';
          } else {
            _routeDistance = '${(distanceMeters / 1000).toStringAsFixed(1)} km';
          }

          final int mins = (durationSeconds / 60).round();
          if (mins < 60) {
            _routeDuration = '$mins min';
          } else {
            final hours = mins ~/ 60;
            final remainingMins = mins % 60;
            _routeDuration = '${hours}h ${remainingMins}m';
          }

          // Parse coordinates
          final geometry = route['geometry'];
          final List coordinates = geometry['coordinates'];
          
          List<LatLng> polylineCoordinates = coordinates.map((coord) {
            return LatLng(coord[1].toDouble(), coord[0].toDouble()); // OSRM gives [lng, lat]
          }).toList();

          setState(() {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                color: const Color(0xFF3b82f6),
                width: 6,
                points: polylineCoordinates,
              ),
            );
          });

          // Zoom map to fit route
          if (_mapController != null && polylineCoordinates.isNotEmpty) {
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

            _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(minLat, minLng),
                  northeast: LatLng(maxLat, maxLng),
                ),
                50.0, // Padding
              ),
            );
          }
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

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      backgroundColor: const Color(0xFF0A192F), // Dark background while loading
      body: SafeArea(
        child: Stack(
          children: [
            // Full Screen Map Canvas (Google Maps) OR Loading Status
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
                  // If user manually pans/zooms, temporarily stop auto-following
                  setState(() {
                    _followUser = false;
                  });
                },
                zoomControlsEnabled: false,
                myLocationEnabled: false, // Using our own marker to show heading
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                polylines: _polylines,
                markers: {
                  ?_destinationMarker,
                  Marker(
                    markerId: const MarkerId('real_time_user_location'),
                    position: _userPos!,
                    rotation: _heading,
                    anchor: const Offset(0.5, 0.5),
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                  ),
                },
              )
            else
              // Strict requirement: NO fake map coordinates. 
              // Show the GPS status instead if no location is available yet.
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

            // Top Search Bar (Preserved exactly as requested)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF112240),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: TextField(
                  readOnly: true,
                  onTap: () async {
                    final selectedLocation = await showSearch<LatLng?>(
                      context: context,
                      delegate: LocationSearchDelegate(),
                    );
                    if (selectedLocation != null) {
                      setState(() {
                        _followUser = false;
                      });
                      await _fetchAndDrawRoute(selectedLocation);
                    }
                  },
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search location...',
                    hintStyle: TextStyle(color: Color(0xFF8892B0)),
                    prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF8892B0)),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ),
            ),

            // Map Controls (Layers, Zoom +, Zoom -, Recenter) (Preserved exactly)
            // Only show controls if map is loaded to prevent interaction errors
            if (_userPos != null)
              Positioned(
                right: 16,
                bottom: 20,
                child: Column(
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'layer_btn',
                      onPressed: () {},
                      backgroundColor: const Color(0xFF112240),
                      child: const Icon(Icons.layers_rounded, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
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
                      child: const Icon(Icons.remove_rounded, color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'recenter',
                      onPressed: () {
                        setState(() {
                          _polylines.clear();
                          _destinationMarker = null;
                          _routeDistance = null;
                          _routeDuration = null;
                        });
                        _recenterMap();
                      },
                      backgroundColor: _followUser ? primaryColor : const Color(0xFF112240),
                      child: Icon(Icons.my_location_rounded, color: _followUser ? Colors.white : primaryColor),
                    ),
                  ],
                ),
              ),

            // Route Info Overlay
            if (_routeDuration != null && _routeDistance != null)
              Positioned(
                top: 80,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A192F).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.directions_car_rounded, color: primaryColor, size: 20),
                      const SizedBox(width: 12),
                      Text(
                        _routeDuration!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        _routeDistance!,
                        style: const TextStyle(
                          color: Color(0xFF8892B0),
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                        onPressed: () {
                          setState(() {
                            _polylines.clear();
                            _destinationMarker = null;
                            _routeDistance = null;
                            _routeDuration = null;
                          });
                          _recenterMap();
                        },
                      )
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
          ],
        ),
      ),
    );
  }
}

// Free OpenStreetMap (Nominatim) Search Delegate
class LocationSearchDelegate extends SearchDelegate<LatLng?> {

  Future<List<Map<String, dynamic>>> _getSuggestions(String input) async {
    if (input.isEmpty) return [];
    
    // Add Chennai/India context to prioritize local results
    final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$input&format=json&addressdetails=1&limit=5&countrycodes=in');
    
    try {
      final response = await http.get(
        url, 
        headers: {
          'User-Agent': 'NeuroDrive_Flutter_App' // Nominatim requires a user-agent
        }
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (e) {
      debugPrint('Error fetching suggestions from OSM: $e');
    }
    return [];
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
            'Start typing to search...\n(e.g., Chennai Central, Airport)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8892B0)),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF0A192F),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getSuggestions(query),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00D2FF)));
          }
          if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text(
                'No locations found.',
                style: TextStyle(color: Color(0xFF8892B0)),
              ),
            );
          }

          final suggestions = snapshot.data!;
          return ListView.builder(
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final place = suggestions[index];
              final displayName = place['display_name'] ?? '';
              final parts = displayName.split(',');
              final mainText = parts.isNotEmpty ? parts[0].trim() : displayName;
              final secondaryText = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
              
              return ListTile(
                leading: const Icon(Icons.location_on, color: Color(0xFF00D2FF)),
                title: Text(
                  mainText,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  secondaryText,
                  style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  final lat = double.tryParse(place['lat'].toString());
                  final lng = double.tryParse(place['lon'].toString()); // Nominatim uses 'lon'
                  
                  if (lat != null && lng != null) {
                    close(context, LatLng(lat, lng));
                  } else {
                    close(context, null);
                  }
                },
              );
            },
          );
        },
      ),
    );
  }
}
