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
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val.toLocal();
      final parsed = DateTime.tryParse(val.toString());
      if (parsed == null) return DateTime.now();
      return parsed.toLocal();
    }

    return Message(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      conversationId: (json['conversation_id'] ?? json['conversationId'] ?? '').toString(),
      senderId: (json['sender_id'] ?? json['senderId'] ?? json['userId'] ?? '').toString(),
      content: (json['content'] ?? json['text'] ?? json['message'] ?? '').toString(),
      mediaUrl: (json['media_url'] ?? json['mediaUrl'] ?? json['imageUrl'])?.toString(),
      type: (json['type'] ?? 'text').toString(),
      status: (json['status'] ?? 'sent').toString(),
      createdAt: parseDate(json['created_at'] ?? json['createdAt']),
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
