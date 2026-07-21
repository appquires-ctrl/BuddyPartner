class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? mediaUrl;
  final String type; // 'text', 'image', 'system'
  final String status; // 'sent', 'delivered', 'read'
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.mediaUrl,
    this.type = 'text',
    this.status = 'sent',
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String? ?? '',
      conversationId: json['conversation_id'] as String? ?? '',
      senderId: json['sender_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      mediaUrl: json['media_url'] as String?,
      type: json['type'] as String? ?? 'text',
      status: json['status'] as String? ?? 'sent',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    String? mediaUrl,
    String? type,
    String? status,
    DateTime? createdAt,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
