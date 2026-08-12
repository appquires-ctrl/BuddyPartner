import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/services/socket_provider.dart';

import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

final presenceProvider =
    StateNotifierProvider.autoDispose<PresenceNotifier, Map<String, bool>>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final socket = ref.watch(socketProvider);
  // Re-build and reset cached map whenever user logs in, logs out, or switches accounts
  ref.watch(authStateProvider);
  return PresenceNotifier(apiClient, socket);
});

class PresenceNotifier extends StateNotifier<Map<String, bool>> {
  final ApiClient _apiClient;
  final sio.Socket? _socket;

  PresenceNotifier(this._apiClient, this._socket) : super({}) {
    _listenToPresenceEvents();
  }

  void _listenToPresenceEvents() {
    if (_socket == null) return;

    _socket.off('presence:update', _handlePresenceUpdate);
    _socket.on('presence:update', _handlePresenceUpdate);
  }

  @override
  void dispose() {
    _socket?.off('presence:update', _handlePresenceUpdate);
    super.dispose();
  }

  void _handlePresenceUpdate(dynamic data) {
    if (!mounted) return;
    if (data is Map<String, dynamic>) {
      final userId = data['userId'] as String?;
      final isOnline = data['isOnline'] as bool?;
      if (userId != null && isOnline != null) {
        state = {
          ...state,
          userId: isOnline,
        };
      }
    }
  }

  /// Query online presence for a list of user IDs via REST endpoint.
  Future<void> fetchPresence(List<String> userIds) async {
    if (userIds.isEmpty || !mounted) return;

    try {
      final response = await _apiClient.dio.get('/api/presence', queryParameters: {
        'userIds': userIds.join(','),
      });

      if (!mounted) return;

      final map = (response.data['presence'] as Map<String, dynamic>?) ?? {};
      final updated = <String, bool>{...state};

      map.forEach((key, val) {
        updated[key] = val == true;
      });

      if (mounted) {
        state = updated;
      }
    } catch (err) {
      // Keep existing status on error
    }
  }

  /// Get online status for a specific user (defaults to false if unknown).
  bool isUserOnline(String userId) {
    return state[userId] ?? false;
  }
}
