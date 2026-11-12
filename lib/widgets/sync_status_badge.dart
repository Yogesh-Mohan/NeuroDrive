import 'dart:async';
import 'package:flutter/material.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/sync_service.dart';

class SyncStatusBadge extends StatefulWidget {
  final bool showPendingCount;
  final VoidCallback? onSyncCompleted;

  const SyncStatusBadge({
    super.key,
    this.showPendingCount = true,
    this.onSyncCompleted,
  });

  @override
  State<SyncStatusBadge> createState() => _SyncStatusBadgeState();
}

class _SyncStatusBadgeState extends State<SyncStatusBadge> {
  final SyncService _syncService = SyncService();
  final ConnectivityService _connectivityService = ConnectivityService();

  bool _isOnline = true;
  SyncState _syncState = SyncState.idle;
  int _pendingCount = 0;
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<SyncState>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _isOnline = _connectivityService.isOnline;
    _syncState = _syncService.currentSyncState;
    _updatePendingCount();

    _connectivitySubscription = _connectivityService.onInternetConnectionChanged.listen((online) {
      if (mounted) {
        setState(() => _isOnline = online);
        _updatePendingCount();
      }
    });

    _syncSubscription = _syncService.syncStateStream.listen((state) {
      if (mounted) {
        setState(() => _syncState = state);
        _updatePendingCount();
        if (state == SyncState.success && widget.onSyncCompleted != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onSyncCompleted!();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _updatePendingCount() async {
    final count = await _syncService.getPendingCount();
    if (mounted) {
      setState(() => _pendingCount = count);
    }
  }

  Future<void> _handleTap() async {
    if (_syncState == SyncState.syncing) return;

    if (!_isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pendingCount > 0
                ? 'Device is offline. $_pendingCount record(s) safely saved in local SQLite storage.'
                : 'Device is offline. All records are stored locally.',
          ),
          backgroundColor: const Color(0xFF112240),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting synchronization with Cloud Firestore...'),
        backgroundColor: Color(0xFF112240),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    final res = await _syncService.syncAll(force: true);
    if (!mounted) return;

    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 20),
              const SizedBox(width: 8),
              Text('Cloud sync complete: ${res.totalSynced} items updated.'),
            ],
          ),
          backgroundColor: const Color(0xFF112240),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _updatePendingCount();
      if (widget.onSyncCompleted != null) widget.onSyncCompleted!();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.errors.isNotEmpty ? res.errors.first : 'Sync failed. Will retry automatically.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Color badgeColor;
    IconData badgeIcon;
    String badgeText;

    if (_syncState == SyncState.syncing) {
      badgeColor = Colors.orangeAccent;
      badgeIcon = Icons.sync_rounded;
      badgeText = 'Syncing...';
    } else if (!_isOnline) {
      badgeColor = const Color(0xFFFF5252);
      badgeIcon = Icons.cloud_off_rounded;
      badgeText = _pendingCount > 0 ? 'Offline ($_pendingCount)' : 'Offline';
    } else if (_syncState == SyncState.failed) {
      badgeColor = Colors.orange;
      badgeIcon = Icons.warning_amber_rounded;
      badgeText = 'Sync Failed';
    } else if (_pendingCount > 0) {
      badgeColor = const Color(0xFF00D2FF);
      badgeIcon = Icons.cloud_upload_outlined;
      badgeText = 'Pending Sync ($_pendingCount)';
    } else {
      badgeColor = Colors.greenAccent;
      badgeIcon = Icons.cloud_done_rounded;
      badgeText = 'Synced';
    }

    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: badgeColor.withValues(alpha: 0.6), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_syncState == SyncState.syncing)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
                ),
              )
            else
              Icon(badgeIcon, size: 14, color: badgeColor),
            const SizedBox(width: 5),
            Text(
              badgeText,
              style: TextStyle(
                color: badgeColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
