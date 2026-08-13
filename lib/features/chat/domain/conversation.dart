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
    return Conversation(
      id: json['id'] as String,
      otherUserId: json['otherUserId'] as String,
      otherUserName: json['otherUserName'] as String? ?? 'User',
      otherUserAvatarSeed: json['otherUserAvatarSeed'] as String?,
      otherUserAvatarStyle: json['otherUserAvatarStyle'] as String? ?? 'avataaars',
      otherUserGender: json['otherUserGender'] as String?,
      otherUserAvatar: (json['otherUserAvatar'] ?? json['other_user_avatar_url']) as String?,
      lastMessage: json['lastMessage'] as String?,
      lastMessageType: json['lastMessageType'] as String?,
      lastMessageSenderId: json['lastMessageSenderId'] as String?,
      lastMessageAt: json['lastMessageAt'] != null
          ? DateTime.parse(json['lastMessageAt'] as String)
          : DateTime.now(),
      unreadCount: json['unreadCount'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
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
