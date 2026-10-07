import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  int _selectedTab = 0;
  List<Map<String, dynamic>> _trips = [];
  List<Map<String, dynamic>> _alerts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final tripsStr = prefs.getStringList('neurodrive_trips_$uid') ?? [];
      final alertsStr = prefs.getStringList('neurodrive_alerts_$uid') ?? [];
      
      setState(() {
        _trips = tripsStr.map((t) => json.decode(t) as Map<String, dynamic>).toList();
        _trips.sort((a, b) => DateTime.parse(b['startTime']).compareTo(DateTime.parse(a['startTime'])));
        
        _alerts = alertsStr.map((a) => json.decode(a) as Map<String, dynamic>).toList();
        _alerts.sort((a, b) => DateTime.parse(b['timestamp']).compareTo(DateTime.parse(a['timestamp'])));
        
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading trips: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _clearHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF112240),
        title: const Text('Clear History', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to clear all your ${_selectedTab == 0 ? "trips" : "alerts"}? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8892B0))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      if (_selectedTab == 0) {
        await prefs.remove('neurodrive_trips_$uid');
      } else {
        await prefs.remove('neurodrive_alerts_$uid');
      }
      _loadTrips();
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Trip History', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            onPressed: _clearHistory,
            tooltip: 'Clear History',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadTrips();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Segmented Tab Switcher (Trips | Alerts)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF112240),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0 ? primaryColor.withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: _selectedTab == 0 ? Border.all(color: primaryColor) : null,
                          ),
                          child: Text(
                            'Trips',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _selectedTab == 0 ? Colors.white : const Color(0xFF8892B0),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedTab = 1),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1 ? primaryColor.withValues(alpha: 0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: _selectedTab == 1 ? Border.all(color: primaryColor) : null,
                          ),
                          child: Text(
                            'Alerts',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _selectedTab == 1 ? Colors.white : const Color(0xFF8892B0),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // History List
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D2FF)))
                : _selectedTab == 1 
                  ? _alerts.isEmpty 
                    ? const Center(child: Text('No alerts found.', style: TextStyle(color: Color(0xFF8892B0))))
                    : RefreshIndicator(
                        color: const Color(0xFF00D2FF),
                        backgroundColor: const Color(0xFF112240),
                        onRefresh: _loadTrips,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          itemCount: _alerts.length,
                          itemBuilder: (context, index) {
                            final alert = _alerts[index];
                            final startDt = DateTime.parse(alert['timestamp']);
                            final dateStr = DateFormat('dd MMM yyyy').format(startDt);
                            final timeStr = DateFormat('hh:mm a').format(startDt);
                            
                            final isCritical = alert['riskLevel'] == 'RiskLevel.critical';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF112240),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: isCritical ? Colors.redAccent : Colors.orangeAccent),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_rounded, color: isCritical ? Colors.redAccent : Colors.orangeAccent, size: 28),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(alert['message'] ?? 'Alert', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                        const SizedBox(height: 4),
                                        Text('$dateStr • $timeStr', style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                  : _trips.isEmpty 
                    ? const Center(child: Text('No trips recorded yet.\nStart Driving to record trips!', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF8892B0))))
                    : RefreshIndicator(
                        color: const Color(0xFF00D2FF),
                        backgroundColor: const Color(0xFF112240),
                        onRefresh: _loadTrips,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          itemCount: _trips.length,
                          itemBuilder: (context, index) {
                            final trip = _trips[index];
                            final startDt = DateTime.parse(trip['startTime']);
                            
                            // Format values
                            final dateStr = DateFormat('dd MMM yyyy').format(startDt);
                            final timeStr = DateFormat('hh:mm a').format(startDt);
                            final distStr = (trip['distanceMeters'] / 1000).toStringAsFixed(1);
                            
                            final int durationSec = trip['durationSeconds'];
                            final int min = durationSec ~/ 60;
                            final String durationStr = min > 0 ? '$min min' : '$durationSec sec';

                            return _buildTripCard(
                              date: dateStr,
                              time: timeStr,
                              distance: '$distStr km',
                              duration: durationStr,
                              alertCount: '0 Alerts', // Future feature
                              alertColor: Colors.greenAccent,
                              onTap: () {}, // Future details screen
                            );
                          },
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripCard({
    required String date,
    required String time,
    required String distance,
    required String duration,
    required String alertCount,
    required Color alertColor,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF112240),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Route Map Thumbnail Placeholder
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B192C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.alt_route_rounded, color: Color(0xFF00D2FF), size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(date, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(time, style: const TextStyle(color: Color(0xFF8892B0), fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('$distance   •   $duration', style: const TextStyle(color: Color(0xFF8892B0), fontSize: 12)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, size: 14, color: alertColor),
                          const SizedBox(width: 4),
                          Text(alertCount, style: TextStyle(color: alertColor, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF8892B0)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
