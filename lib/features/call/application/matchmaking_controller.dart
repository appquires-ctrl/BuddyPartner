import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'matchmaking_state.dart';

/// MatchmakingController manages the full matchmaking lifecycle:
///   idle → queued → matched → inCall → ended → idle
///
/// It owns the Socket.io connection, Agora RTC engine, and a display-only
/// countdown timer. The server is authoritative on call duration.
class MatchmakingController extends Notifier<MatchmakingState> {
  sio.Socket? _socket;
  RtcEngine? _agoraEngine;
  Timer? _countdownTimer;
  String? _agoraAppId;

  /// Tracks a pending direct-call target so we can re-emit the event
  /// if the socket wasn't connected when `callUser()` was called.
  String? _pendingDirectCallUserId;

  /// Expose the Agora RTC engine for rendering video in the UI
  RtcEngine? get agoraEngine => _agoraEngine;

  @override
  MatchmakingState build() {
    ref.onDispose(_cleanup);

    // Listen to authentication state changes to initialize or clean up the socket
    ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) {
      final user = next.value;
      if (user != null) {
        _initSocket();
      } else {
        _cleanup();
      }
    });

    // Also run initial socket setup if user is already logged in
    final user = ref.read(authStateProvider).value;
    if (user != null) {
      Future.microtask(() => _initSocket());
    }

    return const MatchmakingState();
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Connect to the backend Socket.io server and join the matchmaking queue.
  Future<void> joinQueue() async {
    if (state.phase != MatchmakingPhase.idle) return;

    try {
      // 1. Optimized permission check (avoid native channel overhead if already granted)
      bool micGranted = await Permission.microphone.isGranted;
      bool cameraGranted = await Permission.camera.isGranted;

      if (!micGranted || !cameraGranted) {
        final statuses = await [
          Permission.microphone,
          Permission.camera,
        ].request();
        micGranted = statuses[Permission.microphone]?.isGranted ?? false;
        cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      }

      if (!micGranted || !cameraGranted) {
        state = state.copyWith(
          phase: MatchmakingPhase.idle,
          errorMessage: 'Microphone and Camera permissions are required to start matchmaking.',
        );
        return;
      }

      // Ensure socket is initialized and connected
      _initSocket();

      if (_socket != null && _socket!.connected) {
        _socket!.emit('join_queue');
      }

      state = state.copyWith(phase: MatchmakingPhase.queued);
    } catch (e) {
      state = state.copyWith(
        phase: MatchmakingPhase.idle,
        errorMessage: 'Failed to connect: $e',
      );
    }
  }

  /// Cancel matchmaking and leave the queue.
  void leaveQueue() {
    if (state.phase != MatchmakingPhase.queued) return;

    _pendingDirectCallUserId = null;
    _socket?.emit('leave_queue');
    state = state.reset();
  }

  /// Initiate a direct call to a specific user (e.g. from call history).
  /// The server handles this via the 'direct_call' event and responds with
  /// 'match_found' using the same flow as random matchmaking.
  Future<void> callUser({
    required String targetUserId,
    required String targetUserName,
    String? targetUserAvatar,
  }) async {
    if (state.phase != MatchmakingPhase.idle) return;

    try {
      // 1. Ensure mic + camera permissions
      bool micGranted = await Permission.microphone.isGranted;
      bool cameraGranted = await Permission.camera.isGranted;

      if (!micGranted || !cameraGranted) {
        final statuses = await [
          Permission.microphone,
          Permission.camera,
        ].request();
        micGranted = statuses[Permission.microphone]?.isGranted ?? false;
        cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      }

      if (!micGranted || !cameraGranted) {
        state = state.copyWith(
          phase: MatchmakingPhase.idle,
          errorMessage: 'Microphone and Camera permissions are required.',
        );
        return;
      }

      // 2. Ensure socket is initialised and connected
      _initSocket();

      // 3. Set state to queued and pre-fill matched user info so the
      //    calling/connecting UI can show who we're calling.
      state = state.copyWith(
        phase: MatchmakingPhase.queued,
        matchedUser: MatchedUserInfo(
          id: targetUserId,
          fullName: targetUserName,
          avatarUrl: targetUserAvatar,
        ),
      );

      // 4. Ask the server to initiate a direct call.
      //    Store the target so onConnect can re-emit if socket isn't ready yet.
      _pendingDirectCallUserId = targetUserId;
      if (_socket != null && _socket!.connected) {
        _socket!.emit('direct_call', {'targetUserId': targetUserId});
        _pendingDirectCallUserId = null;
      }
    } catch (e) {
      state = state.copyWith(
        phase: MatchmakingPhase.idle,
        errorMessage: 'Failed to start call: $e',
      );
    }
  }

  /// Manually end the current call. Navigating back to home is handled by the UI.
  Future<void> endCall() async {
    if (state.phase == MatchmakingPhase.queued) {
      leaveQueue();
      return;
    }

    if (state.phase != MatchmakingPhase.inCall &&
        state.phase != MatchmakingPhase.matched) {
      return;
    }

    final callId = state.callId;
    if (callId != null) {
      _socket?.emit('end_call', {'callId': callId});
    }

    await _leaveAgoraChannel();
    _stopCountdown();
    state = state.copyWith(phase: MatchmakingPhase.ended);

    // Brief delay before resetting to idle so the UI can react to `ended`
    await Future.delayed(const Duration(milliseconds: 300));
    state = state.reset();
  }

  /// Toggle local microphone mute.
  Future<void> toggleMute() async {
    if (state.phase != MatchmakingPhase.inCall) return;

    final newMuted = !state.isMuted;
    try {
      await _agoraEngine?.muteLocalAudioStream(newMuted);
      state = state.copyWith(isMuted: newMuted);
    } catch (e) {
      debugPrint('Warning: Failed to toggle mute: $e');
    }
  }

  /// Toggle loudspeaker output.
  Future<void> toggleSpeaker() async {
    if (state.phase != MatchmakingPhase.inCall) return;

    final newSpeaker = !state.isSpeakerOn;
    try {
      await _agoraEngine?.setEnableSpeakerphone(newSpeaker);
      state = state.copyWith(isSpeakerOn: newSpeaker);
    } catch (e) {
      debugPrint('Warning: Failed to toggle speaker: $e');
    }
  }

  /// Request video upgrade for the current call.
  Future<void> upgradeToVideo() async {
    if (state.phase != MatchmakingPhase.inCall) return;
    if (state.isVideoEnabled) return; // Already in video mode

    bool cameraGranted = await Permission.camera.isGranted;
    if (!cameraGranted) {
      cameraGranted = await Permission.camera.request().isGranted;
    }
    if (!cameraGranted) {
      state = state.copyWith(errorMessage: 'Camera permission denied');
      return;
    }

    _socket?.emit('upgrade_to_video', {'callId': state.callId});
    await _enableVideo();
  }

  // ── Socket.io connection ────────────────────────────────────────────────

  void _initSocket() {
    if (_socket != null) return;

    final accessToken =
        Supabase.instance.client.auth.currentSession?.accessToken;
    if (accessToken == null) return;

    _socket = sio.io(
      AppConfig.backendUrl,
      sio.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': accessToken})
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('Socket connected to backend');
      // If we got disconnected during an active queue, re-emit the pending event
      if (state.phase == MatchmakingPhase.queued) {
        if (_pendingDirectCallUserId != null) {
          _socket!.emit('direct_call', {'targetUserId': _pendingDirectCallUserId});
          _pendingDirectCallUserId = null;
        } else {
          _socket!.emit('join_queue');
        }
      }
    });

    _socket!.on('match_found', _onMatchFound);
    _socket!.on('call_ended', _onCallEnded);
    _socket!.on('video_upgrade_request', _onVideoUpgradeRequest);
    _socket!.on('video_upgrade_accepted', _onVideoUpgradeAccepted);
    _socket!.on('match_error', _onMatchError);

    _socket!.onDisconnect((_) {
      debugPrint('Socket disconnected');
      
      // Update with the latest access token to ensure reconnection doesn't fail
      // after the old token expires (typically 1 hour)
      final token = Supabase.instance.client.auth.currentSession?.accessToken;
      if (token != null && _socket != null && _socket!.io.options != null) {
        _socket!.io.options!['auth'] = {'token': token};
      }

      if (state.phase == MatchmakingPhase.inCall) {
        _handleServerDisconnect();
      }
    });

    _socket!.onConnectError((err) {
      debugPrint('Socket connection error: $err');
    });

    _socket!.connect();
  }

  void _disconnectSocket() {
    _socket?.dispose();
    _socket = null;
  }

  // ── Socket event handlers ─────────────────────────────────────────────

  Future<void> _onMatchFound(dynamic data) async {
    // Guard: only accept match_found when we're actually waiting for one
    if (state.phase != MatchmakingPhase.queued &&
        state.phase != MatchmakingPhase.idle) {
      return;
    }
    try {
      final map = Map<String, dynamic>.from(data as Map);
      debugPrint('MATCH DATA RECEIVED: $map');
      final callId = map['callId'] as String;
      final channelName = map['agoraChannelName'] as String;
      final agoraToken = map['agoraToken'] as String;
      final agoraUid = map['agoraUid'] as int;
      // Read Agora App ID from server payload (avoids needing --dart-define)
      _agoraAppId = map['agoraAppId'] as String?;
      var matchedUser = MatchedUserInfo.fromJson(
        Map<String, dynamic>.from(map['matchedUser'] as Map),
      );

      if (matchedUser.fullName == 'User' && matchedUser.id.isNotEmpty) {
        try {
          final profileData = await Supabase.instance.client
              .from('users')
              .select('full_name')
              .eq('id', matchedUser.id)
              .maybeSingle();
          if (profileData != null && profileData['full_name'] != null) {
            matchedUser = MatchedUserInfo(
              id: matchedUser.id,
              fullName: profileData['full_name'] as String,
              avatarUrl: matchedUser.avatarUrl,
            );
          }
        } catch (e) {
          debugPrint('Error fetching matching user name fallback: $e');
        }
      }

      state = state.copyWith(
        phase: MatchmakingPhase.matched,
        callId: callId,
        agoraChannel: channelName,
        agoraToken: agoraToken,
        agoraUid: agoraUid,
        matchedUser: matchedUser,
      );

      // Initialize Agora and join the channel
      await _initAgora(channelName, agoraToken, agoraUid);

      state = state.copyWith(phase: MatchmakingPhase.inCall);

      // Start display-only countdown (5:00 → 0:00)
      _startCountdown();
    } catch (e) {
      state = state.copyWith(
        phase: MatchmakingPhase.idle,
        errorMessage: 'Failed to join call: $e',
      );
      // Notify server and cleanly teardown the call for both parties
      endCall();
    }
  }

  Future<void> _onCallEnded(dynamic data) async {
    await _leaveAgoraChannel();
    _stopCountdown();
    state = state.copyWith(phase: MatchmakingPhase.ended);

    await Future.delayed(const Duration(milliseconds: 300));
    state = state.reset();
  }

  Future<void> _onVideoUpgradeRequest(dynamic data) async {
    // Phase 1: auto-accept video upgrade requests
    final callId = state.callId;
    if (callId == null) return;

    _socket?.emit('video_upgrade_accepted', {'callId': callId});
    await _enableVideo();
  }

  Future<void> _onVideoUpgradeAccepted(dynamic data) async {
    // The other party accepted our video request — enable video on our side too
    await _enableVideo();
  }

  void _onMatchError(dynamic data) {
    String errorMsg = 'Matchmaking error. Please try again.';
    if (data is Map && data['error'] != null) {
      errorMsg = data['error'].toString();
    } else if (data is String) {
      errorMsg = data;
    }
    state = state.copyWith(
      phase: MatchmakingPhase.idle,
      errorMessage: errorMsg,
    );
  }

  Future<void> _handleServerDisconnect() async {
    await _leaveAgoraChannel();
    _stopCountdown();
    state = state.copyWith(phase: MatchmakingPhase.ended);

    await Future.delayed(const Duration(milliseconds: 300));
    state = state.reset();
  }

  // ── Agora RTC engine ──────────────────────────────────────────────────

  Future<void> _initAgora(
    String channelName,
    String token,
    int uid,
  ) async {
    try {
      // Mic permission is already granted in joinQueue() — no need to re-request here

      // Use Agora App ID from server payload, fall back to compile-time config
      final appId = _agoraAppId ?? AppConfig.agoraAppId;
      if (appId.isEmpty) {
        throw Exception('Agora App ID is not configured');
      }

      _agoraEngine = createAgoraRtcEngine();
      await _agoraEngine!.initialize(RtcEngineContext(
        appId: appId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ));

      // Register event handlers
      _agoraEngine!.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          // Successfully joined the Agora channel
        },
        onUserJoined: (RtcConnection connection, int remoteUid, int elapsed) {
          // The matched user has joined
          state = state.copyWith(remoteUid: remoteUid);
        },
        onUserOffline: (RtcConnection connection, int remoteUid,
            UserOfflineReasonType reason) {
          // Remote user left
          if (state.remoteUid == remoteUid) {
            state = state.copyWith(clearRemoteUid: true);
          }
        },
        onError: (ErrorCodeType code, String msg) {
          // Agora engine error
        },
      ));

      // Enable audio, disable video initially
      try {
        await _agoraEngine!.enableAudio();
        await _agoraEngine!.setEnableSpeakerphone(false);
      } catch (e) {
        // Log and ignore to prevent failing the call setup on emulators
        debugPrint('Warning: Failed to configure audio/speakerphone properties: $e');
      }

      // Join channel in audio-only mode
      await _agoraEngine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: uid,
        options: const ChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: false,
          publishCameraTrack: false,
          publishMicrophoneTrack: true,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
    } catch (e) {
      await _leaveAgoraChannel(); // Release resources immediately on failure
      rethrow;
    }
  }

  Future<void> _enableVideo() async {
    if (_agoraEngine == null || state.isVideoEnabled) return;

    await _agoraEngine!.enableVideo();
    await _agoraEngine!.startPreview();

    // Update channel media options to publish video
    await _agoraEngine!.updateChannelMediaOptions(const ChannelMediaOptions(
      publishCameraTrack: true,
      autoSubscribeVideo: true,
    ));

    state = state.copyWith(isVideoEnabled: true);
  }

  Future<void> _leaveAgoraChannel() async {
    try {
      await _agoraEngine?.leaveChannel();
      await _agoraEngine?.release();
      _agoraEngine = null;
    } catch (_) {
      // Ignore cleanup errors
    }
  }

  // ── Countdown timer (display-only) ────────────────────────────────────

  void _startCountdown() {
    _stopCountdown();
    state = state.copyWith(remainingSeconds: 300);

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = state.remainingSeconds - 1;
      if (remaining <= 0) {
        timer.cancel();
        // Don't end the call here — wait for the server's call_ended event.
        // The timer hitting 0 is just a visual cue.
        state = state.copyWith(remainingSeconds: 0);
      } else {
        state = state.copyWith(remainingSeconds: remaining);
      }
    });
  }

  void _stopCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  void _cleanup() {
    _stopCountdown();
    _leaveAgoraChannel();
    _disconnectSocket();
  }
}

/// Provider definition for MatchmakingController.
final matchmakingControllerProvider =
    NotifierProvider<MatchmakingController, MatchmakingState>(
  MatchmakingController.new,
);
