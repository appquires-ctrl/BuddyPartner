class Conversation {
  final String id;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatarSeed;
  final String? otherUserAvatarStyle;
  final String? otherUserGender;
  final String? otherUserAvatar;
  final String? lastMessage;
  final String? lastMessageType;
  final String? lastMessageSenderId;
  final DateTime lastMessageAt;
  final int unreadCount;
  final DateTime createdAt;

  const Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatarSeed,
    this.otherUserAvatarStyle,
    this.otherUserGender,
    this.otherUserAvatar,
    this.lastMessage,
    this.lastMessageType,
    this.lastMessageSenderId,
    required this.lastMessageAt,
    this.unreadCount = 0,
    required this.createdAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val.toLocal();
      final parsed = DateTime.tryParse(val.toString());
      if (parsed == null) return DateTime.now();
      return parsed.toLocal();
    }

    int parseUnreadCount(dynamic val) {
      if (val == null) return 0;
      if (val is num) return val.toInt();
      return int.tryParse(val.toString()) ?? 0;
    }

    return Conversation(
      id: (json['id'] ?? json['_id'] ?? json['conversation_id'] ?? '').toString(),
      otherUserId: (json['otherUserId'] ?? json['other_user_id'] ?? json['userId'] ?? '').toString(),
      otherUserName: (json['otherUserName'] ?? json['other_user_name'] ?? json['name'] ?? 'User').toString(),
      otherUserAvatarSeed: json['otherUserAvatarSeed']?.toString() ?? json['other_user_avatar_seed']?.toString(),
      otherUserAvatarStyle: json['otherUserAvatarStyle']?.toString() ?? json['other_user_avatar_style']?.toString() ?? 'avataaars',
      otherUserGender: json['otherUserGender']?.toString() ?? json['other_user_gender']?.toString() ?? json['gender']?.toString(),
      otherUserAvatar: json['otherUserAvatar']?.toString() ?? json['other_user_avatar_url']?.toString(),
      lastMessage: json['lastMessage']?.toString() ?? json['last_message_content']?.toString(),
      lastMessageType: json['lastMessageType']?.toString() ?? json['last_message_type']?.toString(),
      lastMessageSenderId: json['lastMessageSenderId']?.toString() ?? json['last_message_sender_id']?.toString(),
      lastMessageAt: parseDate(json['lastMessageAt'] ?? json['last_message_at']),
      unreadCount: parseUnreadCount(json['unreadCount'] ?? json['unread_count']),
      createdAt: parseDate(json['createdAt'] ?? json['created_at']),
    );
  }

  Conversation copyWith({
    String? id,
    String? otherUserId,
    String? otherUserName,
    String? lastMessage,
    String? lastMessageType,
    String? lastMessageSenderId,
    DateTime? lastMessageAt,
    int? unreadCount,
    DateTime? createdAt,
  }) {
    return Conversation(
      id: id ?? this.id,
      otherUserId: otherUserId ?? this.otherUserId,
      otherUserName: otherUserName ?? this.otherUserName,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
