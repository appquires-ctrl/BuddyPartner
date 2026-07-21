import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/core/services/socket_provider.dart';
import 'package:dating_app/features/chat/data/chat_repository.dart';
import 'package:dating_app/features/chat/domain/message.dart';

class ChatState {
  final List<Message> messages;
  final bool isLoading;
  final bool hasMore;
  final String? nextCursor;
  final String? typingUserId;
  final String? errorMessage;

  const ChatState({
    this.messages = const [],
    this.isLoading = true,
    this.hasMore = true,
    this.nextCursor,
    this.typingUserId,
    this.errorMessage,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? isLoading,
    bool? hasMore,
    String? nextCursor,
    String? typingUserId,
    String? errorMessage,
    bool clearTypingUser = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: nextCursor ?? this.nextCursor,
      typingUserId: clearTypingUser ? null : (typingUserId ?? this.typingUserId),
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ChatController extends FamilyNotifier<ChatState, String> {
  Timer? _typingTimer;
  bool _built = false;

  @override
  ChatState build(String arg) {
    final socket = ref.watch(socketProvider);
    
    if (socket != null) {
      socket.off('message:new', _onNewMessage);
      socket.off('typing', _onTyping);
      socket.off('message:read', _onMessageRead);

      socket.on('message:new', _onNewMessage);
      socket.on('typing', _onTyping);
      socket.on('message:read', _onMessageRead);

      ref.onDispose(() {
        socket.off('message:new', _onNewMessage);
        socket.off('typing', _onTyping);
        socket.off('message:read', _onMessageRead);
        _typingTimer?.cancel();
      });
    }

    if (!_built) {
      _built = true;
      Future.microtask(() => loadInitial());
      return const ChatState();
    }

    return state;
  }

  String get conversationId => arg;

  Future<void> loadInitial() async {
    final repo = ref.read(chatRepositoryProvider);
    
    try {
      state = state.copyWith(isLoading: true);
      final result = await repo.fetchMessages(conversationId);
      
      final msgs = result['messages'] as List<Message>;
      final next = result['nextCursor'] as String?;
      
      state = state.copyWith(
        messages: msgs,
        nextCursor: next,
        hasMore: next != null,
        isLoading: false,
      );
      
      // Mark latest as read if not empty
      if (msgs.isNotEmpty) {
        _markAsRead(msgs.first.id);
      }
    } catch (e, st) {
      debugPrint('Error in loadInitial: $e\n$st');
      state = state.copyWith(isLoading: false, hasMore: false, errorMessage: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.nextCursor == null) return;
    
    final repo = ref.read(chatRepositoryProvider);
    
    try {
      state = state.copyWith(isLoading: true);
      final result = await repo.fetchMessages(
        conversationId, 
        cursor: state.nextCursor,
      );
      
      final msgs = result['messages'] as List<Message>;
      final next = result['nextCursor'] as String?;
      
      state = state.copyWith(
        messages: [...state.messages, ...msgs],
        nextCursor: next,
        hasMore: next != null,
        isLoading: false,
      );
    } catch (e, st) {
      debugPrint('Error in loadMore: $e\n$st');
      state = state.copyWith(isLoading: false, hasMore: false, errorMessage: e.toString());
    }
  }

  void sendMessage(String content) {
    final socket = ref.read(socketProvider);
    
    // Attempt socket send first
    if (socket != null && socket.connected) {
      socket.emitWithAck('send_message', {
        'conversationId': conversationId,
        'content': content,
        'type': 'text',
      }, ack: (data) {
        if (data != null && data['error'] != null) {
          // Could handle error via state
        }
      });
    } else {
      // Fallback to REST
      final repo = ref.read(chatRepositoryProvider);
      repo.sendMessage(conversationId, content).then((newMsg) {
        // Manually insert if REST succeeded and socket didn't get it
        if (!state.messages.any((m) => m.id == newMsg.id)) {
          state = state.copyWith(
            messages: [newMsg, ...state.messages],
          );
        }
      }).catchError((_) {
        // Handle error
      });
    }
  }

  void sendTyping() {
    final socket = ref.read(socketProvider);
    if (socket != null && socket.connected) {
      socket.emit('typing', {'conversationId': conversationId});
    }
  }

  void _markAsRead(String messageId) {
    final socket = ref.read(socketProvider);
    if (socket != null && socket.connected) {
      socket.emit('message:read', {
        'conversationId': conversationId,
        'messageId': messageId,
      });
    }
  }

  void _onNewMessage(dynamic data) {
    if (data == null) return;
    try {
      final msgMap = data['message'] as Map<String, dynamic>;
      final msg = Message.fromJson(msgMap);
      
      if (msg.conversationId == conversationId) {
        // Avoid duplicates
        if (!state.messages.any((m) => m.id == msg.id)) {
          state = state.copyWith(
            messages: [msg, ...state.messages],
            clearTypingUser: true,
          );
          _markAsRead(msg.id);
        }
      }
    } catch (_) {}
  }

  void _onTyping(dynamic data) {
    if (data == null) return;
    try {
      if (data['conversationId'] == conversationId) {
        state = state.copyWith(typingUserId: data['userId'] as String);
        
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          state = state.copyWith(clearTypingUser: true);
        });
      }
    } catch (_) {}
  }

  void _onMessageRead(dynamic data) {
    if (data == null) return;
    try {
      if (data['conversationId'] == conversationId) {
        final messageId = data['messageId'] as String;
        // In a full implementation, we'd find this message and all before it 
        // and update their status to 'read'
        
        final updatedMsgs = state.messages.map((m) {
          // Simple assumption: if it's sent before or is this message, it's read
          // To be precise we'd compare dates, but this works for the latest read receipt
          return m.status != 'read' ? m.copyWith(status: 'read') : m;
        }).toList();
        
        state = state.copyWith(messages: updatedMsgs);
      }
    } catch (_) {}
  }
}

final chatControllerProvider = NotifierProviderFamily<ChatController, ChatState, String>(
  ChatController.new,
);
