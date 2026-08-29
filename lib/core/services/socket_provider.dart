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
import 'package:buddypartner/core/utils/app_snack_bar.dart';

/// Shared Socket.io connection provider.
///
/// Both matchmaking and messaging reuse this single socket —
/// no second real-time connection is created.
///
/// The socket is lazily created on first access and disposed when
/// the user logs out (authState becomes null).
class SocketNotifier extends Notifier<sio.Socket?> {
  String? _connectedUserId;
  sio.Socket? _socket;

  @override
  sio.Socket? build() {
    ref.onDispose(_dispose);

    // Auto-connect when user authenticates, disconnect on logout or account switch
    ref.listen<AsyncValue<CustomUser?>>(authStateProvider, (prev, next) {
      final prevUser = prev?.value;
      final nextUser = next.value;

      if (nextUser != null) {
        if (prevUser != null && prevUser.id != nextUser.id) {
          // Account switched: explicitly tear down previous socket connection
          _dispose();
        }
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
    final currentUser = ref.read(authStateProvider).value;
    if (currentUser == null) return;

    // If socket exists for a different user, destroy it first
    if ((state != null || _socket != null) && _connectedUserId != null && _connectedUserId != currentUser.id) {
      _dispose();
    }

    if (_socket != null && _socket!.connected && _connectedUserId == currentUser.id) {
      state = _socket;
      return;
    }

    final accessToken = await ref.read(apiClientProvider).getToken();
    if (accessToken == null || accessToken.isEmpty) return;

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

    if (_socket != null && _connectedUserId == currentUser.id) {
      if (_socket!.io.options != null) {
        _socket!.io.options!['auth'] = authPayload;
      }
      if (!_socket!.connected) {
        _socket!.connect();
      }
      state = _socket;
      return;
    }

    // Completely destroy any existing socket before instantiating a fresh one
    _dispose();

    _connectedUserId = currentUser.id;

    final socket = sio.io(
      AppConfig.backendUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          .disableMultiplex()
          .setAuth(authPayload)
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(500)
          .setReconnectionDelayMax(3000)
          .setTimeout(5000)
          .build(),
    );

    _socket = socket;

    socket.onConnect((_) {
      debugPrint('[SocketProvider] Connected to backend as user: $_connectedUserId');
      state = socket;
      // Immediately notify backend of online status on connect
      try {
        socket.emit('presence:state', {'status': 'online'});
      } catch (_) {}
    });

    socket.on('force_disconnect', (data) {
      debugPrint('[SocketProvider] Received force_disconnect from server: $data');
      _dispose();
    });

    socket.on('session_terminated', (data) async {
      debugPrint('[SocketProvider] Received session_terminated from server: $data');
      _dispose();
      await ref.read(apiClientProvider).clearTokens();
      await ref.read(authStateProvider.notifier).clearSession();
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        final message = (data is Map && data['reason'] != null)
            ? data['reason'].toString()
            : 'Your account was logged in on another device. Please log in again.';
        AppSnackBar.showError(context, message);
        context.go(RouteNames.login);
      }
    });

    socket.onDisconnect((_) async {
      debugPrint('[SocketProvider] Disconnected');
      // Refresh token for reconnection if still authenticated
      final activeUser = ref.read(authStateProvider).value;
      if (activeUser != null && activeUser.id == _connectedUserId) {
        final token = await ref.read(apiClientProvider).getToken();
        if (token != null && socket.io.options != null) {
          socket.io.options!['auth'] = {
            'token': token,
            'appVersion': appVersion,
            'platform': platform,
          };
        }
      }
    });

    socket.onConnectError((err) {
      debugPrint('[SocketProvider] Connection error: $err');
      final errStr = err.toString();
      if (errStr.contains('SESSION_TERMINATED')) {
        _dispose();
        ref.read(apiClientProvider).clearTokens();
        ref.read(authStateProvider.notifier).clearSession();
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          AppSnackBar.showError(context, 'Your account was logged in on another device. Please log in again.');
          context.go(RouteNames.login);
        }
      } else if (errStr.contains('ACCOUNT_UPGRADE_REQUIRED')) {
        final context = rootNavigatorKey.currentContext;
        if (context != null) {
          context.go(RouteNames.updateRequired);
        }
      }
    });

    socket.connect();
    state = socket;
  }

  /// Instantly tell server the user is online (e.g. app foregrounded)
  void setPresenceOnline() {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    if (_socket != null && _socket!.connected) {
      try {
        _socket!.emit('presence:state', {'status': 'online'});
      } catch (err) {
        debugPrint('[SocketProvider] Error setting presence online: $err');
      }
    } else {
      _ensureConnected();
    }
  }

  /// Instantly tell server the user is offline (e.g. app paused/backgrounded/closed)
  void setPresenceOffline() {
    final sock = _socket ?? state;
    if (sock != null && sock.connected) {
      try {
        sock.emit('presence:state', {'status': 'offline'});
      } catch (err) {
        debugPrint('[SocketProvider] Error setting presence offline: $err');
      }
    }
  }

  /// Explicitly disconnect and dispose socket connection (e.g. on logout)
  void disconnectAndDispose() {
    setPresenceOffline();
    _dispose();
  }

  void _dispose() {
    _connectedUserId = null;
    final sock = _socket ?? state;
    _socket = null;
    if (sock != null) {
      try {
        sock.clearListeners();
        if (sock.connected) {
          sock.disconnect();
        }
        sock.dispose();
        sock.destroy();
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


