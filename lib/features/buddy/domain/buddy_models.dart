import 'package:flutter/material.dart';

/// The 10 supported Buddy Activity types.
enum BuddyType {
  movie(
    id: 'movie',
    title: 'Movie Buddy',
    subtitle: 'Find someone to watch movies with',
    stickerAsset: 'assets/images/stickers/movie_buddy.jpg',
    gradientColors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
    accentColor: Color(0xFF8B5CF6),
  ),
  pizza(
    id: 'pizza',
    title: 'Pizza Buddy',
    subtitle: 'Find someone to grab pizza with',
    stickerAsset: 'assets/images/stickers/pizza_buddy.jpg',
    gradientColors: [Color(0xFFF97316), Color(0xFFEA580C)],
    accentColor: Color(0xFFF97316),
  ),
  coffee(
    id: 'coffee',
    title: 'Coffee Buddy',
    subtitle: 'Find someone for a coffee chat',
    stickerAsset: 'assets/images/stickers/coffee_buddy.jpg',
    gradientColors: [Color(0xFFD97706), Color(0xFFB45309)],
    accentColor: Color(0xFFD97706),
  ),
  hangout(
    id: 'hangout',
    title: 'Hangout Buddy',
    subtitle: 'Find someone to chill and hangout with',
    stickerAsset: 'assets/images/stickers/hangout_buddy.jpg',
    gradientColors: [Color(0xFF06B6D4), Color(0xFF0891B2)],
    accentColor: Color(0xFF06B6D4),
  ),
  trip(
    id: 'trip',
    title: 'Trip Buddy',
    subtitle: 'Find a travel partner for your next trip',
    stickerAsset: 'assets/images/stickers/trip_buddy.jpg',
    gradientColors: [Color(0xFF10B981), Color(0xFF059669)],
    accentColor: Color(0xFF10B981),
  ),
  cricket(
    id: 'cricket',
    title: 'Cricket Buddy',
    subtitle: 'Find a buddy to watch or play cricket',
    stickerAsset: 'assets/images/stickers/cricket_buddy.jpg',
    gradientColors: [Color(0xFF3B82F6), Color(0xFF2563EB)],
    accentColor: Color(0xFF3B82F6),
  ),
  shopping(
    id: 'shopping',
    title: 'Shopping Buddy',
    subtitle: 'Find someone to go shopping with',
    stickerAsset: 'assets/images/stickers/shopping_buddy.jpg',
    gradientColors: [Color(0xFFEC4899), Color(0xFFDB2777)],
    accentColor: Color(0xFFEC4899),
  ),
  nightOut(
    id: 'night_out',
    title: 'Night Out Buddy',
    subtitle: 'Find a partner for a fun night out',
    stickerAsset: 'assets/images/stickers/nightout_buddy.jpg',
    gradientColors: [Color(0xFFA855F7), Color(0xFF7E22CE)],
    accentColor: Color(0xFFA855F7),
  ),
  clubbing(
    id: 'clubbing',
    title: 'Clubbing Buddy',
    subtitle: 'Find a party and clubbing partner',
    stickerAsset: 'assets/images/stickers/clubbing_buddy.jpg',
    gradientColors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
    accentColor: Color(0xFF6366F1),
  ),
  longDrive(
    id: 'long_drive',
    title: 'Long Drive Buddy',
    subtitle: 'Find someone for a scenic long drive',
    stickerAsset: 'assets/images/stickers/longdrive_buddy.jpg',
    gradientColors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
    accentColor: Color(0xFF14B8A6),
  );

  final String id;
  final String title;
  final String subtitle;
  final String stickerAsset;
  final List<Color> gradientColors;
  final Color accentColor;

  const BuddyType({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.stickerAsset,
    required this.gradientColors,
    required this.accentColor,
  });

  static BuddyType fromString(String? val) {
    if (val == null) return BuddyType.movie;
    return BuddyType.values.firstWhere(
      (e) => e.id == val,
      orElse: () => BuddyType.movie,
    );
  }
}

enum BuddyTargetGender {
  male(id: 'male', label: 'Male'),
  female(id: 'female', label: 'Female'),
  all(id: 'all', label: 'All');

  final String id;
  final String label;

  const BuddyTargetGender({required this.id, required this.label});

  static BuddyTargetGender fromString(String? val) {
    if (val == null) return BuddyTargetGender.all;
    return BuddyTargetGender.values.firstWhere(
      (e) => e.id == val,
      orElse: () => BuddyTargetGender.all,
    );
  }
}

enum BuddyRequestStatus {
  open(id: 'open', label: 'Looking for partner'),
  accepted(id: 'accepted', label: 'Accepted — Handshake in progress'),
  otpVerified(id: 'otp_verified', label: 'Verified & Connected');

  final String id;
  final String label;

  const BuddyRequestStatus({required this.id, required this.label});

  static BuddyRequestStatus fromString(String? val) {
    if (val == null) return BuddyRequestStatus.open;
    return BuddyRequestStatus.values.firstWhere(
      (e) => e.id == val,
      orElse: () => BuddyRequestStatus.open,
    );
  }
}

class BuddyUserSummary {
  final String id;
  final String fullName;
  final String? userName;
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;

  const BuddyUserSummary({
    required this.id,
    required this.fullName,
    this.userName,
    this.avatarSeed,
    this.avatarStyle,
    this.gender,
  });

  factory BuddyUserSummary.fromJson(Map<String, dynamic> json) {
    return BuddyUserSummary(
      id: json['id'] as String? ?? '',
      fullName: json['fullName'] as String? ?? json['full_name'] as String? ?? 'User',
      userName: json['userName'] as String? ?? json['user_name'] as String?,
      avatarSeed: json['avatarSeed'] as String? ?? json['avatar_seed'] as String?,
      avatarStyle: json['avatarStyle'] as String? ?? json['avatar_style'] as String? ?? 'avataaars',
      gender: json['gender'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fullName': fullName,
      'userName': userName,
      'avatarSeed': avatarSeed,
      'avatarStyle': avatarStyle,
      'gender': gender,
    };
  }
}

class BuddyRequest {
  final String id;
  final String initiatorId;
  final BuddyType buddyType;
  final String city;
  final BuddyTargetGender targetGender;
  final BuddyRequestStatus status;
  final String? accepterId;
  final String? otpCode;
  final int otpAttempts;
  final DateTime? acceptedAt;
  final DateTime? verifiedAt;
  final String? conversationId;
  final int initiatorCoinCost;
  final int accepterCoinReward;
  final DateTime createdAt;
  final bool isInitiator;
  final BuddyUserSummary? initiator;
  final BuddyUserSummary? accepter;

  const BuddyRequest({
    required this.id,
    required this.initiatorId,
    required this.buddyType,
    required this.city,
    required this.targetGender,
    required this.status,
    this.accepterId,
    this.otpCode,
    this.otpAttempts = 0,
    this.acceptedAt,
    this.verifiedAt,
    this.conversationId,
    this.initiatorCoinCost = 100,
    this.accepterCoinReward = 50,
    required this.createdAt,
    this.isInitiator = false,
    this.initiator,
    this.accepter,
  });

  factory BuddyRequest.fromJson(Map<String, dynamic> json, {String? currentUserId}) {
    final initId = json['initiatorId'] as String? ?? json['initiator_id'] as String? ?? '';
    final accId = json['accepterId'] as String? ?? json['accepter_id'] as String?;

    return BuddyRequest(
      id: json['id'] as String? ?? '',
      initiatorId: initId,
      buddyType: BuddyType.fromString(json['buddyType'] as String? ?? json['buddy_type'] as String?),
      city: json['city'] as String? ?? '',
      targetGender: BuddyTargetGender.fromString(json['targetGender'] as String? ?? json['target_gender'] as String?),
      status: BuddyRequestStatus.fromString(json['status'] as String?),
      accepterId: accId,
      otpCode: json['otpCode'] as String? ?? json['otp_code'] as String?,
      otpAttempts: (json['otpAttempts'] as num? ?? json['otp_attempts'] as num?)?.toInt() ?? 0,
      acceptedAt: json['acceptedAt'] != null ? DateTime.tryParse(json['acceptedAt'] as String) : (json['accepted_at'] != null ? DateTime.tryParse(json['accepted_at'] as String) : null),
      verifiedAt: json['verifiedAt'] != null ? DateTime.tryParse(json['verifiedAt'] as String) : (json['verified_at'] != null ? DateTime.tryParse(json['verified_at'] as String) : null),
      conversationId: json['conversationId'] as String? ?? json['conversation_id'] as String?,
      initiatorCoinCost: (json['initiatorCoinCost'] as num? ?? json['initiator_coin_cost'] as num?)?.toInt() ?? 100,
      accepterCoinReward: (json['accepterCoinReward'] as num? ?? json['accepter_coin_reward'] as num?)?.toInt() ?? 50,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now() : DateTime.now()),
      isInitiator: currentUserId != null ? (initId == currentUserId) : (json['isInitiator'] as bool? ?? false),
      initiator: json['initiator'] != null ? BuddyUserSummary.fromJson(json['initiator'] as Map<String, dynamic>) : null,
      accepter: json['accepter'] != null ? BuddyUserSummary.fromJson(json['accepter'] as Map<String, dynamic>) : null,
    );
  }

  BuddyRequest copyWith({
    String? id,
    String? initiatorId,
    BuddyType? buddyType,
    String? city,
    BuddyTargetGender? targetGender,
    BuddyRequestStatus? status,
    String? accepterId,
    String? otpCode,
    int? otpAttempts,
    DateTime? acceptedAt,
    DateTime? verifiedAt,
    String? conversationId,
    int? initiatorCoinCost,
    int? accepterCoinReward,
    DateTime? createdAt,
    bool? isInitiator,
    BuddyUserSummary? initiator,
    BuddyUserSummary? accepter,
  }) {
    return BuddyRequest(
      id: id ?? this.id,
      initiatorId: initiatorId ?? this.initiatorId,
      buddyType: buddyType ?? this.buddyType,
      city: city ?? this.city,
      targetGender: targetGender ?? this.targetGender,
      status: status ?? this.status,
      accepterId: accepterId ?? this.accepterId,
      otpCode: otpCode ?? this.otpCode,
      otpAttempts: otpAttempts ?? this.otpAttempts,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      conversationId: conversationId ?? this.conversationId,
      initiatorCoinCost: initiatorCoinCost ?? this.initiatorCoinCost,
      accepterCoinReward: accepterCoinReward ?? this.accepterCoinReward,
      createdAt: createdAt ?? this.createdAt,
      isInitiator: isInitiator ?? this.isInitiator,
      initiator: initiator ?? this.initiator,
      accepter: accepter ?? this.accepter,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'initiatorId': initiatorId,
      'buddyType': buddyType.id,
      'city': city,
      'targetGender': targetGender.id,
      'status': status.id,
      'accepterId': accepterId,
      'otpCode': otpCode,
      'otpAttempts': otpAttempts,
      'acceptedAt': acceptedAt?.toIso8601String(),
      'verifiedAt': verifiedAt?.toIso8601String(),
      'conversationId': conversationId,
      'initiatorCoinCost': initiatorCoinCost,
      'accepterCoinReward': accepterCoinReward,
      'createdAt': createdAt.toIso8601String(),
      'isInitiator': isInitiator,
      'initiator': initiator?.toJson(),
      'accepter': accepter?.toJson(),
    };
  }
}
