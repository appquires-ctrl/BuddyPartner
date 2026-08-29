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
/// to immediately emit instant online/offline presence states to the backend
/// without waiting for Socket.IO ping/pong timeouts.
class AppLifecycleService {
  final Ref _ref;
  late final AppLifecycleListener _listener;

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
    debugPrint('[AppLifecycleService] App resumed -> Setting presence: ONLINE');
    _ref.read(socketProvider.notifier).setPresenceOnline();
    _ref.read(presenceProvider.notifier).refreshSubscribedPresence();
  }

  void _handleInactive() {
    debugPrint('[AppLifecycleService] App inactive -> Setting presence: OFFLINE');
    _ref.read(socketProvider.notifier).setPresenceOffline();
  }

  void _handlePause() {
    debugPrint('[AppLifecycleService] App paused -> Setting presence: OFFLINE');
    _ref.read(socketProvider.notifier).setPresenceOffline();
  }

  void _handleHide() {
    debugPrint('[AppLifecycleService] App hidden -> Setting presence: OFFLINE');
    _ref.read(socketProvider.notifier).setPresenceOffline();
  }

  void _handleDetach() {
    debugPrint('[AppLifecycleService] App detached -> Setting presence: OFFLINE');
    _ref.read(socketProvider.notifier).setPresenceOffline();
  }

  void dispose() {
    _listener.dispose();
  }
}
