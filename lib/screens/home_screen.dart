import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/services/location_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final LocationService _locationService = LocationService();
  final AuthService _authService = AuthService();
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionStreamSubscription;
  
  bool _isDriveModeOn = false;
  bool _followUser = true;
  String _gpsStatus = 'Inactive';
  Position? _currentPosition;
  double _currentSpeedKmh = 0.0;
  
  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _toggleDriveMode() async {
    if (_isDriveModeOn) {
      // Turn OFF Drive Mode
      _positionStreamSubscription?.cancel();
      setState(() {
        _isDriveModeOn = false;
        _gpsStatus = 'Inactive';
        _currentPosition = null;
        _currentSpeedKmh = 0.0;
      });
    } else {
      // Turn ON Drive Mode
      setState(() {
        _gpsStatus = 'Requesting Permissions...';
      });
      
      final hasPermission = await _locationService.handlePermissions();
      
      if (!hasPermission) {
        setState(() {
          _gpsStatus = 'Permission Denied / Unavailable';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required for Drive Mode')),
          );
        }
        return;
      }
      
      setState(() {
        _isDriveModeOn = true;
        _followUser = true; // Auto follow when starting
        _gpsStatus = 'Acquiring GPS Signal...';
      });

      _positionStreamSubscription = _locationService.getLocationStream()?.listen(
        (Position position) {
          final double calculatedSpeed =
              _locationService.calculateSpeedKmh(position, _currentPosition);

          setState(() {
            _currentPosition = position;
            _currentSpeedKmh = calculatedSpeed;
            _gpsStatus = 'Active (Real-time)';
          });
          
          if (_followUser && _mapController != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLngZoom(
                LatLng(position.latitude, position.longitude),
                16.0,
              ),
            );
          }
        },
        onError: (error) {
          setState(() {
            _gpsStatus = 'Error acquiring GPS';
          });
        },
      );
    }
  }

  void _recenterMap() {
    if (_currentPosition != null && _mapController != null) {
      setState(() {
        _followUser = true;
      });
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          16.0,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Speed in km/h calculated accurately via LocationService
    final double speedKmh = _isDriveModeOn ? _currentSpeedKmh : 0.0;
    
    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _authService.getUserProfileStream(),
          builder: (context, snapshot) {
            final name = snapshot.data?.data()?['name'] ?? 'Driver';
            return Text('Welcome, $name');
          }
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {},
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Phase 3 - Map',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _toggleDriveMode,
                    icon: Icon(_isDriveModeOn ? Icons.stop : Icons.play_arrow),
                    label: Text(_isDriveModeOn ? 'STOP DRIVE' : 'START DRIVE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDriveModeOn ? Colors.red : Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            
            // Stats Panel
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatCard('Speed (KM/H)', speedKmh.toStringAsFixed(1), _isDriveModeOn ? Colors.white : Colors.grey),
                  _buildStatCard('Heading', _currentPosition != null ? '${_currentPosition!.heading.toStringAsFixed(0)}°' : '---', Colors.white),
                  _buildStatCard('Status', _isDriveModeOn ? 'ON' : 'OFF', _isDriveModeOn ? Colors.greenAccent : Colors.grey),
                ],
              ),
            ),
            
            // Map Area
            Expanded(
              child: Stack(
                children: [
                  if (_isDriveModeOn) 
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: _currentPosition != null 
                            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                            : const LatLng(0, 0),
                        zoom: 16.0,
                      ),
                      onMapCreated: (controller) {
                        _mapController = controller;
                      },
                      onCameraMoveStarted: () {
                        setState(() {
                          _followUser = false; // Stop following if user pans map
                        });
                      },
                      myLocationEnabled: false,
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      markers: {
                        if (_currentPosition != null)
                          Marker(
                            markerId: const MarkerId('current_location'),
                            position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                            rotation: _currentPosition!.heading,
                            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                          ),
                      },
                    )
                  else
                    Container(
                      color: Colors.black54,
                      child: const Center(
                        child: Text(
                          'Start Drive Mode to view map',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ),
                    ),
                    
                  // Map Controls (Recenter Button)
                  if (_isDriveModeOn)
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: FloatingActionButton(
                        onPressed: _recenterMap,
                        backgroundColor: _followUser ? Theme.of(context).colorScheme.primary : Colors.grey[800],
                        child: Icon(
                          Icons.my_location, 
                          color: _followUser ? Colors.white : Colors.white54
                        ),
                      ),
                    ),
                    
                  // GPS Status Overlay
                  if (_isDriveModeOn)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _gpsStatus,
                          style: const TextStyle(color: Colors.white, fontSize: 12),
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

  Widget _buildStatCard(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
