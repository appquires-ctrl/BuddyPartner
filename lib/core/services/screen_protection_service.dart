import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:dating_app/app/router/app_router.dart';
import 'package:dating_app/core/services/socket_provider.dart';

/// Service to manage app-wide screen protection across platforms.
///
/// - Android: Hardware/OS-level block via FLAG_SECURE (ScreenProtector.preventScreenshotOn).
/// - iOS: App-switcher privacy (ScreenProtector.protectDataWithColor) + Screenshot detection listener
///        that triggers UI toast & socket event.
class ScreenProtectionService {
  final Ref _ref;

  ScreenProtectionService(this._ref);

  /// Called early in main.dart before runApp for global OS-level protection
  static Future<void> enableGlobalProtection() async {
    // Disabled for now so clients and QA can take screenshots for bug reports
    /*
    try {
      await ScreenProtector.preventScreenshotOn();
      await ScreenProtector.protectDataLeakageWithColor(Colors.black);
      await ScreenProtector.protectDataLeakageOff();
    } catch (e) {
      debugPrint('[ScreenProtectionService] Error enabling global protection: $e');
    }
    */
  }

  /// Initialize event listeners for screenshot detection
  void initScreenshotListener() {
    // Disabled for now so clients and QA can take screenshots for bug reports
    /*
    try {
      ScreenProtector.addListener(
        () {
          _handleScreenshotDetected('screenshot');
        },
        (isRecording) {
          if (isRecording) {
            _handleScreenshotDetected('screen_recording');
          }
        },
      );
    } catch (e) {
      debugPrint('[ScreenProtectionService] Listener init error: $e');
    }
    */
  }

  void dispose() {
    try {
      ScreenProtector.removeListener();
    } catch (e) {
      debugPrint('[ScreenProtectionService] Error removing listener: $e');
    }
  }

  // ignore: unused_element
  void _handleScreenshotDetected(String type) {
    debugPrint('[ScreenProtectionService] Event detected: $type');

    // 1. Show floating warning Snackbar in app UI
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.white),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Screenshots are not supported in this app for privacy.',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    // 2. Emit Socket.io event to inform other participant/backend if connected
    final socket = _ref.read(socketProvider);
    if (socket != null && socket.connected) {
      socket.emit('screenshot_taken', {
        'type': type,
        'timestamp': DateTime.now().toIso8601String(),
      });
      debugPrint('[ScreenProtectionService] Emitted screenshot_taken socket event');
    }
  }
}

final screenProtectionServiceProvider = Provider<ScreenProtectionService>((ref) {
  final service = ScreenProtectionService(ref);
  service.initScreenshotListener();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
