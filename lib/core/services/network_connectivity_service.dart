import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum NetworkStatus {
  connected,
  disconnected,
  checking,
}

/// State notifier that monitors real-time internet connectivity
class NetworkConnectivityNotifier extends StateNotifier<NetworkStatus> {
  Timer? _pollingTimer;
  bool _isChecking = false;

  NetworkConnectivityNotifier() : super(NetworkStatus.connected) {
    _init();
  }

  void _init() {
    checkConnection();
    // Periodically verify network health (every 8 seconds)
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      checkConnection(isBackground: true);
    });
  }

  /// Checks whether the device can reach the internet
  Future<bool> checkConnection({bool isBackground = false}) async {
    if (_isChecking) return state == NetworkStatus.connected;
    _isChecking = true;

    if (!isBackground && state != NetworkStatus.checking) {
      state = NetworkStatus.checking;
    }

    bool isOnline = false;
    try {
      if (kIsWeb) {
        isOnline = true;
      } else {
        // Fast primary lookup with strict timeout
        final lookup = await InternetAddress.lookup('google.com')
            .timeout(const Duration(seconds: 3));
        if (lookup.isNotEmpty && lookup[0].rawAddress.isNotEmpty) {
          isOnline = true;
        }
      }
    } catch (_) {
      // Fallback check to reliable DNS IP (8.8.8.8) to bypass potential local DNS issues
      try {
        if (!kIsWeb) {
          final socket = await Socket.connect('8.8.8.8', 53,
                  timeout: const Duration(seconds: 2))
              .timeout(const Duration(seconds: 2));
          socket.destroy();
          isOnline = true;
        }
      } catch (_) {
        isOnline = false;
      }
    }

    _isChecking = false;

    if (isOnline) {
      if (state != NetworkStatus.connected) {
        state = NetworkStatus.connected;
      }
    } else {
      if (state != NetworkStatus.disconnected) {
        state = NetworkStatus.disconnected;
      }
    }

    return isOnline;
  }

  /// Called when an HTTP / Socket connection error occurs in the app
  void markDisconnected() {
    if (state != NetworkStatus.disconnected) {
      state = NetworkStatus.disconnected;
    }
  }

  /// Called when an HTTP / Socket request succeeds
  void markConnected() {
    if (state != NetworkStatus.connected) {
      state = NetworkStatus.connected;
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}

final networkConnectivityProvider =
    StateNotifierProvider<NetworkConnectivityNotifier, NetworkStatus>((ref) {
  return NetworkConnectivityNotifier();
});
