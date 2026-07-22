import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:dating_app/core/services/socket_provider.dart';

import 'package:dating_app/core/config/app_config.dart';
import 'matchmaking_state.dart';
import 'package:dating_app/features/call/application/call_summary_provider.dart';
import 'package:dating_app/features/recharge/presentation/providers/recharge_providers.dart';

/// MatchmakingController manages the full matchmaking lifecycle:
///   idle → queued → matched → inCall → ended → idle
///
/// It owns the Socket.io connection, Agora RTC engine, and a display-only
/// countdown timer. The server is authoritative on call duration.
class MatchmakingController extends Notifier<MatchmakingState> {
  RtcEngine? _agoraEngine;
  Timer? _countdownTimer;
  String? _agoraAppId;

  Timer? _callingTimeoutTimer;

  /// Tracks a pending direct-call target so we can re-emit the event
  /// if the socket wasn't connected when `callUser()` was called.
  String? _pendingDirectCallUserId;

  /// Whether we've already registered matchmaking event listeners on the socket
  bool _listenersRegistered = false;

  /// Expose the Agora RTC engine for rendering video in the UI
  RtcEngine? get agoraEngine => _agoraEngine;

  /// Helper to get the shared socket instance
  sio.Socket? get _socket => ref.read(socketProvider);

  @override
  MatchmakingState build() {
    ref.onDispose(_cleanup);

    // Watch the shared socket — when it changes (connects), set up listeners
    ref.listen<sio.Socket?>(socketProvider, (prev, next) {
      if (next != null && !_listenersRegistered) {
        _setupSocketListeners(next);
      } else if (next == null) {
        _listenersRegistered = false;
      }
    });

    // Also set up listeners if socket already exists
    final existingSocket = ref.read(socketProvider);
    if (existingSocket != null && !_listenersRegistered) {
      Future.microtask(() => _setupSocketListeners(existingSocket));
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

      // Ensure socket is initialized via provider
      final socket = _socket;

      if (socket != null && socket.connected) {
        socket.emitWithAck('join_queue', null, ack: (data) {
          if (data is Map && data['error'] != null) {
            final error = data['error'].toString();
            if (error == 'insufficient_balance') {
              state = state.copyWith(
                phase: MatchmakingPhase.idle,
                errorMessage: data['message']?.toString() ??
                    'You need at least 10 coins to start a call — recharge to continue',
              );
            }
          }
        });
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

    _callingTimeoutTimer?.cancel();
    _callingTimeoutTimer = null;
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

      // 2. Socket is managed by the shared provider
      final socket = _socket;

      // 3. Set state to outgoingRequest and pre-fill matched user info so the
      //    calling/connecting UI can show who we're calling.
      state = state.copyWith(
        phase: MatchmakingPhase.outgoingRequest,
        matchedUser: MatchedUserInfo(
          id: targetUserId,
          fullName: targetUserName,
          avatarUrl: targetUserAvatar,
        ),
      );

      // 4. Ask the server to initiate a direct call.
      //    Store the target so onConnect can re-emit if socket isn't ready yet.
      _pendingDirectCallUserId = targetUserId;
      if (socket != null && socket.connected) {
        socket.emit('direct_call', {'targetUserId': targetUserId});
        _pendingDirectCallUserId = null;
      }

      // 5. Start a 32-second connection timeout timer
      _callingTimeoutTimer?.cancel();
      _callingTimeoutTimer = Timer(const Duration(seconds: 32), () {
        if (state.phase == MatchmakingPhase.outgoingRequest) {
          cancelCallRequest();
          state = state.copyWith(
            phase: MatchmakingPhase.idle,
            errorMessage: 'No answer. Target user might be offline or busy.',
          );
        }
      });
    } catch (e) {
      _callingTimeoutTimer?.cancel();
      state = state.copyWith(
        phase: MatchmakingPhase.idle,
        errorMessage: 'Failed to start call: $e',
      );
    }
  }

  /// Accept the incoming direct call request.
  Future<void> acceptCall() async {
    if (state.phase != MatchmakingPhase.incomingRequest || state.callId == null) return;

    try {
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
        declineCall();
        state = state.copyWith(
          errorMessage: 'Permissions are required to accept the call.',
        );
        return;
      }

      _socket?.emit('accept_call_request', {'callRequestId': state.callId});
    } catch (e) {
      debugPrint('Error accepting call request: $e');
      state = state.copyWith(errorMessage: 'Failed to accept call request.');
    }
  }

  /// Decline the incoming direct call request.
  void declineCall() {
    if (state.phase != MatchmakingPhase.incomingRequest || state.callId == null) return;
    _socket?.emit('decline_call_request', {'callRequestId': state.callId});
    _callingTimeoutTimer?.cancel();
    _callingTimeoutTimer = null;
    state = state.reset();
  }

  /// Cancel the outgoing direct call request before it is accepted.
  void cancelCallRequest() {
    if (state.phase != MatchmakingPhase.outgoingRequest || state.callId == null) return;
    _socket?.emit('cancel_call_request', {'callRequestId': state.callId});
    _callingTimeoutTimer?.cancel();
    _callingTimeoutTimer = null;
    _pendingDirectCallUserId = null;
    state = state.reset();
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

    if (state.matchedUser != null) {
      final elapsed = 300 - state.remainingSeconds;
      final cost = (elapsed / 60.0 * 10).ceil();
      ref.read(lastCallSummaryProvider.notifier).state = CallSummaryInfo(
        matchedUserId: state.matchedUser!.id,
        matchedUserName: state.matchedUser!.fullName,
        matchedUserAvatar: state.matchedUser!.avatarUrl,
        durationSeconds: elapsed,
        totalCost: cost,
      );
    }

    state = state.copyWith(phase: MatchmakingPhase.ended);

    // Refresh wallet balance from server so UI shows updated coins
    ref.invalidate(walletBalanceProvider);

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

  // ── Socket.io listeners ─────────────────────────────────────────────────

  /// Register matchmaking-specific event handlers on the shared socket.
  void _setupSocketListeners(sio.Socket socket) {
    if (_listenersRegistered) return;
    _listenersRegistered = true;

    socket.on('connect', (_) {
      debugPrint('[Matchmaking] Socket connected');
      // If we got disconnected during an active queue, re-emit the pending event
      if (state.phase == MatchmakingPhase.queued) {
        if (_pendingDirectCallUserId != null) {
          socket.emit('direct_call', {'targetUserId': _pendingDirectCallUserId});
          _pendingDirectCallUserId = null;
        } else {
          socket.emit('join_queue');
        }
      }
    });

    socket.on('match_found', _onMatchFound);
    socket.on('incoming_call_request', _onIncomingCallRequest);
    socket.on('outgoing_call_ringing', _onOutgoingCallRinging);
    socket.on('call_response', _onCallResponse);
    socket.on('call_ended', _onCallEnded);
    socket.on('video_upgrade_request', _onVideoUpgradeRequest);
    socket.on('video_upgrade_accepted', _onVideoUpgradeAccepted);
    socket.on('match_error', _onMatchError);
    socket.on('balance_update', _onBalanceUpdate);

    socket.on('disconnect', (_) async {
      debugPrint('[Matchmaking] Socket disconnected');
      if (state.phase == MatchmakingPhase.inCall) {
        _handleServerDisconnect();
      }
    });
  }

  // ── Socket event handlers ─────────────────────────────────────────────

  Future<void> _onMatchFound(dynamic data) async {
    // Guard: only accept match_found when we're actually waiting for one
    if (state.phase != MatchmakingPhase.queued &&
        state.phase != MatchmakingPhase.idle &&
        state.phase != MatchmakingPhase.outgoingRequest &&
        state.phase != MatchmakingPhase.incomingRequest) {
      return;
    }
    
    // Cancel connection timeout timer since we got matched/connected
    _callingTimeoutTimer?.cancel();
    _callingTimeoutTimer = null;
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

      // Matched profile details are already fetched and provided by Neon backend inside the event payload.
      // So no fallback database query is required.

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
    String? endReason;
    int? serverTotalCost;
    if (data is Map) {
      if (data['reason'] != null) {
        endReason = data['reason'].toString();
      }
      if (data['totalCost'] != null) {
        serverTotalCost = (data['totalCost'] as num).toInt();
      }
    }
    final String? errorMessage = (endReason == 'insufficient_balance')
        ? 'Call ended — insufficient balance'
        : null;

    if (state.matchedUser != null) {
      final elapsed = 300 - state.remainingSeconds;
      // Use server-provided actual cost; fall back to voice-rate estimate
      final cost = serverTotalCost ?? (elapsed / 60.0 * 10).ceil();
      ref.read(lastCallSummaryProvider.notifier).state = CallSummaryInfo(
        matchedUserId: state.matchedUser!.id,
        matchedUserName: state.matchedUser!.fullName,
        matchedUserAvatar: state.matchedUser!.avatarUrl,
        durationSeconds: elapsed,
        totalCost: cost,
      );
    }

    await _leaveAgoraChannel();
    _stopCountdown();
    state = state.copyWith(
      phase: MatchmakingPhase.ended,
      errorMessage: errorMessage,
    );

    // Refresh wallet balance from server so UI shows updated coins
    ref.invalidate(walletBalanceProvider);

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
    if (data is Map) {
      if (data['message'] != null) {
        errorMsg = data['message'].toString();
      } else if (data['error'] != null) {
        errorMsg = data['error'].toString();
      }
    } else if (data is String) {
      errorMsg = data;
    }
    state = state.copyWith(
      phase: MatchmakingPhase.idle,
      errorMessage: errorMsg,
    );
  }

  void _onBalanceUpdate(dynamic data) {
    try {
      if (data is Map && data['balance'] != null) {
        final newBalance = (data['balance'] as num).toInt();
        ref.read(walletBalanceProvider.notifier).updateBalance(newBalance);
      }
    } catch (e) {
      debugPrint('Error updating balance from socket: $e');
    }
  }

  Future<void> _onIncomingCallRequest(dynamic data) async {
    try {
      final map = Map<String, dynamic>.from(data as Map);
      final callRequestId = map['callRequestId'] as String;
      final caller = MatchedUserInfo.fromJson(
        Map<String, dynamic>.from(map['caller'] as Map),
      );

      state = state.copyWith(
        phase: MatchmakingPhase.incomingRequest,
        callId: callRequestId,
        matchedUser: caller,
      );

      _callingTimeoutTimer?.cancel();
      _callingTimeoutTimer = Timer(const Duration(seconds: 32), () {
        if (state.phase == MatchmakingPhase.incomingRequest) {
          declineCall();
        }
      });
    } catch (e) {
      debugPrint('Error parsing incoming call request: $e');
    }
  }

  void _onOutgoingCallRinging(dynamic data) {
    try {
      final map = Map<String, dynamic>.from(data as Map);
      final callRequestId = map['callRequestId'] as String;
      state = state.copyWith(
        callId: callRequestId,
      );
    } catch (e) {
      debugPrint('Error parsing outgoing call ringing: $e');
    }
  }

  void _onCallResponse(dynamic data) {
    try {
      final map = Map<String, dynamic>.from(data as Map);
      final status = map['status'] as String;

      _callingTimeoutTimer?.cancel();
      _callingTimeoutTimer = null;
      _pendingDirectCallUserId = null;

      String message = 'Call request ended';
      if (status == 'declined') {
        message = 'Call declined';
      } else if (status == 'busy') {
        message = 'User is busy';
      } else if (status == 'offline') {
        message = 'User is offline';
      } else if (status == 'no_answer') {
        message = 'No answer';
      } else if (status == 'cancelled') {
        message = 'Call cancelled';
      }

      state = state.reset().copyWith(
        errorMessage: message,
      );
    } catch (e) {
      debugPrint('Error parsing call response: $e');
    }
  }

  Future<void> _handleServerDisconnect() async {
    if (state.matchedUser != null) {
      final elapsed = 300 - state.remainingSeconds;
      final cost = (elapsed / 60.0 * 10).ceil();
      ref.read(lastCallSummaryProvider.notifier).state = CallSummaryInfo(
        matchedUserId: state.matchedUser!.id,
        matchedUserName: state.matchedUser!.fullName,
        matchedUserAvatar: state.matchedUser!.avatarUrl,
        durationSeconds: elapsed,
        totalCost: cost,
      );
    }

    await _leaveAgoraChannel();
    _stopCountdown();
    state = state.copyWith(phase: MatchmakingPhase.ended);

    // Refresh wallet balance from server so UI shows updated coins
    ref.invalidate(walletBalanceProvider);

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
    _callingTimeoutTimer?.cancel();
    _callingTimeoutTimer = null;
    _stopCountdown();
    _leaveAgoraChannel();
    _listenersRegistered = false;
    // Socket lifecycle is managed by socketProvider — do NOT dispose it here
  }
}

/// Provider definition for MatchmakingController.
final matchmakingControllerProvider =
    NotifierProvider<MatchmakingController, MatchmakingState>(
  MatchmakingController.new,
);
