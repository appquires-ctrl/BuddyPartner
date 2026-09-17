import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/services/socket_provider.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';

/// Service to manage dynamic screen protection across platforms.
///
/// - Standard UI (Home, Discover, Chat, Wallet, Profile, etc.): Screenshots are fully allowed.
/// - Active Video & Voice Calls: Screenshots and recordings are strictly restricted
///   via FLAG_SECURE on Android and preventScreenshot + color mask on iOS.
class ScreenProtectionService {
  final Ref _ref;
  static bool _isCallProtectionActive = false;
  ProviderSubscription<MatchmakingState>? _mmSub;
  ProviderSubscription<InstantConnectState>? _instantSub;
  AppLifecycleListener? _lifecycleListener;

  ScreenProtectionService(this._ref);

  /// Current protection state
  static bool get isCallProtectionActive => _isCallProtectionActive;

  /// Enables screenshot & screen recording protection.
  /// Called when entering an active video or voice call.
  static Future<void> enableCallProtection() async {
    if (_isCallProtectionActive) return;
    _isCallProtectionActive = true;
    try {
      await ScreenProtector.preventScreenshotOn();
      if (Platform.isIOS) {
        await ScreenProtector.protectDataLeakageWithColor(Colors.black);
      }
      debugPrint('[ScreenProtectionService] Call screen protection ENABLED (FLAG_SECURE active)');
    } catch (e) {
      _isCallProtectionActive = false;
      debugPrint('[ScreenProtectionService] Error enabling call protection: $e');
    }
  }

  /// Disables screenshot & screen recording protection.
  /// Allows users to take screenshots freely across all normal screens.
  static Future<void> disableCallProtection({bool force = false}) async {
    if (!_isCallProtectionActive && !force) return;
    _isCallProtectionActive = false;
    try {
      await ScreenProtector.preventScreenshotOff();
      if (Platform.isIOS) {
        await ScreenProtector.protectDataLeakageWithColorOff();
      }
      debugPrint('[ScreenProtectionService] Call screen protection DISABLED (FLAG_SECURE cleared)');
    } catch (e) {
      debugPrint('[ScreenProtectionService] Error disabling call protection: $e');
    }
  }

  /// Deprecated alias to prevent blocking on startup
  @Deprecated('Use enableCallProtection() or disableCallProtection() instead')
  static Future<void> enableGlobalProtection() async {
    await disableCallProtection(force: true);
  }

  /// Initialize screenshot listener, call lifecycle observers, and OS resume sync
  void init() {
    _initScreenshotListener();
    _bindCallLifecycleListeners();
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        _syncCallProtection();
      },
    );
    // Sync initial state on app start
    _syncCallProtection();
  }

  void _initScreenshotListener() {
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

  void _bindCallLifecycleListeners() {
    // Monitor regular matchmaking call phase
    _mmSub = _ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      _syncCallProtection();
    });

    // Monitor instant connect VIP call phase
    _instantSub = _ref.listen<InstantConnectState>(instantConnectControllerProvider, (prev, next) {
      _syncCallProtection();
    });
  }

  void _syncCallProtection() {
    final mmState = _ref.read(matchmakingControllerProvider);
    final instantState = _ref.read(instantConnectControllerProvider);

    final isMmInCall = (mmState.phase == MatchmakingPhase.inCall || mmState.phase == MatchmakingPhase.matched);
    final isInstantInCall = instantState.phase == InstantPhase.inCall;

    final isCallActive = isMmInCall || isInstantInCall;
    final shouldProtect = isCallActive && !mmState.isCallMinimized;

    if (shouldProtect && !_isCallProtectionActive) {
      enableCallProtection();
    } else if (!shouldProtect && _isCallProtectionActive) {
      disableCallProtection();
    }
  }

  void dispose() {
    _mmSub?.close();
    _instantSub?.close();
    _lifecycleListener?.dispose();
    try {
      ScreenProtector.removeListener();
    } catch (e) {
      debugPrint('[ScreenProtectionService] Error removing listener: $e');
    }
  }

  void _handleScreenshotDetected(String type) {
    // Crucial: Only restrict & alert if inside an active call!
    // Screenshots anywhere else in the app are completely permitted.
    if (!_isCallProtectionActive) {
      debugPrint('[ScreenProtectionService] Screenshot taken outside call; permitted.');
      return;
    }

    debugPrint('[ScreenProtectionService] Call screenshot/recording detected: $type');

    // 1. Show warning Snackbar in app UI during call
    final context = rootNavigatorKey.currentContext;
    if (context != null && context.mounted) {
      AppSnackBar.showError(context, 'Screenshots are restricted during calls for privacy.');
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
  service.init();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

