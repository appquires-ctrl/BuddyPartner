import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/core/services/socket_provider.dart';
import 'package:dating_app/features/chat/data/chat_repository.dart';
import 'package:dating_app/features/chat/domain/conversation.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

class ConversationsNotifier extends AutoDisposeAsyncNotifier<List<Conversation>> {
  Timer? _syncTimer;

  @override
  FutureOr<List<Conversation>> build() async {
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

    // 🚀 Fail-Safe Real-Time Periodic Sync (Every 3 seconds)
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _syncConversationsSilently();
    });

    ref.onDispose(() {
      _syncTimer?.cancel();
      if (socket != null) {
        socket.off('message:new', _handleIncomingMessage);
        socket.off('new_message', _handleIncomingMessage);
        socket.off('conversation:updated', _handleIncomingMessage);
        socket.off('conversation:new', _handleConversationEvent);
      }
    });

    return _fetchConversations();
  }

  Future<List<Conversation>> _fetchConversations() async {
    final repo = ref.read(chatRepositoryProvider);
    return await repo.fetchConversations();
  }

  /// Silently background-syncs conversations without showing loading spinners or flickering
  Future<void> _syncConversationsSilently() async {
    try {
      final latest = await _fetchConversations();
      final current = state.value;
      if (current == null || !_isSameConversationList(current, latest)) {
        state = AsyncData(latest);
      }
    } catch (_) {}
  }

  bool _isSameConversationList(List<Conversation> a, List<Conversation> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].lastMessage != b[i].lastMessage ||
          a[i].unreadCount != b[i].unreadCount ||
          a[i].lastMessageAt != b[i].lastMessageAt) {
        return false;
      }
    }
    return true;
  }

  /// Robust multi-format incoming message handler.
  /// Instantly updates preview text, timestamp, unread badge, and moves card to top.
  void _handleIncomingMessage(dynamic data) {
    if (data == null) return;
    
    try {
      Map<String, dynamic>? msgMap;
      if (data is Map<String, dynamic>) {
        if (data.containsKey('message') && data['message'] is Map<String, dynamic>) {
          msgMap = data['message'] as Map<String, dynamic>;
        } else {
          msgMap = data;
        }
      }

      if (msgMap == null) return;

      final conversationId = (msgMap['conversationId'] ?? msgMap['conversation_id']) as String?;
      if (conversationId == null || conversationId.isEmpty) return;

      final content = (msgMap['content'] ?? msgMap['text'] ?? '') as String;
      final senderId = (msgMap['senderId'] ?? msgMap['sender_id'] ?? msgMap['userId']) as String?;
      final type = (msgMap['type'] ?? 'text') as String;
      final createdAtRaw = msgMap['createdAt'] ?? msgMap['created_at'];
      final createdAt = createdAtRaw != null
          ? DateTime.tryParse(createdAtRaw.toString()) ?? DateTime.now()
          : DateTime.now();

      final currentList = state.value;
      if (currentList == null) return;

      final authState = ref.read(authStateProvider).value;
      final currentUserId = authState?.id;
      final isMe = senderId != null && senderId == currentUserId;

      final index = currentList.indexWhere((c) => c.id == conversationId);

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
    } catch (e, st) {
      debugPrint('Error in _handleIncomingMessage: $e\n$st');
    }
  }

  void _handleConversationEvent(dynamic data) {
    _fetchConversations().then((newList) {
      state = AsyncData(newList);
    }).catchError((_) {});
  }
  
  /// Refreshes the list manually (e.g. for pull-to-refresh)
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchConversations);
  }
}

final conversationsProvider = AutoDisposeAsyncNotifierProvider<ConversationsNotifier, List<Conversation>>(
  ConversationsNotifier.new,
);
