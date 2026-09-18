import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/services/socket_provider.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

final presenceProvider =
    StateNotifierProvider<PresenceNotifier, Map<String, bool>>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final socket = ref.watch(socketProvider);
  // Reset cached map whenever user logs in, logs out, or switches accounts
  ref.watch(authStateProvider);
  return PresenceNotifier(apiClient, socket);
});

class PresenceNotifier extends StateNotifier<Map<String, bool>> {
  final ApiClient _apiClient;
  final sio.Socket? _socket;
  final Set<String> _subscribedUserIds = <String>{};
  final Map<String, Timer> _pendingOfflineTimers = <String, Timer>{};

  // Grace period before marking a user offline to prevent UI flickering on temporary network blips
  static const Duration _offlineGracePeriod = Duration(milliseconds: 1500);

  PresenceNotifier(this._apiClient, this._socket) : super({}) {
    _listenToPresenceEvents();
  }

  void _listenToPresenceEvents() {
    if (_socket == null) return;

    _socket.off('presence:update', _handlePresenceUpdate);
    _socket.on('presence:update', _handlePresenceUpdate);

    _socket.off('connect', _handleSocketReconnect);
    _socket.on('connect', _handleSocketReconnect);

    // If socket is already connected upon initialization, subscribe to tracked users
    if (_subscribedUserIds.isNotEmpty && _socket.connected) {
      try {
        _socket.emit('presence:subscribe', _subscribedUserIds.toList());
      } catch (_) {}
    }
  }

  void _handleSocketReconnect(dynamic _) {
    if (_subscribedUserIds.isNotEmpty && _socket != null && _socket.connected) {
      try {
        _socket.emit('presence:subscribe', _subscribedUserIds.toList());
        fetchPresence(_subscribedUserIds.toList());
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _socket?.off('presence:update', _handlePresenceUpdate);
    _socket?.off('connect', _handleSocketReconnect);
    for (final timer in _pendingOfflineTimers.values) {
      timer.cancel();
    }
    _pendingOfflineTimers.clear();
    super.dispose();
  }

  void _handlePresenceUpdate(dynamic data) {
    if (!mounted) return;
    if (data is Map<String, dynamic>) {
      final userId = data['userId'] as String?;
      final isOnline = data['isOnline'] as bool?;
      if (userId == null || isOnline == null) return;

      if (isOnline) {
        // Going online is INSTANT: cancel any pending offline timer and update state immediately
        _pendingOfflineTimers.remove(userId)?.cancel();
        if (state[userId] != true) {
          state = {
            ...state,
            userId: true,
          };
        }
      } else {
        // Going offline is DEBOUNCED: start 3s grace period timer to absorb network blips
        if (state[userId] == false) return;

        _pendingOfflineTimers.remove(userId)?.cancel();
        _pendingOfflineTimers[userId] = Timer(_offlineGracePeriod, () {
          _pendingOfflineTimers.remove(userId);
          if (mounted && state[userId] != false) {
            state = {
              ...state,
              userId: false,
            };
          }
        });
      }
    }
  }

  /// Explicitly mark a user as online immediately (e.g., when they type, send a message, or read a message).
  void markUserOnline(String userId) {
    final validId = userId.trim();
    if (validId.isEmpty || !mounted) return;
    _pendingOfflineTimers.remove(validId)?.cancel();
    if (state[validId] != true) {
      state = {
        ...state,
        validId: true,
      };
    }
  }

  /// Explicitly mark a user as offline (e.g., when a sent message remains single tick).
  void markUserOffline(String userId) {
    final validId = userId.trim();
    if (validId.isEmpty || !mounted) return;
    _pendingOfflineTimers.remove(validId)?.cancel();
    if (state[validId] != false) {
      state = {
        ...state,
        validId: false,
      };
    }
  }

  /// Subscribe to real-time presence updates for a list of user IDs.
  Future<void> subscribeToUsers(List<String> userIds) async {
    final validIds = userIds.where((id) => id.isNotEmpty).toList();
    if (validIds.isEmpty) return;

    _subscribedUserIds.addAll(validIds);

    if (_socket != null && _socket.connected) {
      try {
        _socket.emit('presence:subscribe', validIds);
      } catch (err) {
        debugPrint('[PresenceNotifier] Error subscribing to users: $err');
      }
    }

    await fetchPresence(validIds);
  }

  /// Unsubscribe from real-time presence updates for a list of user IDs.
  void unsubscribeFromUsers(List<String> userIds) {
    final validIds = userIds.where((id) => id.isNotEmpty).toList();
    if (validIds.isEmpty) return;

    _subscribedUserIds.removeAll(validIds);
    for (final id in validIds) {
      _pendingOfflineTimers.remove(id)?.cancel();
    }

    if (_socket != null && _socket.connected) {
      try {
        _socket.emit('presence:unsubscribe', validIds);
      } catch (err) {
        debugPrint('[PresenceNotifier] Error unsubscribing from users: $err');
      }
    }
  }

  DateTime? _lastFetchTime;
  Future<void>? _inFlightFetch;
  static const Duration _minFetchInterval = Duration(seconds: 15);

  /// Refresh presence for all currently subscribed users (e.g., when app resumes).
  Future<void> refreshSubscribedPresence({bool force = false}) async {
    if (_subscribedUserIds.isEmpty) return;

    final userIds = _subscribedUserIds.toList();
    if (_socket != null && _socket.connected) {
      try {
        _socket.emit('presence:subscribe', userIds);
      } catch (_) {}
    }

    await fetchPresence(userIds, force: force);
  }

  /// Query online presence for a list of user IDs via REST endpoint.
  Future<void> fetchPresence(List<String> userIds, {bool force = false}) async {
    final validIds = userIds.where((id) => id.isNotEmpty).toList();
    if (validIds.isEmpty || !mounted) return;

    final now = DateTime.now();
    if (!force && _lastFetchTime != null && now.difference(_lastFetchTime!) < _minFetchInterval) {
      return;
    }

    if (_inFlightFetch != null) {
      return _inFlightFetch!;
    }

    _inFlightFetch = _executeFetchPresence(validIds, now);
    try {
      await _inFlightFetch!;
    } finally {
      _inFlightFetch = null;
    }
  }

  Future<void> _executeFetchPresence(List<String> validIds, DateTime fetchTime) async {
    _lastFetchTime = fetchTime;
    try {
      final response = await _apiClient.dio.get('/api/presence', queryParameters: {
        'userIds': validIds.join(','),
      });

      if (!mounted) return;

      final map = (response.data['presence'] as Map<String, dynamic>?) ?? {};
      final updated = <String, bool>{...state};
      bool hasChanges = false;

      map.forEach((key, val) {
        final bool isOnline = val == true;
        if (isOnline) {
          _pendingOfflineTimers.remove(key)?.cancel();
        }
        if (state[key] != isOnline) {
          hasChanges = true;
        }
        updated[key] = isOnline;
      });

      if (hasChanges && mounted) {
        state = updated;
      }
    } catch (err) {
      // Keep existing status on network error
    }
  }

  /// Get online status for a specific user (defaults to false if unknown).
  bool isUserOnline(String userId) {
    return state[userId] ?? false;
  }
}
