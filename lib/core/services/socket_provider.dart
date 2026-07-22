import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/api_client.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

/// Shared Socket.io connection provider.
///
/// Both matchmaking and messaging reuse this single socket —
/// no second real-time connection is created.
///
/// The socket is lazily created on first access and disposed when
/// the user logs out (authState becomes null).
class SocketNotifier extends Notifier<sio.Socket?> {
  @override
  sio.Socket? build() {
    ref.onDispose(_dispose);

    // Auto-connect when user authenticates, disconnect on logout
    ref.listen<AsyncValue<CustomUser?>>(authStateProvider, (prev, next) {
      final user = next.value;
      if (user != null) {
        _ensureConnected();
      } else {
        _dispose();
      }
    });

    // If user is already logged in at build time, connect
    final user = ref.read(authStateProvider).value;
    if (user != null) {
      Future.microtask(() => _ensureConnected());
    }

    return null;
  }

  /// Ensure the socket is created and connected.
  Future<void> _ensureConnected() async {
    if (state != null) return;

    final accessToken = await ref.read(apiClientProvider).getToken();
    if (accessToken == null) return;

    final socket = sio.io(
      AppConfig.backendUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );

    socket.onConnect((_) {
      debugPrint('[SocketProvider] Connected to backend');
      state = socket;
    });

    socket.onDisconnect((_) async {
      debugPrint('[SocketProvider] Disconnected');
      // Refresh token for reconnection
      final token = await ref.read(apiClientProvider).getToken();
      if (token != null && socket.io.options != null) {
        socket.io.options!['auth'] = {'token': token};
      }
    });

    socket.onConnectError((err) {
      debugPrint('[SocketProvider] Connection error: $err');
    });

    socket.connect();
    state = socket;
  }

  void _dispose() {
    state?.dispose();
    state = null;
  }
}

final socketProvider = NotifierProvider<SocketNotifier, sio.Socket?>(
  SocketNotifier.new,
);
