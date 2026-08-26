import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/widgets/feedback/in_app_notification_banner.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

/// Top-level background message handler required by Firebase Messaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  if (kDebugMode) {
    debugPrint('🔔 [FCM Background] Received push: ${message.messageId}, data: ${message.data}');
  }
}

/// NotificationService coordinates Firebase Messaging (FCM), token registration,
/// and routes incoming messages to both system push and in-app banners.
class NotificationService {
  static final NotificationService instance = NotificationService._internal();
  NotificationService._internal();

  bool _initialized = false;
  String? _fcmToken;

  /// Callback to navigate to a conversation from notification click
  void Function({
    required String conversationId,
    required String userId,
    required String userName,
    String? userAvatar,
  })? onOpenChat;

  /// Initializes Firebase and Firebase Messaging safely
  Future<void> initialize(WidgetRef? ref) async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp();
      _initialized = true;
      if (kDebugMode) {
        debugPrint('🔥 [Firebase] Initialized successfully');
      }

      // 1. Request notification permissions (Android 13+ & iOS)
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (kDebugMode) {
        debugPrint('🔔 [FCM] Notification authorization status: ${settings.authorizationStatus}');
      }

      // 2. Fetch and register FCM Token
      _fcmToken = await messaging.getToken();
      if (kDebugMode) {
        debugPrint('🔔 [FCM] Device Token: $_fcmToken');
      }

      if (ref != null && _fcmToken != null) {
        await syncTokenWithBackend(ref, _fcmToken!);
      }

      // 3. Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (kDebugMode) {
          debugPrint('🔔 [FCM] Token refreshed: $newToken');
        }
        if (ref != null) {
          syncTokenWithBackend(ref, newToken);
        }
      });

      // 4. Foreground Message Listener -> Show In-App Banner
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint('🔔 [FCM Foreground] Received: ${message.notification?.title} - ${message.notification?.body}');
        }
        _handleForegroundMessage(message);
      });

      // 5. Handle notification click when app is opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint('🔔 [FCM Open] User clicked notification: ${message.data}');
        }
        _handleNotificationClick(message);
      });

      // 6. Handle app launch from terminated state via notification click
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        if (kDebugMode) {
          debugPrint('🔔 [FCM Terminated Open] App launched via notification: ${initialMessage.data}');
        }
        Future.delayed(const Duration(milliseconds: 800), () {
          _handleNotificationClick(initialMessage);
        });
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Warning: Firebase Messaging initialization error: $e');
      }
    }
  }

  String? get fcmToken => _fcmToken;

  /// Sends device FCM token to backend for push notification routing
  Future<void> syncTokenWithBackend(WidgetRef ref, [String? token]) async {
    final tokenToSync = token ?? _fcmToken;
    if (tokenToSync == null || tokenToSync.isEmpty) return;

    try {
      final authUser = ref.read(authStateProvider).value;
      if (authUser == null || authUser.id.isEmpty) {
        if (kDebugMode) {
          debugPrint('🔔 [FCM] User not yet authenticated, token cached: ${tokenToSync.substring(0, 15)}...');
        }
        return;
      }

      final apiClient = ref.read(apiClientProvider);
      await apiClient.dio.post(
        '/api/notifications/fcm-token',
        data: {'fcmToken': tokenToSync},
      ).catchError((_) async {
        // Fallback endpoint
        return await apiClient.dio.post(
          '/api/auth/fcm-token',
          data: {'fcmToken': tokenToSync},
        );
      });

      if (kDebugMode) {
        debugPrint('🔔 [FCM] Token successfully registered with server for user ${authUser.id}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Warning: Could not sync FCM token with server: $e');
      }
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString();

    // Do NOT show in-app chat banner for call notifications!
    if (type == 'instant_call' || type == 'incoming_call') {
      debugPrint('🔔 [FCM Foreground] Received call alert ($type). Suppressing chat banner.');
      return;
    }

    final notification = message.notification;

    final senderId = data['senderId']?.toString() ?? data['userId']?.toString() ?? '';
    final senderName = data['senderName']?.toString() ??
        data['userName']?.toString() ??
        notification?.title?.replaceAll('New message from ', '') ??
        'User';
    final messageBody = data['message']?.toString() ??
        data['text']?.toString() ??
        notification?.body ??
        'Sent you a new message';
    final conversationId = data['conversationId']?.toString() ?? 'user:$senderId';
    final avatar = data['avatar']?.toString() ?? data['senderAvatar']?.toString();
    final avatarSeed = data['avatarSeed']?.toString();
    final avatarStyle = data['avatarStyle']?.toString();
    final gender = data['gender']?.toString();

    // Trigger in-app notification banner only for actual chat messages
    if (senderId.isNotEmpty || conversationId.isNotEmpty) {
      InAppNotificationManager.show(InAppMessageNotification(
        senderId: senderId,
        senderName: senderName,
        senderAvatar: avatar,
        avatarSeed: avatarSeed,
        avatarStyle: avatarStyle,
        gender: gender,
        message: messageBody,
        conversationId: conversationId,
      ));
    }
  }

  void _handleNotificationClick(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString();

    if (type == 'instant_call' || type == 'incoming_call') {
      debugPrint('🔔 [FCM Click] Opened app for live call alert: $type');
      return;
    }

    final senderId = data['senderId']?.toString() ?? data['userId']?.toString() ?? '';
    final senderName = data['senderName']?.toString() ?? data['userName']?.toString() ?? 'User';
    final conversationId = data['conversationId']?.toString() ?? (senderId.isNotEmpty ? 'user:$senderId' : '');
    final avatar = data['avatar']?.toString() ?? data['senderAvatar']?.toString();

    if (senderId.isNotEmpty || conversationId.isNotEmpty) {
      onOpenChat?.call(
        conversationId: conversationId,
        userId: senderId,
        userName: senderName,
        userAvatar: avatar,
      );
    }
  }
}

/// Provider for NotificationService
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});
