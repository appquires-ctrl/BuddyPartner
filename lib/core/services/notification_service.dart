import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/services/apptrove_service.dart';
import 'package:buddypartner/core/widgets/feedback/in_app_notification_banner.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

/// Holds pending chat payload when app is launched cold from a notification
class PendingChatNotification {
  final String conversationId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;

  const PendingChatNotification({
    required this.conversationId,
    required this.userId,
    required this.userName,
    this.userAvatar,
    this.avatarSeed,
    this.avatarStyle,
    this.gender,
  });
}

/// Holds pending group chat payload when app is launched cold from a notification
class PendingGroupNotification {
  final String groupId;
  final String title;

  const PendingGroupNotification({
    required this.groupId,
    required this.title,
  });
}

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
  PendingChatNotification? _pendingChatNotification;
  PendingGroupNotification? _pendingGroupNotification;

  /// Pending chat notification if launched from terminated state
  PendingChatNotification? get pendingChatNotification => _pendingChatNotification;
  PendingGroupNotification? get pendingGroupNotification => _pendingGroupNotification;

  /// Consumes and clears the pending chat notification
  PendingChatNotification? consumePendingChat() {
    final pending = _pendingChatNotification;
    _pendingChatNotification = null;
    return pending;
  }

  /// Consumes and clears the pending group chat notification
  PendingGroupNotification? consumePendingGroup() {
    final pending = _pendingGroupNotification;
    _pendingGroupNotification = null;
    return pending;
  }

  /// Callback to navigate to a conversation from notification click
  void Function({
    required String conversationId,
    required String userId,
    required String userName,
    String? userAvatar,
    String? avatarSeed,
    String? avatarStyle,
    String? gender,
  })? onOpenChat;

  /// Callback to navigate to a buddy group chat from notification click
  void Function({
    required String groupId,
    required String title,
  })? onOpenBuddyGroup;

  /// Callback when a female taps an Instant VIP call push notification
  void Function({
    required String sessionId,
    required int bidAmount,
  })? onInstantCallNotification;

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

      if (_fcmToken != null) {
        AppTroveService.sendFcmToken(_fcmToken!);
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
        AppTroveService.sendFcmToken(newToken);
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
        _handleInitialMessage(initialMessage);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Warning: Firebase Messaging initialization error: $e');
      }
    }
  }

  String? get fcmToken => _fcmToken;
  String? _lastSyncedToken;
  String? _lastSyncedUserId;
  DateTime? _lastTokenSyncTime;
  static const Duration _minTokenSyncInterval = Duration(minutes: 5);

  /// Sends device FCM token to backend for push notification routing
  Future<void> syncTokenWithBackend(WidgetRef ref, [String? token, bool force = false]) async {
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

      final now = DateTime.now();
      if (!force &&
          _lastSyncedUserId == authUser.id &&
          _lastSyncedToken == tokenToSync &&
          _lastTokenSyncTime != null &&
          now.difference(_lastTokenSyncTime!) < _minTokenSyncInterval) {
        // Skip redundant sync: identical token already registered recently
        return;
      }

      final apiClient = ref.read(apiClientProvider);
      await apiClient.dio.post(
        '/api/auth/fcm-token',
        data: {'fcmToken': tokenToSync},
      );

      _lastSyncedUserId = authUser.id;
      _lastSyncedToken = tokenToSync;
      _lastTokenSyncTime = DateTime.now();

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

    // Trigger incoming VIP call dialog for foreground instant_call alerts
    if (type == 'instant_call') {
      final sessionId = data['sessionId']?.toString() ?? '';
      final bidAmount = int.tryParse(data['bidAmount']?.toString() ?? '10') ?? 10;
      debugPrint('🔔 [FCM Foreground] Instant VIP call received: session=$sessionId, bid=$bidAmount');
      onInstantCallNotification?.call(sessionId: sessionId, bidAmount: bidAmount);
      return;
    }

    // Do NOT show in-app chat banner for standard call notifications
    if (type == 'incoming_call') {
      debugPrint('🔔 [FCM Foreground] Standard incoming call received. Suppressing chat banner.');
      return;
    }

    final notification = message.notification;

    final groupId = data['groupId']?.toString();
    final isGroup = type == 'BUDDY_GROUP_MESSAGE' || (groupId != null && groupId.isNotEmpty);

    final senderId = data['senderId']?.toString() ?? data['userId']?.toString() ?? (isGroup ? groupId! : '');
    final senderName = data['senderName']?.toString() ??
        data['userName']?.toString() ??
        (isGroup ? (data['title']?.toString() ?? 'Garba Buddy Group') : null) ??
        notification?.title?.replaceAll('New message from ', '') ??
        'User';
    final messageBody = data['message']?.toString() ??
        data['text']?.toString() ??
        notification?.body ??
        'Sent you a new message';
    final conversationId = data['conversationId']?.toString() ?? groupId ?? (senderId.isNotEmpty ? 'user:$senderId' : '');
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
        isGroup: isGroup,
        groupId: groupId,
      ));
    }
  }

  void _handleInitialMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString();
    final groupId = data['groupId']?.toString();

    if (type == 'BUDDY_GROUP_MESSAGE' || (groupId != null && groupId.isNotEmpty)) {
      final title = data['title']?.toString() ?? 'Garba Buddy Group';
      _pendingGroupNotification = PendingGroupNotification(groupId: groupId!, title: title);
      debugPrint('🔔 [FCM Terminated] Cached pending buddy group notification: $groupId');
      return;
    }

    if (type == 'instant_call') {
      final sessionId = data['sessionId']?.toString() ?? '';
      final bidAmount = int.tryParse(data['bidAmount']?.toString() ?? '10') ?? 10;
      debugPrint('🔔 [FCM Initial Click] Female clicked instant call alert: session=$sessionId, bid=$bidAmount');
      onInstantCallNotification?.call(sessionId: sessionId, bidAmount: bidAmount);
      return;
    }

    if (type == 'incoming_call') {
      debugPrint('🔔 [FCM Initial Click] Opened app for live standard call alert');
      return;
    }

    final senderId = data['senderId']?.toString() ?? data['userId']?.toString() ?? '';
    final senderName = data['senderName']?.toString() ?? data['userName']?.toString() ?? 'User';
    final conversationId = data['conversationId']?.toString() ?? (senderId.isNotEmpty ? 'user:$senderId' : '');
    final avatar = data['avatar']?.toString() ?? data['senderAvatar']?.toString();
    final avatarSeed = data['avatarSeed']?.toString();
    final avatarStyle = data['avatarStyle']?.toString();
    final gender = data['gender']?.toString();

    if (senderId.isNotEmpty || conversationId.isNotEmpty) {
      _pendingChatNotification = PendingChatNotification(
        conversationId: conversationId,
        userId: senderId,
        userName: senderName,
        userAvatar: avatar,
        avatarSeed: avatarSeed,
        avatarStyle: avatarStyle,
        gender: gender,
      );
      debugPrint('🔔 [FCM Terminated] Cached pending chat notification for $senderName ($conversationId)');
    }
  }

  void _handleNotificationClick(RemoteMessage message) {
    final data = message.data;
    final type = data['type']?.toString();
    final groupId = data['groupId']?.toString();

    if (type == 'BUDDY_GROUP_MESSAGE' || (groupId != null && groupId.isNotEmpty)) {
      final title = data['title']?.toString() ?? 'Garba Buddy Group';
      debugPrint('🔔 [FCM Click] User clicked buddy group notification: $groupId');
      onOpenBuddyGroup?.call(groupId: groupId!, title: title);
      return;
    }

    if (type == 'instant_call') {
      final sessionId = data['sessionId']?.toString() ?? '';
      final bidAmount = int.tryParse(data['bidAmount']?.toString() ?? '10') ?? 10;
      debugPrint('🔔 [FCM Click] Female clicked instant call alert: session=$sessionId, bid=$bidAmount');
      onInstantCallNotification?.call(sessionId: sessionId, bidAmount: bidAmount);
      return;
    }

    if (type == 'incoming_call') {
      debugPrint('🔔 [FCM Click] Opened app for live standard call alert');
      return;
    }

    final senderId = data['senderId']?.toString() ?? data['userId']?.toString() ?? '';
    final senderName = data['senderName']?.toString() ?? data['userName']?.toString() ?? 'User';
    final conversationId = data['conversationId']?.toString() ?? (senderId.isNotEmpty ? 'user:$senderId' : '');
    final avatar = data['avatar']?.toString() ?? data['senderAvatar']?.toString();
    final avatarSeed = data['avatarSeed']?.toString();
    final avatarStyle = data['avatarStyle']?.toString();
    final gender = data['gender']?.toString();

    if (senderId.isNotEmpty || conversationId.isNotEmpty) {
      onOpenChat?.call(
        conversationId: conversationId,
        userId: senderId,
        userName: senderName,
        userAvatar: avatar,
        avatarSeed: avatarSeed,
        avatarStyle: avatarStyle,
        gender: gender,
      );
    }
  }
}

/// Provider for NotificationService
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});
