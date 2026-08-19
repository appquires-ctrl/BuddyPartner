import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:buddypartner/core/config/app_config.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/app/router/route_names.dart';

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
    if (state != null && state!.connected) return;

    final accessToken = await ref.read(apiClientProvider).getToken();
    if (accessToken == null) return;

    String appVersion = '1.0.0';
    try {
      if (!kIsWeb) {
        final pkg = await PackageInfo.fromPlatform();
        appVersion = pkg.version;
      }
    } catch (_) {}

    final platform = kIsWeb ? 'android' : (Platform.isIOS ? 'ios' : 'android');
    final authPayload = {
      'token': accessToken,
      'appVersion': appVersion,
      'platform': platform,
    };

    if (state != null) {
      if (state!.io.options != null) {
        state!.io.options!['auth'] = authPayload;
      }
      if (!state!.connected) {
        state!.connect();
      }
      return;
    }

    final socket = sio.io(
      AppConfig.backendUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth(authPayload)
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(10000)
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
        socket.io.options!['auth'] = {
          'token': token,
          'appVersion': appVersion,
          'platform': platform,
        };
      }
    });

    socket.onConnectError((err) {
      debugPrint('[SocketProvider] Connection error: $err');
      final errStr = err.toString();
      if (errStr.contains('ACCOUNT_UPGRADE_REQUIRED')) {
        final context = rootNavigatorKey.currentContext;
        if (context != null) {
          context.go(RouteNames.updateRequired);
        }
      }
    });

    socket.connect();
    state = socket;
  }

  /// Explicitly disconnect and dispose socket connection (e.g. on logout)
  void disconnectAndDispose() {
    _dispose();
  }

  void _dispose() {
    if (state != null) {
      try {
        if (state!.connected) {
          state!.disconnect();
        }
        state!.dispose();
      } catch (err) {
        debugPrint('[SocketProvider] Error disposing socket: $err');
      }
      state = null;
    }
  }
}

final socketProvider = NotifierProvider<SocketNotifier, sio.Socket?>(
  SocketNotifier.new,
);
