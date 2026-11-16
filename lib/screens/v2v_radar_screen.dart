import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/models/v2v_telemetry.dart';
import '../core/services/v2v_radar_service.dart';

class V2VRadarScreen extends StatefulWidget {
  const V2VRadarScreen({super.key});

  @override
  State<V2VRadarScreen> createState() => _V2VRadarScreenState();
}

class _V2VRadarScreenState extends State<V2VRadarScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweepController;
  final V2VRadarService _radarService = V2VRadarService();

  // Settings
  bool _useCentimeters = true;
  final TextEditingController _ipController =
      TextEditingController(text: 'http://192.168.4.1/');
  final TextEditingController _firebaseNodeController =
      TextEditingController(text: 'live_telemetry/car_01');

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _radarService.initialize(initialMode: V2VConnectionMode.firebaseRealtime);
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _ipController.dispose();
    _firebaseNodeController.dispose();
    super.dispose();
  }

  void _showConnectionDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1E36),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final currentMode = _radarService.currentMode;
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Radar Data Source',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Option 1: Cloud Firestore (Already configured & active)
                  _buildSourceTile(
                    title: 'Cloud Firestore (Active)',
                    subtitle: 'Collection: /v2v_telemetry/car_01',
                    icon: Icons.local_fire_department_rounded,
                    isSelected: currentMode == V2VConnectionMode.cloudFirestore,
                    onTap: () {
                      _radarService.setConnectionMode(V2VConnectionMode.cloudFirestore);
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 8),
                  // Option 2: Firebase RTDB
                  _buildSourceTile(
                    title: 'Firebase Realtime Database',
                    subtitle: 'RTDB Node: /live_telemetry/car_01',
                    icon: Icons.cloud_sync_rounded,
                    isSelected: currentMode == V2VConnectionMode.firebaseRealtime,
                    onTap: () {
                      _radarService.setConnectionMode(
                        V2VConnectionMode.firebaseRealtime,
                        customFirebaseNode: _firebaseNodeController.text.trim(),
                      );
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 8),
                  // Option 3: Local ESP32 SoftAP (http://192.168.4.1/)
                  _buildSourceTile(
                    title: 'Direct ESP32 SoftAP',
                    subtitle: 'Local WiFi (http://192.168.4.1/)',
                    icon: Icons.wifi_tethering_rounded,
                    isSelected: currentMode == V2VConnectionMode.localEsp32,
                    onTap: () {
                      _radarService.setConnectionMode(
                        V2VConnectionMode.localEsp32,
                        customUrl: _ipController.text.trim(),
                      );
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                  ),
                  const SizedBox(height: 8),
                  // Option 4: Live Simulation
                  _buildSourceTile(
                    title: 'Interactive Simulation Mode',
                    subtitle: 'Oscillating radar test telemetry',
                    icon: Icons.play_circle_outline_rounded,
                    isSelected: currentMode == V2VConnectionMode.simulation,
                    onTap: () {
                      _radarService.setConnectionMode(V2VConnectionMode.simulation);
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSourceTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF00FF88).withValues(alpha: 0.12)
            : const Color(0xFF162744),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF00FF88) : Colors.white10,
          width: isSelected ? 1.5 : 1.0,
        ),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? const Color(0xFF00FF88) : Colors.white70,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle_rounded, color: Color(0xFF00FF88))
            : null,
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const radarGreen = Color(0xFF00FF88);

    return Scaffold(
      backgroundColor: const Color(0xFF060D17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1728),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MIST V2V',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              'ULTRASONIC RADAR MONITORING SYSTEM',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFF00FF88),
                letterSpacing: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_input_antenna_rounded, color: Color(0xFF00FF88)),
            tooltip: 'Connection Source',
            onPressed: _showConnectionDialog,
          ),
          IconButton(
            icon: Icon(
              _useCentimeters ? Icons.straighten_rounded : Icons.social_distance_rounded,
              color: Colors.white70,
            ),
            tooltip: 'Toggle Unit (cm / m)',
            onPressed: () => setState(() => _useCentimeters = !_useCentimeters),
          ),
        ],
      ),
      body: StreamBuilder<V2VTelemetry>(
        stream: _radarService.telemetryStream,
        initialData: _radarService.latestTelemetry,
        builder: (context, snapshot) {
          final telemetry = snapshot.data ?? V2VTelemetry.initial();
          final isCritical = telemetry.status == 'CRITICAL';
          final isCaution = telemetry.status == 'CAUTION';

          final statusColor = isCritical
              ? const Color(0xFFFF3366)
              : (isCaution ? const Color(0xFFFFB74D) : radarGreen);

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
              child: Column(
                children: [
                  // Top Device Status Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C1A2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: telemetry.isOnline ? radarGreen : Colors.red,
                                boxShadow: [
                                  BoxShadow(
                                    color: (telemetry.isOnline ? radarGreen : Colors.red)
                                        .withValues(alpha: 0.6),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              telemetry.vehicleId,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor, width: 1),
                          ),
                          child: Text(
                            telemetry.status,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // FORWARD RADAR VIEW Box (Matches Laptop Screen!)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF071422),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.1),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'FORWARD RADAR VIEW',
                          style: TextStyle(
                            color: Color(0xFF88A0C0),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Radar Canvas
                        SizedBox(
                          height: 250,
                          width: double.infinity,
                          child: AnimatedBuilder(
                            animation: _sweepController,
                            builder: (context, child) {
                              return CustomPaint(
                                painter: RadarArcPainter(
                                  sweepProgress: _sweepController.value,
                                  distanceCm: telemetry.distanceCm,
                                  statusColor: statusColor,
                                  useCentimeters: _useCentimeters,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // LIVE DETECTED DISTANCE Box (Matches Laptop Bottom Card)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C1A2E),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'LIVE DETECTED DISTANCE',
                          style: TextStyle(
                            color: Color(0xFF88A0C0),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              _useCentimeters
                                  ? telemetry.distanceCm.toStringAsFixed(1)
                                  : telemetry.distanceMeters.toStringAsFixed(2),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 46,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                                shadows: [
                                  Shadow(
                                    color: statusColor.withValues(alpha: 0.5),
                                    blurRadius: 16,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _useCentimeters ? 'cm' : 'm',
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _useCentimeters ? 'CENTIMETERS' : 'METERS',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2.0,
                          ),
                        ),
                        if (telemetry.remoteDistanceCm != null) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'V2V Remote Car: ${telemetry.remoteDistanceCm!.toStringAsFixed(1)} cm',
                              style: const TextStyle(
                                color: Colors.lightBlueAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2-Metric Telemetry Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          title: 'CLOSING SPEED',
                          value: '${telemetry.closingSpeedKmh.toStringAsFixed(1)} km/h',
                          icon: Icons.speed_rounded,
                          accentColor: const Color(0xFF00D2FF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          title: 'DATA SOURCE',
                          value: _getSourceName(_radarService.currentMode),
                          icon: Icons.hub_rounded,
                          accentColor: radarGreen,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ADAS Multi-Zone Proximity Guard (Safe / Caution / Critical)
                  StreamBuilder<ProximityZoneStats>(
                    stream: _radarService.zoneStatsStream,
                    initialData: _radarService.zoneStats,
                    builder: (context, statsSnapshot) {
                      final stats = statsSnapshot.data ?? _radarService.zoneStats;
                      final isSafe = stats.currentZone == 'SAFE';
                      final isCaution = stats.currentZone == 'CAUTION';
                      final isCritical = stats.currentZone == 'CRITICAL';

                      final activeColor = isCritical
                          ? const Color(0xFFFF3366)
                          : (isCaution ? const Color(0xFFFFB74D) : radarGreen);

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C1A2E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: activeColor.withValues(alpha: isSafe ? 0.3 : 0.7),
                            width: isSafe ? 1.0 : 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: activeColor.withValues(alpha: isSafe ? 0.05 : 0.2),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: Title + Active Zone Pill
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.shield_outlined, color: activeColor, size: 18),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'ADAS PROXIMITY ZONES',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: activeColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: activeColor, width: 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: activeColor,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        stats.currentZone,
                                        style: TextStyle(
                                          color: activeColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // 3-Zone Interactive Visual Bar
                            Row(
                              children: [
                                // Zone 1: Safe (> 15 cm)
                                Expanded(
                                  child: _buildZoneBadge(
                                    title: 'SAFE',
                                    range: '> 15 cm',
                                    color: radarGreen,
                                    isActive: isSafe,
                                    icon: Icons.check_circle_outline_rounded,
                                    count: null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Zone 2: Caution (8 – 15 cm)
                                Expanded(
                                  child: _buildZoneBadge(
                                    title: 'CAUTION',
                                    range: '8 – 15 cm',
                                    color: const Color(0xFFFFB74D),
                                    isActive: isCaution,
                                    icon: Icons.warning_amber_rounded,
                                    count: stats.cautionCount,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Zone 3: Critical (< 8 cm)
                                Expanded(
                                  child: _buildZoneBadge(
                                    title: 'CRITICAL',
                                    range: '< 8 cm',
                                    color: const Color(0xFFFF3366),
                                    isActive: isCritical,
                                    icon: Icons.dangerous_rounded,
                                    count: stats.criticalCount,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),
                            const Divider(color: Colors.white10, height: 1),
                            const SizedBox(height: 10),

                            // Footer: Guidance advice + Total Alerts Counter
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isCritical
                                        ? '🚨 COLLISION RISK: Brake immediately!'
                                        : (isCaution
                                            ? '⚠️ OBJECT NEARBY: Decelerate & hold distance.'
                                            : '🟢 SAFE CLEARANCE: Safe following distance maintained.'),
                                    style: TextStyle(
                                      color: isSafe ? const Color(0xFF88A0C0) : activeColor,
                                      fontSize: 11,
                                      fontWeight: isSafe ? FontWeight.normal : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${stats.totalCount} Alert${stats.totalCount == 1 ? "" : "s"}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Hardware Connection Diagnostic Box
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0C1B2E),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: telemetry.isOnline
                            ? radarGreen.withValues(alpha: 0.3)
                            : Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              telemetry.isOnline ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                              color: telemetry.isOnline ? radarGreen : Colors.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              telemetry.isOnline ? 'Hardware Stream Active' : 'Hardware Connection Guide',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            if (_radarService.workingEndpoint != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: radarGreen.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _radarService.workingEndpoint!.split('/').last,
                                  style: const TextStyle(color: radarGreen, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _radarService.lastDebugLog,
                          style: TextStyle(
                            color: telemetry.isOnline ? const Color(0xFF88A0C0) : const Color(0xFFFFCC80),
                            fontSize: 12,
                          ),
                        ),
                        if (_radarService.lastRawPayload != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Payload: ${_radarService.lastRawPayload}',
                              style: const TextStyle(
                                color: Color(0xFF00FF88),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                        if (!telemetry.isOnline && _radarService.currentMode == V2VConnectionMode.localEsp32) ...[
                          const Divider(color: Colors.white12, height: 16),
                          const Text(
                            '⚠️ Android Phone Settings Check:',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '1. Turn OFF Mobile Data (4G/5G) on your phone.\n2. Connect phone WiFi to ESP32 network.\n3. If phone says "No Internet", tap "Stay Connected".',
                            style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                _radarService.setConnectionMode(V2VConnectionMode.localEsp32);
                                setState(() {});
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 16, color: Color(0xFF00FF88)),
                              label: const Text('Re-scan Hardware Endpoints', style: TextStyle(color: Color(0xFF00FF88), fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF00FF88)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                        if (_radarService.currentMode == V2VConnectionMode.firebaseRealtime) ...[
                          const Divider(color: Colors.white12, height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await _radarService.pushTestDistanceToRtdb(distanceCm: 6.7);
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.radar_rounded, size: 16),
                                  label: const Text('Push 6.7 cm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00FF88),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await _radarService.pushTestDistanceToRtdb(distanceCm: 14.1);
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.bolt_rounded, size: 16),
                                  label: const Text('Push 14.1 cm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF9100),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_radarService.currentMode == V2VConnectionMode.cloudFirestore) ...[
                          const Divider(color: Colors.white12, height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    await _radarService.seedFirestoreData(distanceCm: 14.1);
                                    setState(() {});
                                  },
                                  icon: const Icon(Icons.bolt_rounded, size: 18),
                                  label: const Text('Seed Test Telemetry (14.1 cm)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF9100),
                                    foregroundColor: Colors.black,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _getSourceName(V2VConnectionMode mode) {
    switch (mode) {
      case V2VConnectionMode.cloudFirestore:
        return 'Cloud Firestore';
      case V2VConnectionMode.firebaseRealtime:
        return 'Firebase RTDB';
      case V2VConnectionMode.localEsp32:
        return 'ESP32 (192.168.4.1)';
      case V2VConnectionMode.simulation:
        return 'Simulation';
    }
  }

  Widget _buildInfoCard({
    required String title,
    required String value,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1A2E),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accentColor, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF88A0C0),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneBadge({
    required String title,
    required String range,
    required Color color,
    required bool isActive,
    required IconData icon,
    required int? count,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.18) : const Color(0xFF071422),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color : Colors.white12,
          width: isActive ? 1.8 : 1.0,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isActive ? color : Colors.white54, size: 14),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  color: isActive ? color : Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            range,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 9,
            ),
          ),
          if (count != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (count > 0 ? color : Colors.white10).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count logged',
                style: TextStyle(
                  color: count > 0 ? color : Colors.white54,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// CustomPainter that renders the exact Green Forward Radar Arc seen in Image 3
class RadarArcPainter extends CustomPainter {
  final double sweepProgress; // 0.0 to 1.0
  final double distanceCm;
  final Color statusColor;
  final bool useCentimeters;

  RadarArcPainter({
    required this.sweepProgress,
    required this.distanceCm,
    required this.statusColor,
    required this.useCentimeters,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 15);
    final maxRadius = math.min(size.width / 2 - 20, size.height - 30);

    const radarGreen = Color(0xFF00FF88);

    // 1. Radar Grid Ring Paints
    final ringPaint = Paint()
      ..color = radarGreen.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final axisPaint = Paint()
      ..color = radarGreen.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw 3 Concentric Semi-Circle Arcs (like 5cm, 10cm, 15cm)
    final ringSteps = [0.33, 0.66, 1.0];
    final labels = useCentimeters
        ? ['5cm', '10cm', '15cm']
        : ['5m', '10m', '15m'];

    for (int i = 0; i < ringSteps.length; i++) {
      final r = maxRadius * ringSteps[i];
      final rect = Rect.fromCircle(center: center, radius: r);
      canvas.drawArc(rect, math.pi, math.pi, false, ringPaint);

      // Ring text label (5cm, 10cm, 15cm)
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: radarGreen.withValues(alpha: 0.7),
            fontSize: 9,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(center.dx + 4, center.dy - r - 6),
      );
    }

    // Baseline horizontal axis
    canvas.drawLine(
      Offset(center.dx - maxRadius, center.dy),
      Offset(center.dx + maxRadius, center.dy),
      axisPaint,
    );

    // Center Forward Vertical Axis (90 deg)
    canvas.drawLine(
      center,
      Offset(center.dx, center.dy - maxRadius),
      Paint()
        ..color = radarGreen.withValues(alpha: 0.5)
        ..strokeWidth = 1.5,
    );

    // Angled Axis Lines (45 deg, 135 deg)
    for (final angle in [math.pi * 0.25, math.pi * 0.75]) {
      final dx = center.dx + maxRadius * math.cos(math.pi + angle);
      final dy = center.dy + maxRadius * math.sin(math.pi + angle);
      canvas.drawLine(center, Offset(dx, dy), axisPaint);
    }

    // 2. Sweeping Radar Beam (Sector Sweep from left to right)
    // Map progress 0..1 to angle pi .. 2*pi
    final sweepAngle = math.pi + (sweepProgress * math.pi);
    final sweepLineEnd = Offset(
      center.dx + maxRadius * math.cos(sweepAngle),
      center.dy + maxRadius * math.sin(sweepAngle),
    );

    // Sweeping beam tail (fading gradient)
    final beamPath = Path();
    beamPath.moveTo(center.dx, center.dy);
    const tailAngleSpan = math.pi * 0.18; // approx 32 degrees tail
    final tailStartAngle = sweepAngle - tailAngleSpan;
    beamPath.arcTo(
      Rect.fromCircle(center: center, radius: maxRadius),
      tailStartAngle,
      tailAngleSpan,
      false,
    );
    beamPath.close();

    final sweepGradient = RadialGradient(
      center: Alignment.bottomCenter,
      radius: 1.0,
      colors: [
        radarGreen.withValues(alpha: 0.35),
        radarGreen.withValues(alpha: 0.0),
      ],
    );

    final sweepFillPaint = Paint()
      ..shader = sweepGradient.createShader(
        Rect.fromCircle(center: center, radius: maxRadius),
      );
    canvas.drawPath(beamPath, sweepFillPaint);

    // Bright sweep line edge
    final sweepLinePaint = Paint()
      ..color = radarGreen
      ..strokeWidth = 2.0
      ..shader = LinearGradient(
        colors: [radarGreen.withValues(alpha: 0.1), radarGreen],
      ).createShader(Rect.fromPoints(center, sweepLineEnd));

    canvas.drawLine(center, sweepLineEnd, sweepLinePaint);

    // 3. Detected Vehicle Blip / Target Dot (at measured distance!)
    // Clamping distance to max 20 cm for full radius display
    final clampedDist = distanceCm.clamp(0.5, 20.0);
    final targetRadius = (clampedDist / 15.0) * maxRadius;
    final targetOffset = Offset(center.dx, center.dy - targetRadius);

    // Blip Outer Glow
    canvas.drawCircle(
      targetOffset,
      12.0,
      Paint()
        ..color = statusColor.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Blip Solid Core
    canvas.drawCircle(
      targetOffset,
      6.0,
      Paint()..color = statusColor,
    );

    // Blip Center White Dot
    canvas.drawCircle(
      targetOffset,
      2.5,
      Paint()..color = Colors.white,
    );

    // Blip text badge (e.g. "6.7 cm")
    final blipTextPainter = TextPainter(
      text: TextSpan(
        text: '${distanceCm.toStringAsFixed(1)} cm',
        style: TextStyle(
          color: statusColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          backgroundColor: const Color(0xFF071422).withValues(alpha: 0.8),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    blipTextPainter.paint(
      canvas,
      Offset(targetOffset.dx + 10, targetOffset.dy - 8),
    );

    // Origin Base Station Dot
    canvas.drawCircle(
      center,
      4.0,
      Paint()..color = Colors.white70,
    );
  }

  @override
  bool shouldRepaint(covariant RadarArcPainter oldDelegate) => true;
}
