/// Represents the current phase of the matchmaking lifecycle.
enum MatchmakingPhase {
  /// Default state — no matchmaking activity.
  idle,

  /// User has been added to the server queue, waiting for a match.
  queued,

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

  const MatchedUserInfo({
    required this.id,
    required this.fullName,
    this.avatarUrl,
  });

  factory MatchedUserInfo.fromJson(Map<String, dynamic> json) {
    return MatchedUserInfo(
      id: json['id'] as String? ?? '',
      fullName: json['fullName'] as String? ?? 'User',
      avatarUrl: json['avatarUrl'] as String?,
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
  final MatchedUserInfo? matchedUser;

  /// Countdown timer value (300 → 0) for display purposes only.
  /// The server is authoritative on actual call duration.
  final int remainingSeconds;

  final bool isVideoEnabled;
  final bool isMuted;
  final bool isSpeakerOn;
  final String? errorMessage;

  const MatchmakingState({
    this.phase = MatchmakingPhase.idle,
    this.callId,
    this.agoraChannel,
    this.agoraToken,
    this.agoraUid,
    this.matchedUser,
    this.remainingSeconds = 300,
    this.isVideoEnabled = false,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.errorMessage,
  });

  MatchmakingState copyWith({
    MatchmakingPhase? phase,
    String? callId,
    String? agoraChannel,
    String? agoraToken,
    int? agoraUid,
    MatchedUserInfo? matchedUser,
    int? remainingSeconds,
    bool? isVideoEnabled,
    bool? isMuted,
    bool? isSpeakerOn,
    String? errorMessage,
  }) {
    return MatchmakingState(
      phase: phase ?? this.phase,
      callId: callId ?? this.callId,
      agoraChannel: agoraChannel ?? this.agoraChannel,
      agoraToken: agoraToken ?? this.agoraToken,
      agoraUid: agoraUid ?? this.agoraUid,
      matchedUser: matchedUser ?? this.matchedUser,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      errorMessage: errorMessage,
    );
  }

  /// Reset to initial idle state, clearing all call-related data.
  MatchmakingState reset() {
    return const MatchmakingState();
  }
}
