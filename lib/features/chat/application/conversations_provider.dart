import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/core/services/socket_provider.dart';
import 'package:dating_app/features/chat/data/chat_repository.dart';
import 'package:dating_app/features/chat/domain/conversation.dart';
import 'package:dating_app/features/chat/domain/message.dart';

class ConversationsNotifier extends AutoDisposeAsyncNotifier<List<Conversation>> {
  @override
  FutureOr<List<Conversation>> build() async {
    final socket = ref.watch(socketProvider);
    
    if (socket != null) {
      socket.off('message:new', _onNewMessage);

      socket.on('message:new', _onNewMessage);

      ref.onDispose(() {
        socket.off('message:new', _onNewMessage);
      });
    }

    return _fetchConversations();
  }

  Future<List<Conversation>> _fetchConversations() async {
    final repo = ref.read(chatRepositoryProvider);
    return await repo.fetchConversations();
  }

  void _onNewMessage(dynamic data) {
    if (data == null) return;
    
    try {
      final msgMap = data['message'] as Map<String, dynamic>;
      final msg = Message.fromJson(msgMap);
      
      final currentList = state.value;
      if (currentList == null) return;
      
      final index = currentList.indexWhere((c) => c.id == msg.conversationId);
      
      if (index >= 0) {
        // Update existing conversation
        final updatedList = List<Conversation>.from(currentList);
        final conv = updatedList[index];
        
        updatedList[index] = conv.copyWith(
          lastMessage: msg.content,
          lastMessageType: msg.type,
          lastMessageSenderId: msg.senderId,
          lastMessageAt: msg.createdAt,
          unreadCount: conv.unreadCount + 1, // Will be zeroed out if the user is in the chat view
        );
        
        // Move to top
        final movedConv = updatedList.removeAt(index);
        updatedList.insert(0, movedConv);
        
        state = AsyncData(updatedList);
      } else {
        // New conversation, fetch the full list again to get the updated profile data
        ref.invalidateSelf();
      }
    } catch (e) {
      // Ignore parse errors on socket messages
    }
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
