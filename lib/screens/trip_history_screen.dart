import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../core/models/trip_model.dart';
import '../core/models/alert_model.dart';
import '../core/services/trip_service.dart';
import '../core/services/alert_service.dart';
import '../widgets/sync_status_badge.dart';
import 'trip_details_screen.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  final TripService _tripService = TripService();
  final AlertService _alertService = AlertService();
  int _selectedTab = 0;
  List<TripModel> _trips = [];
  List<AlertModel> _alerts = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (_isSyncing) return; // Prevent recursive loops when called from badge sync
    _isSyncing = true;
    if (_trips.isEmpty && _alerts.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      // Load trips from TripService (Firestore + Local sync fallback)
      final loadedTrips = await _tripService.getTrips();

      // Load alerts from AlertService (Firestore + Local sync fallback)
      final loadedAlerts = await _alertService.getAlerts();

      if (mounted) {
        setState(() {
          _trips = loadedTrips;
          _alerts = loadedAlerts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading trip history: $e');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Failed to load history: ${e.toString().replaceAll('Exception: ', '')}';
          _isLoading = false;
        });
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _clearHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign in to clear cloud history.')),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF112240),
        title: const Text(
          'Clear History',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to clear all your ${_selectedTab == 0 ? "trips" : "alerts"}? This cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF8892B0)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Clear',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (_selectedTab == 0) {
        await _tripService.clearAllTrips();
      } else {
        await _alertService.clearAllAlerts();
      }
      _loadData();
    }
  }

  Future<void> _seedMockAlerts() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to generate mock alerts.')),
        );
      }
      return;
    }

    try {
      final now = DateTime.now();

      final mockAlerts = [
        AlertModel(
          id: 'mock_alert_${now.millisecondsSinceEpoch}_1',
          tripId: 'mock_trip_01',
          alertType: 'CRITICAL_COLLISION_ALERT',
          severity: 'critical',
          message: 'CRITICAL: Vehicle braking sharply ahead! TTC: 1.8s',
          timestamp: now.subtract(const Duration(minutes: 2)),
          latitude: 11.0545,
          longitude: 78.0487,
          distance: 14.2,
          ttc: 1.8,
          isSynced: false,
        ),
        AlertModel(
          id: 'mock_alert_${now.millisecondsSinceEpoch}_2',
          tripId: 'mock_trip_01',
          alertType: 'COLLISION_WARNING',
          severity: 'warning',
          message: 'WARNING: Slow vehicle detected in lane. Distance: 32m',
          timestamp: now.subtract(const Duration(minutes: 8)),
          latitude: 11.0542,
          longitude: 78.0482,
          distance: 32.5,
          ttc: 3.4,
          isSynced: false,
        ),
        AlertModel(
          id: 'mock_alert_${now.millisecondsSinceEpoch}_3',
          tripId: 'mock_trip_01',
          alertType: 'CAUTION_ALERT',
          severity: 'caution',
          message: 'CAUTION: Speed limit recommendation. Safe gap maintained.',
          timestamp: now.subtract(const Duration(minutes: 18)),
          latitude: 11.0538,
          longitude: 78.0475,
          distance: 58.0,
          ttc: 6.2,
          isSynced: false,
        ),
      ];

      for (final alert in mockAlerts) {
        await _alertService.saveDirectAlert(alert);
      }

      if (mounted) {
        setState(() {
          _selectedTab = 1; // Switch to Alerts tab
        });
        await _loadData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('3 Mock Safety Alerts Added! (Critical, Warning, Caution)'),
              ],
            ),
            backgroundColor: Color(0xFF112240),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error generating mock alerts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF00D2FF);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text(
          'Trip History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: 12.0,
              horizontal: 4.0,
            ),
            child: SyncStatusBadge(onSyncCompleted: _loadData),
          ),
          IconButton(
            icon: const Icon(Icons.add_alert_rounded, color: Color(0xFF00D2FF)),
            onPressed: _seedMockAlerts,
            tooltip: 'Add Mock Safety Alerts',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
            onPressed: _clearHistory,
            tooltip: 'Clear History',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Segmented Tab Switcher (Trips | Alerts)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20.0,
                vertical: 12.0,
              ),
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
                            color: _selectedTab == 0
                                ? primaryColor.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: _selectedTab == 0
                                ? Border.all(color: primaryColor)
                                : null,
                          ),
                          child: Text(
                            'Trips',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _selectedTab == 0
                                  ? Colors.white
                                  : const Color(0xFF8892B0),
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
                            color: _selectedTab == 1
                                ? primaryColor.withValues(alpha: 0.2)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: _selectedTab == 1
                                ? Border.all(color: primaryColor)
                                : null,
                          ),
                          child: Text(
                            'Alerts',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _selectedTab == 1
                                  ? Colors.white
                                  : const Color(0xFF8892B0),
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
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF00D2FF),
                      ),
                    )
                  : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.cloud_off_rounded,
                              color: Colors.orangeAccent,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFF8892B0)),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadData,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _selectedTab == 1
                  ? _alerts.isEmpty
                        ? const Center(
                            child: Text(
                              'No alerts found.',
                              style: TextStyle(color: Color(0xFF8892B0)),
                            ),
                          )
                        : RefreshIndicator(
                            color: const Color(0xFF00D2FF),
                            backgroundColor: const Color(0xFF112240),
                            onRefresh: _loadData,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              itemCount: _alerts.length,
                              itemBuilder: (context, index) {
                                final alert = _alerts[index];
                                final startDt = alert.timestamp;
                                final dateStr = DateFormat(
                                  'dd MMM yyyy',
                                ).format(startDt);
                                final timeStr = DateFormat(
                                  'hh:mm a',
                                ).format(startDt);
                                final isCritical = alert.severity == 'critical';
                                final isCaution = alert.severity == 'caution';

                                final Color alertColor = isCritical
                                    ? Colors.redAccent
                                    : (isCaution
                                          ? const Color(0xFF00D2FF)
                                          : Colors.orangeAccent);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 14),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF112240),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: alertColor.withValues(alpha: 0.8),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isCritical
                                            ? Icons.warning_rounded
                                            : Icons.warning_amber_rounded,
                                        color: alertColor,
                                        size: 28,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    alert.message,
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                                if (!alert.isSynced)
                                                  const Tooltip(
                                                    message:
                                                        'Saved locally, pending cloud sync',
                                                    child: Icon(
                                                      Icons.cloud_off_rounded,
                                                      size: 14,
                                                      color:
                                                          Colors.orangeAccent,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  '$dateStr • $timeStr',
                                                  style: const TextStyle(
                                                    color: Color(0xFF8892B0),
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (alert.distance != null) ...[
                                                  const Text(
                                                    ' • ',
                                                    style: TextStyle(
                                                      color: Color(0xFF8892B0),
                                                    ),
                                                  ),
                                                  Text(
                                                    '${alert.distance!.toStringAsFixed(0)}m',
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ],
                                                if (alert.ttc != null) ...[
                                                  const Text(
                                                    ' • ',
                                                    style: TextStyle(
                                                      color: Color(0xFF8892B0),
                                                    ),
                                                  ),
                                                  Text(
                                                    'TTC: ${alert.ttc!.toStringAsFixed(1)}s',
                                                    style: TextStyle(
                                                      color: alertColor,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
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
                  ? const Center(
                      child: Text(
                        'No trips recorded yet.\nStart Driving to record trips!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF8892B0)),
                      ),
                    )
                  : RefreshIndicator(
                      color: const Color(0xFF00D2FF),
                      backgroundColor: const Color(0xFF112240),
                      onRefresh: _loadData,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        itemCount: _trips.length,
                        itemBuilder: (context, index) {
                          final trip = _trips[index];
                          final startDt = trip.startTime;

                          // Format values
                          final dateStr = DateFormat(
                            'dd MMM yyyy',
                          ).format(startDt);
                          final timeStr = DateFormat('hh:mm a').format(startDt);
                          final distStr = trip.distanceKm.toStringAsFixed(1);
                          final durationStr = trip.formattedDuration;
                          final speedStr =
                              '${trip.avgSpeed.toStringAsFixed(0)} km/h';

                          // Filter alerts belonging to this trip time window
                          final tripAlerts = _alerts.where((a) {
                            return a.timestamp.isAfter(
                                  startDt.subtract(const Duration(minutes: 1)),
                                ) &&
                                a.timestamp.isBefore(
                                  trip.endTime.add(const Duration(minutes: 1)),
                                );
                          }).toList();

                          final hasAlerts = tripAlerts.isNotEmpty;
                          final alertColor = hasAlerts
                              ? Colors.orangeAccent
                              : Colors.greenAccent;
                          final alertCountStr = '${tripAlerts.length} Alerts';

                          return _buildTripCard(
                            date: dateStr,
                            time: timeStr,
                            distance: '$distStr km',
                            duration: durationStr,
                            avgSpeed: speedStr,
                            isSynced: trip.isSynced,
                            alertCount: alertCountStr,
                            alertColor: alertColor,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TripDetailsScreen(
                                    trip: trip,
                                    allAlerts: _alerts,
                                  ),
                                ),
                              );
                            },
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
    required String avgSpeed,
    required bool isSynced,
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
                // Route Map Thumbnail Icon
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B192C),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(
                    Icons.alt_route_rounded,
                    color: Color(0xFF00D2FF),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            date,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Row(
                            children: [
                              if (!isSynced) ...[
                                const Tooltip(
                                  message: 'Saved locally, pending cloud sync',
                                  child: Icon(
                                    Icons.cloud_off_rounded,
                                    size: 14,
                                    color: Colors.orangeAccent,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                time,
                                style: const TextStyle(
                                  color: Color(0xFF8892B0),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$distance   •   $duration   •   $avgSpeed',
                        style: const TextStyle(
                          color: Color(0xFF8892B0),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 14,
                            color: alertColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            alertCount,
                            style: TextStyle(
                              color: alertColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8892B0),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
