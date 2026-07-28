import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/core/services/api_client.dart';
import 'package:dating_app/features/chat/domain/conversation.dart';
import 'package:dating_app/features/chat/domain/message.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(apiClientProvider));
});

class ChatRepository {
  final ApiClient _apiClient;

  ChatRepository(this._apiClient);

  Future<List<Conversation>> fetchConversations() async {
    final response = await _apiClient.dio.get('/api/conversations');
    final data = response.data['conversations'] as List;
    return data.map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Conversation> findOrCreateConversation(String otherUserId) async {
    final response = await _apiClient.dio.post('/api/conversations', data: {
      'otherUserId': otherUserId,
    });
    // The backend might return the DB row (snake_case) rather than the projected DTO for GET, 
    // so we map the result to a usable Conversation model.
    final convMap = response.data['conversation'] as Map<String, dynamic>;
    return Conversation(
      id: convMap['id'],
      otherUserId: otherUserId, // since we know who we asked for
      otherUserName: 'User', // Will be fetched when listing conversations
      lastMessageAt: convMap['last_message_at'] != null ? DateTime.parse(convMap['last_message_at']) : DateTime.now(),
      createdAt: convMap['created_at'] != null ? DateTime.parse(convMap['created_at']) : DateTime.now(),
    );
  }

  Future<Map<String, dynamic>> fetchMessages(String conversationId, {String? cursor, int limit = 30}) async {
    final queryParams = {
      'limit': limit.toString(),
      if (cursor != null) 'cursor': cursor,
    };
    final response = await _apiClient.dio.get(
      '/api/conversations/$conversationId/messages',
      queryParameters: queryParams,
    );
    
    final messages = (response.data['messages'] as List)
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
    
    return {
      'messages': messages,
      'nextCursor': response.data['nextCursor'],
    };
  }

  Future<Message> sendMessage(String conversationId, String content, {String type = 'text'}) async {
    final response = await _apiClient.dio.post(
      '/api/conversations/$conversationId/messages',
      data: {
        'content': content,
        'type': type,
      },
    );
    return Message.fromJson(response.data['message'] as Map<String, dynamic>);
  }

  Future<void> blockUser(String userId) async {
    await _apiClient.dio.post('/api/block', data: {'userId': userId});
  }

  Future<void> unblockUser(String userId) async {
    await _apiClient.dio.delete('/api/block/$userId');
  }

  Future<void> reportUser({
    required String reportedUserId,
    required String reason,
    String? description,
    String? messageId,
    String? conversationId,
  }) async {
    await _apiClient.dio.post('/api/report', data: {
      'reportedUserId': reportedUserId,
      'reason': reason,
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      if (messageId != null && messageId.trim().isNotEmpty) 'messageId': messageId.trim(),
      if (conversationId != null && conversationId.trim().isNotEmpty) 'conversationId': conversationId.trim(),
    });
  }
}
