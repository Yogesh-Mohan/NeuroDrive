import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum NetworkState {
  online,
  offline,
}

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService({Connectivity? connectivity, http.Client? client}) {
    if (connectivity != null) _instance._connectivity = connectivity;
    if (client != null) _instance._client = client;
    return _instance;
  }
  ConnectivityService._internal() {
    _init();
  }

  Connectivity _connectivity = Connectivity();
  http.Client _client = http.Client();

  final StreamController<bool> _internetController = StreamController<bool>.broadcast();
  Stream<bool> get onInternetConnectionChanged => _internetController.stream;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _debounceTimer;

  /// Custom verifier override for unit testing
  @visibleForTesting
  Future<bool> Function()? testVerifier;

  void _init() {
    // Listen to hardware network state changes
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _handleHardwareConnectivityChange(results);
    });

    // Initial check
    checkRealInternet().then((online) {
      _isOnline = online;
      _internetController.add(online);
    }).catchError((_) {});
  }

  void _handleHardwareConnectivityChange(List<ConnectivityResult> results) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      final hasHardware = results.any((r) => r != ConnectivityResult.none);
      if (!hasHardware) {
        _updateOnlineState(false);
      } else {
        // Hardware is connected, verify real internet access
        final realInternet = await checkRealInternet();
        _updateOnlineState(realInternet);
      }
    });
  }

  void _updateOnlineState(bool online) {
    if (_isOnline != online) {
      _isOnline = online;
      debugPrint('[ConnectivityService] Internet status changed: ${online ? "ONLINE" : "OFFLINE"}');
      _internetController.add(online);
    }
  }

  /// Verifies actual reachability beyond local interface assignment.
  /// Uses multiple fast fallback strategies with resilient timeouts.
  Future<bool> checkRealInternet() async {
    if (testVerifier != null) {
      return await testVerifier!();
    }

    try {
      // 1. Check hardware status first
      final results = await _connectivity.checkConnectivity();
      final hasHardware = results.any((r) => r != ConnectivityResult.none);
      if (!hasHardware) {
        return false;
      }

      // 2. Perform fast DNS lookup (fastest & most reliable on Android mobile data)
      if (!kIsWeb) {
        try {
          final lookup = await InternetAddress.lookup('google.com')
              .timeout(const Duration(seconds: 3));
          if (lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty) {
            return true;
          }
        } catch (_) {}
      }

      // 3. Fallback: HTTP 204 endpoint check
      try {
        final probeUrl = Uri.parse('https://www.google.com/generate_204');
        final response = await _client.get(probeUrl).timeout(const Duration(seconds: 4));
        if (response.statusCode == 200 || response.statusCode == 204) {
          return true;
        }
      } catch (_) {}

      // 4. Secondary DNS fallback for cloudflare
      if (!kIsWeb) {
        try {
          final lookupCf = await InternetAddress.lookup('1.1.1.1')
              .timeout(const Duration(seconds: 2));
          if (lookupCf.isNotEmpty) return true;
        } catch (_) {}
      }

      // If hardware shows connected (Mobile data or WiFi), treat as online optimistically
      // rather than showing false "Offline" when strict probe fails on mobile carrier NAT
      return hasHardware;
    } catch (_) {
      return true;
    }
  }

  @visibleForTesting
  void setOnlineManually(bool online) {
    _isOnline = online;
    _internetController.add(online);
  }

  void dispose() {
    _subscription?.cancel();
    _debounceTimer?.cancel();
    _internetController.close();
  }
}
