import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/socket_provider.dart';
import 'package:buddypartner/features/chat/application/presence_provider.dart';

final appLifecycleServiceProvider = Provider<AppLifecycleService>((ref) {
  final service = AppLifecycleService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// Global App Lifecycle Service
///
/// Listens to mobile OS lifecycle state changes (resumed, paused, hidden, detached)
/// to emit online/offline presence states with debouncing.
///
/// Prevents API request storms and ANR freezes caused by brief lifecycle changes
/// (such as permission dialogs, notification shade pull-downs, or quick app switches).
class AppLifecycleService {
  final Ref _ref;
  late final AppLifecycleListener _listener;
  Timer? _offlineDebounceTimer;
  bool _isMarkedOffline = false;

  // Grace period before transitioning presence to offline (absorbs transient dialogs)
  static const Duration _offlineDebounceDuration = Duration(seconds: 4);

  AppLifecycleService(this._ref) {
    _listener = AppLifecycleListener(
      onStateChange: _handleStateChange,
      onResume: _handleResume,
      onInactive: _handleInactive,
      onPause: _handlePause,
      onHide: _handleHide,
      onDetach: _handleDetach,
    );
  }

  void _handleStateChange(AppLifecycleState state) {
    debugPrint('[AppLifecycleService] AppLifecycleState: $state');
  }

  void _handleResume() {
    debugPrint('[AppLifecycleService] App resumed');
    final wasPendingOffline = _offlineDebounceTimer?.isActive ?? false;
    _offlineDebounceTimer?.cancel();
    _offlineDebounceTimer = null;

    // Only restore online presence if we actually completed the offline transition
    // or if this is the initial startup. Avoid spamming on transient dialog closes.
    if (_isMarkedOffline) {
      _isMarkedOffline = false;
      debugPrint('[AppLifecycleService] Restoring presence: ONLINE');
      _ref.read(socketProvider.notifier).setPresenceOnline();
      _ref.read(presenceProvider.notifier).refreshSubscribedPresence();
    } else if (!wasPendingOffline) {
      // Normal foregrounding without a pending offline timer (e.g. first resume)
      _ref.read(socketProvider.notifier).setPresenceOnline();
      _ref.read(presenceProvider.notifier).refreshSubscribedPresence();
    }
  }

  void _handleInactive() {
    // Inactive on Android occurs when system dialogs (e.g. permissions, camera,
    // notification shade) are displayed. The app is STILL visible in foreground.
    // Do NOT mark offline on inactive to avoid request oscillations.
    debugPrint('[AppLifecycleService] App inactive (foreground modal/shade) - keeping online state');
  }

  void _handlePause() {
    debugPrint('[AppLifecycleService] App paused -> Scheduling offline debounce (4s)');
    _scheduleOfflineTransition();
  }

  void _handleHide() {
    debugPrint('[AppLifecycleService] App hidden -> Scheduling offline debounce (4s)');
    _scheduleOfflineTransition();
  }

  void _handleDetach() {
    debugPrint('[AppLifecycleService] App detached -> Immediate OFFLINE');
    _offlineDebounceTimer?.cancel();
    _offlineDebounceTimer = null;
    _isMarkedOffline = true;
    _ref.read(socketProvider.notifier).setPresenceOffline();
  }

  void _scheduleOfflineTransition() {
    _offlineDebounceTimer?.cancel();
    _offlineDebounceTimer = Timer(_offlineDebounceDuration, () {
      _isMarkedOffline = true;
      debugPrint('[AppLifecycleService] Debounce expired -> Setting presence: OFFLINE');
      _ref.read(socketProvider.notifier).setPresenceOffline();
    });
  }

  void dispose() {
    _offlineDebounceTimer?.cancel();
    _listener.dispose();
  }
}
