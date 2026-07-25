/// Represents the current phase of the matchmaking lifecycle.
enum MatchmakingPhase {
  /// Default state — no matchmaking activity.
  idle,

  /// User has been added to the server queue, waiting for a match.
  queued,

  /// Direct call request is outgoing, waiting for target user response.
  outgoingRequest,

  /// Direct call request is incoming, awaiting acceptance.
  incomingRequest,

  /// A match has been found, Agora channel setup is in progress.
  matched,

  /// Actively in a voice/video call via Agora.
  inCall,

  /// Call has ended, cleaning up before returning to idle.
  ended,
}

/// Public info about the matched user, received from the server.
class MatchedUserInfo {
  final String id;
  final String fullName;
  final String? avatarUrl;
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;

  const MatchedUserInfo({
    required this.id,
    required this.fullName,
    this.avatarUrl,
    this.avatarSeed,
    this.avatarStyle,
    this.gender,
  });

  factory MatchedUserInfo.fromJson(Map<String, dynamic> json) {
    return MatchedUserInfo(
      id: json['id'] as String? ?? '',
      fullName: (json['fullName'] ?? json['full_name']) as String? ?? 'User',
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url']) as String?,
      avatarSeed: (json['avatarSeed'] ?? json['avatar_seed']) as String?,
      avatarStyle: (json['avatarStyle'] ?? json['avatar_style']) as String? ?? 'avataaars',
      gender: json['gender'] as String?,
    );
  }
}

/// Immutable state for the matchmaking controller.
class MatchmakingState {
  final MatchmakingPhase phase;
  final String? callId;
  final String? agoraChannel;
  final String? agoraToken;
  final int? agoraUid;
  final int? remoteUid;
  final MatchedUserInfo? matchedUser;

  /// Countdown timer value (300 → 0) for display purposes only.
  /// The server is authoritative on actual call duration.
  final int remainingSeconds;

  final bool isVideoEnabled;
  final bool isMuted;
  final bool isSpeakerOn;
  final String? errorMessage;

  /// Video upgrade request state flags
  final bool isVideoRequestOutgoing;
  final bool isVideoRequestIncoming;
  final String? videoRequestSenderName;

  /// Roses earned during this call (for female users)
  final int rosesEarnedThisCall;

  const MatchmakingState({
    this.phase = MatchmakingPhase.idle,
    this.callId,
    this.agoraChannel,
    this.agoraToken,
    this.agoraUid,
    this.remoteUid,
    this.matchedUser,
    this.remainingSeconds = 300,
    this.isVideoEnabled = false,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.errorMessage,
    this.isVideoRequestOutgoing = false,
    this.isVideoRequestIncoming = false,
    this.videoRequestSenderName,
    this.rosesEarnedThisCall = 0,
  });

  MatchmakingState copyWith({
    MatchmakingPhase? phase,
    String? callId,
    String? agoraChannel,
    String? agoraToken,
    int? agoraUid,
    int? remoteUid,
    bool clearRemoteUid = false,
    bool clearMatchedUser = false,
    MatchedUserInfo? matchedUser,
    int? remainingSeconds,
    bool? isVideoEnabled,
    bool? isMuted,
    bool? isSpeakerOn,
    String? errorMessage,
    bool? isVideoRequestOutgoing,
    bool? isVideoRequestIncoming,
    String? videoRequestSenderName,
    bool clearVideoRequestSenderName = false,
    int? rosesEarnedThisCall,
  }) {
    return MatchmakingState(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      agoraChannel: agoraChannel ?? this.agoraChannel,
      agoraToken: agoraToken ?? this.agoraToken,
      agoraUid: agoraUid ?? this.agoraUid,
      remoteUid: clearRemoteUid ? null : (remoteUid ?? this.remoteUid),
      matchedUser: clearMatchedUser ? null : (matchedUser ?? this.matchedUser),
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      errorMessage: errorMessage,
      isVideoRequestOutgoing: isVideoRequestOutgoing ?? this.isVideoRequestOutgoing,
      isVideoRequestIncoming: isVideoRequestIncoming ?? this.isVideoRequestIncoming,
      videoRequestSenderName: clearVideoRequestSenderName
          ? null
          : (videoRequestSenderName ?? this.videoRequestSenderName),
      rosesEarnedThisCall: rosesEarnedThisCall ?? this.rosesEarnedThisCall,
    );
  }

  /// Reset to initial idle state, clearing all call-related data.
  MatchmakingState reset() {
    return const MatchmakingState();
  }
}
