class InstantCallSession {
  final String id;
  final String maleUserId;
  final String? femaleUserId;
  final int bidAmount;
  final String status;
  final String? agoraChannelName;
  final DateTime? startedAt;
  final DateTime? milestone10mAt;
  final int durationSeconds;
  final bool scratchCardUnlocked;

  const InstantCallSession({
    required this.id,
    required this.maleUserId,
    this.femaleUserId,
    required this.bidAmount,
    required this.status,
    this.agoraChannelName,
    this.startedAt,
    this.milestone10mAt,
    this.durationSeconds = 0,
    this.scratchCardUnlocked = false,
  });

  factory InstantCallSession.fromJson(Map<String, dynamic> json) {
    return InstantCallSession(
      id: json['id'] as String? ?? '',
      maleUserId: json['male_user_id'] as String? ?? json['maleUserId'] as String? ?? '',
      femaleUserId: json['female_user_id'] as String? ?? json['femaleUserId'] as String?,
      bidAmount: (json['bid_amount'] ?? json['bidAmount'] as num?)?.toInt() ?? 10,
      status: json['status'] as String? ?? 'queued',
      agoraChannelName: json['agora_channel_name'] as String? ?? json['agoraChannelName'] as String?,
      startedAt: json['started_at'] != null ? DateTime.tryParse(json['started_at'] as String)?.toLocal() : null,
      milestone10mAt: json['milestone_10m_at'] != null ? DateTime.tryParse(json['milestone_10m_at'] as String)?.toLocal() : null,
      durationSeconds: (json['duration_seconds'] ?? json['durationSeconds'] as num?)?.toInt() ?? 0,
      scratchCardUnlocked: json['scratch_card_unlocked'] == true || json['scratchCardUnlocked'] == true,
    );
  }
}

class ScratchCardModel {
  final String id;
  final String? sessionId;
  final int coinReward;
  final bool isScratched;
  final DateTime? scratchedAt;
  final DateTime createdAt;

  const ScratchCardModel({
    required this.id,
    this.sessionId,
    required this.coinReward,
    required this.isScratched,
    this.scratchedAt,
    required this.createdAt,
  });

  factory ScratchCardModel.fromJson(Map<String, dynamic> json) {
    return ScratchCardModel(
      id: json['id'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? json['session_id'] as String?,
      coinReward: (json['coinReward'] ?? json['coin_reward'] as num?)?.toInt() ?? 0,
      isScratched: json['isScratched'] == true || json['is_scratched'] == true,
      scratchedAt: json['scratchedAt'] != null
          ? DateTime.tryParse(json['scratchedAt'] as String)?.toLocal()
          : (json['scratched_at'] != null
              ? DateTime.tryParse(json['scratched_at'] as String)?.toLocal()
              : null),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)?.toLocal() ?? DateTime.now()
          : (json['created_at'] != null
              ? DateTime.tryParse(json['created_at'] as String)?.toLocal() ?? DateTime.now()
              : DateTime.now()),
    );
  }
}

class FemaleInstantStatus {
  final bool incomingPaidCallsEnabled;
  final bool isSubscribed;
  final int unscratchedCount;
  final int pendingCoins;
  final int totalScratchedCoins;
  final int totalScratchedCards;

  const FemaleInstantStatus({
    this.incomingPaidCallsEnabled = false,
    this.isSubscribed = false,
    this.unscratchedCount = 0,
    this.pendingCoins = 0,
    this.totalScratchedCoins = 0,
    this.totalScratchedCards = 0,
  });

  factory FemaleInstantStatus.fromJson(Map<String, dynamic> json) {
    return FemaleInstantStatus(
      incomingPaidCallsEnabled: json['incomingPaidCallsEnabled'] == true,
      isSubscribed: json['isSubscribed'] == true,
      unscratchedCount: (json['unscratchedCount'] as num?)?.toInt() ?? 0,
      pendingCoins: (json['pendingCoins'] as num?)?.toInt() ?? 0,
      totalScratchedCoins: (json['totalScratchedCoins'] as num?)?.toInt() ?? 0,
      totalScratchedCards: (json['totalScratchedCards'] as num?)?.toInt() ?? 0,
    );
  }

  FemaleInstantStatus copyWith({
    bool? incomingPaidCallsEnabled,
    bool? isSubscribed,
    int? unscratchedCount,
    int? pendingCoins,
    int? totalScratchedCoins,
    int? totalScratchedCards,
  }) {
    return FemaleInstantStatus(
      incomingPaidCallsEnabled: incomingPaidCallsEnabled ?? this.incomingPaidCallsEnabled,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      unscratchedCount: unscratchedCount ?? this.unscratchedCount,
      pendingCoins: pendingCoins ?? this.pendingCoins,
      totalScratchedCoins: totalScratchedCoins ?? this.totalScratchedCoins,
      totalScratchedCards: totalScratchedCards ?? this.totalScratchedCards,
    );
  }
}

class IncomingPaidCallRequest {
  final String callRequestId;
  final String? sessionId;
  final int bidAmount;
  final String agoraChannelName;
  final String agoraToken;
  final int agoraUid;
  final int timeoutSeconds;

  const IncomingPaidCallRequest({
    required this.callRequestId,
    this.sessionId,
    this.bidAmount = 10,
    this.agoraChannelName = '',
    this.agoraToken = '',
    this.agoraUid = 0,
    this.timeoutSeconds = 15,
  });

  factory IncomingPaidCallRequest.fromJson(Map<String, dynamic> json) {
    return IncomingPaidCallRequest(
      callRequestId: json['callRequestId'] as String? ?? '',
      sessionId: json['sessionId'] as String?,
      bidAmount: (json['bidAmount'] as num?)?.toInt() ?? 10,
      agoraChannelName: json['agoraChannelName'] as String? ?? '',
      agoraToken: json['agoraToken'] as String? ?? '',
      agoraUid: (json['agoraUid'] as num?)?.toInt() ?? 0,
      timeoutSeconds: (json['timeoutSeconds'] as num?)?.toInt() ?? 15,
    );
  }
}
