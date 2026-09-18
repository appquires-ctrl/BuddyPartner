import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/socket_provider.dart';
import 'package:buddypartner/features/chat/data/chat_repository.dart';
import 'package:buddypartner/features/chat/domain/conversation.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/core/widgets/feedback/in_app_notification_banner.dart';

class ConversationsNotifier extends AsyncNotifier<List<Conversation>> {
  Future<List<Conversation>>? _inFlightFetch;
  DateTime? _lastFetchTime;
  static const Duration _cacheDuration = Duration(seconds: 15);

  @override
  FutureOr<List<Conversation>> build() async {
    final authUser = ref.watch(authStateProvider).value;
    if (authUser == null) return const [];

    final socket = ref.watch(socketProvider);
    
    if (socket != null) {
      // Clean up any old event listeners
      socket.off('message:new', _handleIncomingMessage);
      socket.off('new_message', _handleIncomingMessage);
      socket.off('conversation:updated', _handleIncomingMessage);
      socket.off('conversation:new', _handleConversationEvent);

      // Subscribe to real-time events
      socket.on('message:new', _handleIncomingMessage);
      socket.on('new_message', _handleIncomingMessage);
      socket.on('conversation:updated', _handleIncomingMessage);
      socket.on('conversation:new', _handleConversationEvent);
    }

    ref.onDispose(() {
      if (socket != null) {
        socket.off('message:new', _handleIncomingMessage);
        socket.off('new_message', _handleIncomingMessage);
        socket.off('conversation:updated', _handleIncomingMessage);
        socket.off('conversation:new', _handleConversationEvent);
      }
    });

    return _fetchConversations();
  }

  Future<List<Conversation>> _fetchConversations({bool force = false}) async {
    final now = DateTime.now();
    if (!force && state.hasValue && _lastFetchTime != null && now.difference(_lastFetchTime!) < _cacheDuration) {
      return state.value!;
    }

    if (_inFlightFetch != null) return _inFlightFetch!;

    _inFlightFetch = _executeFetch();
    try {
      return await _inFlightFetch!;
    } finally {
      _inFlightFetch = null;
    }
  }

  Future<List<Conversation>> _executeFetch() async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      final list = await repo.fetchConversations();
      _lastFetchTime = DateTime.now();
      return list;
    } catch (_) {
      return state.value ?? const [];
    }
  }

  /// Robust multi-format incoming message handler.
  /// Instantly updates preview text, timestamp, unread badge, and moves card to top.
  void _handleIncomingMessage(dynamic data) {
    if (data == null) return;
    
    try {
      Map<dynamic, dynamic>? rawMap;
      if (data is Map) {
        if (data.containsKey('message') && data['message'] is Map) {
          rawMap = data['message'] as Map;
        } else {
          rawMap = data;
        }
      }

      if (rawMap == null) return;
      final msgMap = Map<String, dynamic>.from(rawMap);

      final conversationId = (msgMap['conversationId'] ?? msgMap['conversation_id'])?.toString();
      final content = (msgMap['content'] ?? msgMap['text'] ?? msgMap['message'] ?? '').toString();
      final senderId = (msgMap['senderId'] ?? msgMap['sender_id'] ?? msgMap['userId'])?.toString();
      final type = (msgMap['type'] ?? 'text').toString();
      final createdAtRaw = msgMap['createdAt'] ?? msgMap['created_at'];
      final createdAt = createdAtRaw != null
          ? (DateTime.tryParse(createdAtRaw.toString()) ?? DateTime.now())
          : DateTime.now();

      final currentList = state.value ?? [];

      final authState = ref.read(authStateProvider).value;
      final currentUserId = authState?.id;
      final isMe = senderId != null && senderId == currentUserId;

      final index = currentList.indexWhere((c) =>
          (conversationId != null && c.id == conversationId) ||
          (senderId != null && c.otherUserId == senderId));

      if (index >= 0) {
        // Conversation exists -> Update item & reorder to top immediately (0ms delay)
        final updatedList = List<Conversation>.from(currentList);
        final conv = updatedList.removeAt(index);

        final updatedConv = conv.copyWith(
          lastMessage: content,
          lastMessageType: type,
          lastMessageSenderId: senderId,
          lastMessageAt: createdAt,
          unreadCount: isMe ? 0 : conv.unreadCount + 1,
        );

        // Move conversation card to the very top (index 0)
        updatedList.insert(0, updatedConv);

        // Emit AsyncData instantly without full screen reloads/flicker
        state = AsyncData(updatedList);
      } else {
        // New conversation from a new contact -> Fetch full list in background
        _fetchConversations().then((newList) {
          state = AsyncData(newList);
        }).catchError((e) {
          debugPrint('Error fetching conversations on new message: $e');
        });
      }

      // If message is from another user, show in-app notification banner
      if (!isMe && senderId != null && senderId.isNotEmpty) {
        String senderName = 'User';
        String? senderAvatar;
        String? avatarSeed;
        String? avatarStyle;
        String? gender;

        if (index >= 0) {
          final conv = currentList[index];
          senderName = conv.otherUserName;
          senderAvatar = conv.otherUserAvatar;
          avatarSeed = conv.otherUserAvatarSeed;
          avatarStyle = conv.otherUserAvatarStyle;
          gender = conv.otherUserGender;
        } else if (msgMap['sender'] is Map) {
          final senderMap = msgMap['sender'] as Map;
          senderName = senderMap['fullName']?.toString() ?? senderMap['name']?.toString() ?? 'User';
          senderAvatar = senderMap['avatar']?.toString();
          avatarSeed = senderMap['avatarSeed']?.toString();
          avatarStyle = senderMap['avatarStyle']?.toString();
          gender = senderMap['gender']?.toString();
        }

        InAppNotificationManager.show(InAppMessageNotification(
          senderId: senderId,
          senderName: senderName,
          senderAvatar: senderAvatar,
          avatarSeed: avatarSeed,
          avatarStyle: avatarStyle,
          gender: gender,
          message: content.isNotEmpty ? content : 'Sent you a new message',
          conversationId: conversationId ?? 'user:$senderId',
        ));
      }
    } catch (e, st) {
      debugPrint('Error in _handleIncomingMessage: $e\n$st');
    }
  }

  void _handleConversationEvent(dynamic data) {
    _fetchConversations().then((newList) {
      state = AsyncData(newList);
    }).catchError((_) {});
  }

  /// Instantly marks a conversation as read and resets its unread badge to 0
  void markConversationAsRead(String conversationId) {
    final currentList = state.value;
    if (currentList == null || currentList.isEmpty) return;

    final targetId = conversationId.startsWith('user:') ? conversationId.substring(5) : conversationId;
    final index = currentList.indexWhere((c) => c.id == targetId || c.otherUserId == targetId || c.id == conversationId);

    if (index >= 0 && currentList[index].unreadCount > 0) {
      final updatedList = List<Conversation>.from(currentList);
      updatedList[index] = updatedList[index].copyWith(unreadCount: 0);
      state = AsyncData(updatedList);
    }
  }
  
  /// Refreshes the list manually (e.g. for pull-to-refresh)
  Future<void> refresh() async {
    final freshList = await _fetchConversations();
    state = AsyncData(freshList);
  }
}

final conversationsProvider = AsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
  ConversationsNotifier.new,
);

/// Computes the total unread messages count for the current user.
final totalUnreadMessagesCountProvider = Provider<int>((ref) {
  final currentUserId = ref.watch(authStateProvider).value?.id;
  final convs = ref.watch(conversationsProvider).valueOrNull ?? const [];
  return convs.where((c) {
    final isSentByMe = c.lastMessageSenderId == currentUserId;
    return !isSentByMe && c.unreadCount > 0;
  }).fold<int>(0, (sum, c) => sum + c.unreadCount);
});
