import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/core/services/socket_provider.dart';
import 'package:dating_app/features/chat/data/chat_repository.dart';
import 'package:dating_app/features/chat/domain/message.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'package:dating_app/features/chat/application/conversations_provider.dart';

import 'package:dating_app/features/auth/application/auth_error_mapper.dart';

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
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      nextCursor: nextCursor ?? this.nextCursor,
      typingUserId: clearTypingUser ? null : (typingUserId ?? this.typingUserId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ChatController extends AutoDisposeFamilyNotifier<ChatState, String> {
  Timer? _typingTimer;
  bool _built = false;
  String? _resolvedConvId;

  String get effectiveConversationId => _resolvedConvId ?? arg;

  @override
  ChatState build(String arg) {
    final socket = ref.watch(socketProvider);
    
    if (socket != null) {
      socket.off('message:new', _onNewMessage);
      socket.off('typing', _onTyping);
      socket.off('message:read', _onMessageRead);
      socket.off('message:status_update', _onStatusUpdate);

      socket.on('message:new', _onNewMessage);
      socket.on('typing', _onTyping);
      socket.on('message:read', _onMessageRead);
      socket.on('message:status_update', _onStatusUpdate);

      ref.onDispose(() {
        socket.off('message:new', _onNewMessage);
        socket.off('typing', _onTyping);
        socket.off('message:read', _onMessageRead);
        socket.off('message:status_update', _onStatusUpdate);
        _typingTimer?.cancel();
        ref.invalidate(conversationsProvider);
      });
    }

    if (!_built) {
      _built = true;
      Future.microtask(() => loadInitial());
      return const ChatState();
    }

    return state;
  }

  String get conversationId => effectiveConversationId;

  Future<void> loadInitial() async {
    final repo = ref.read(chatRepositoryProvider);
    
    try {
      state = state.copyWith(isLoading: true, clearError: true);
      String convId = arg;

      // Handle instant navigation where arg is passed as 'user:$userId'
      if (convId.startsWith('user:')) {
        final targetUserId = convId.substring(5);
        final conv = await repo.findOrCreateConversation(targetUserId);
        convId = conv.id;
        _resolvedConvId = conv.id;
      }

      final result = await repo.fetchMessages(convId);
      
      final msgs = result['messages'] as List<Message>;
      final next = result['nextCursor'] as String?;
      
      state = state.copyWith(
        messages: msgs,
        nextCursor: next,
        hasMore: next != null,
        isLoading: false,
        clearError: true,
      );
      
      // Mark latest as read if not empty
      if (msgs.isNotEmpty) {
        _markAsRead(msgs.first.id);
      }
    } catch (e, st) {
      debugPrint('Error in loadInitial: $e\n$st');
      final cleanMessage = AuthErrorMapper.mapMessage(e);
      state = state.copyWith(isLoading: false, hasMore: false, errorMessage: cleanMessage);
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.nextCursor == null) return;
    
    final repo = ref.read(chatRepositoryProvider);
    final convId = effectiveConversationId;
    if (convId.startsWith('user:')) return;
    
    try {
      state = state.copyWith(isLoading: true);
      final result = await repo.fetchMessages(
        convId, 
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
      final cleanMessage = AuthErrorMapper.mapMessage(e);
      state = state.copyWith(isLoading: false, hasMore: false, errorMessage: cleanMessage);
    }
  }

  void sendMessage(String content) {
    if (content.trim().isEmpty) return;
    final socket = ref.read(socketProvider);
    final convId = effectiveConversationId;
    if (convId.startsWith('user:')) return;
    
    final authState = ref.read(authStateProvider).value;
    final currentUserId = authState?.id ?? 'me';
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';

    final tempMsg = Message(
      id: tempId,
      conversationId: convId,
      senderId: currentUserId,
      content: content.trim(),
      type: 'text',
      status: 'sending',
      createdAt: DateTime.now(),
    );

    // 🚀 INSTANT (0ms) Optimistic UI Update: Prepend message to list immediately!
    state = state.copyWith(
      messages: [tempMsg, ...state.messages],
    );

    // Invalidate conversations list so Messages tab is updated instantly in background
    ref.invalidate(conversationsProvider);

    // Dispatch message to server in background
    if (socket != null && socket.connected) {
      socket.emitWithAck('send_message', {
        'conversationId': convId,
        'content': content.trim(),
        'type': 'text',
      }, ack: (data) {
        if (data != null && data['message'] != null) {
          try {
            final realMsg = Message.fromJson(data['message'] as Map<String, dynamic>);
            _replaceTempMessage(tempId, realMsg);
          } catch (_) {}
        }
      });
    } else {
      // Fallback to REST
      final repo = ref.read(chatRepositoryProvider);
      repo.sendMessage(convId, content.trim()).then((realMsg) {
        _replaceTempMessage(tempId, realMsg);
      }).catchError((_) {
        _markMessageFailed(tempId);
      });
    }
  }

  void _replaceTempMessage(String tempId, Message realMsg) {
    final updatedMsgs = state.messages.map((m) {
      if (m.id == tempId) {
        return realMsg;
      }
      return m;
    }).toList();

    // Deduplicate in case socket event already arrived
    final seen = <String>{};
    final deduped = <Message>[];
    for (final m in updatedMsgs) {
      if (seen.add(m.id)) {
        deduped.add(m);
      }
    }

    state = state.copyWith(messages: deduped);
  }

  void _markMessageFailed(String tempId) {
    final updatedMsgs = state.messages.map((m) {
      if (m.id == tempId) {
        return m.copyWith(status: 'failed');
      }
      return m;
    }).toList();
    state = state.copyWith(messages: updatedMsgs);
  }

  void sendTyping() {
    final socket = ref.read(socketProvider);
    final convId = effectiveConversationId;
    if (convId.startsWith('user:')) return;

    if (socket != null && socket.connected) {
      socket.emit('typing', {'conversationId': convId});
    }
  }

  void _markAsRead(String messageId) {
    final socket = ref.read(socketProvider);
    final convId = effectiveConversationId;
    if (convId.startsWith('user:')) return;

    if (socket != null && socket.connected) {
      socket.emit('message:read', {
        'conversationId': convId,
        'messageId': messageId,
      });
    }
  }

  void _onNewMessage(dynamic data) {
    if (data == null) return;
    try {
      final msgMap = data['message'] as Map<String, dynamic>;
      final msg = Message.fromJson(msgMap);
      
      if (msg.conversationId == effectiveConversationId) {
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
      if (data['conversationId'] == effectiveConversationId) {
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
      if (data['conversationId'] == effectiveConversationId) {
        final updatedMsgs = state.messages.map((m) {
          return m.status != 'read' ? m.copyWith(status: 'read') : m;
        }).toList();
        
        state = state.copyWith(messages: updatedMsgs);
      }
    } catch (_) {}
  }

  void _onStatusUpdate(dynamic data) {
    if (data == null) return;
    try {
      if (data['conversationId'] == effectiveConversationId) {
        final targetMsgId = data['messageId'] as String?;
        final newStatus = data['status'] as String?;

        if (newStatus == null) return;

        final updatedMsgs = state.messages.map((m) {
          if (targetMsgId != null) {
            if (m.id == targetMsgId) {
              return m.copyWith(status: newStatus);
            }
            return m;
          } else if (newStatus == 'read') {
            return m.copyWith(status: 'read');
          }
          return m;
        }).toList();

        state = state.copyWith(messages: updatedMsgs);
      }
    } catch (_) {}
  }
}

final chatControllerProvider = AutoDisposeNotifierProviderFamily<ChatController, ChatState, String>(
  ChatController.new,
);
