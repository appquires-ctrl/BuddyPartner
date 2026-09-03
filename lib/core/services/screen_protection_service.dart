import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/services/socket_provider.dart';

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
    try {
      await ScreenProtector.preventScreenshotOn();
      if (Platform.isIOS) {
        await ScreenProtector.protectDataLeakageWithColor(Colors.black);
      }
    } catch (e) {
      debugPrint('[ScreenProtectionService] Error enabling global protection: $e');
    }
  }

  /// Initialize event listeners for screenshot detection
  void initScreenshotListener() {
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
      AppSnackBar.showError(context, 'Screenshots are not supported in this app for privacy.');
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
