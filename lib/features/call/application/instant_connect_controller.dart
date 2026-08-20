import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/services/socket_provider.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/call/domain/models/instant_connect_models.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

enum InstantPhase {
  idle,
  queued,
  incomingRequest,
  inCall,
  ended,
}

class InstantConnectState {
  final InstantPhase phase;
  final String? sessionId;
  final String? callId;
  final int bidAmount;
  final int queuePosition;
  final IncomingPaidCallRequest? incomingRequest;
  final FemaleInstantStatus femaleStatus;
  final List<ScratchCardModel> scratchCards;
  final ScratchCardModel? latestUnlockedCard;
  final bool is10mReached;
  final int callSecondsElapsed;
  final String? errorMessage;

  const InstantConnectState({
    this.phase = InstantPhase.idle,
    this.sessionId,
    this.callId,
    this.bidAmount = 0,
    this.queuePosition = 0,
    this.incomingRequest,
    this.femaleStatus = const FemaleInstantStatus(),
    this.scratchCards = const [],
    this.latestUnlockedCard,
    this.is10mReached = false,
    this.callSecondsElapsed = 0,
    this.errorMessage,
  });

  InstantConnectState copyWith({
    InstantPhase? phase,
    String? sessionId,
    bool clearSessionId = false,
    String? callId,
    bool clearCallId = false,
    int? bidAmount,
    int? queuePosition,
    IncomingPaidCallRequest? incomingRequest,
    bool clearIncomingRequest = false,
    FemaleInstantStatus? femaleStatus,
    List<ScratchCardModel>? scratchCards,
    ScratchCardModel? latestUnlockedCard,
    bool clearLatestUnlockedCard = false,
    bool? is10mReached,
    int? callSecondsElapsed,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return InstantConnectState(
      phase: phase ?? this.phase,
      sessionId: clearSessionId ? null : (sessionId ?? this.sessionId),
      callId: clearCallId ? null : (callId ?? this.callId),
      bidAmount: bidAmount ?? this.bidAmount,
      queuePosition: queuePosition ?? this.queuePosition,
      incomingRequest: clearIncomingRequest ? null : (incomingRequest ?? this.incomingRequest),
      femaleStatus: femaleStatus ?? this.femaleStatus,
      scratchCards: scratchCards ?? this.scratchCards,
      latestUnlockedCard: clearLatestUnlockedCard ? null : (latestUnlockedCard ?? this.latestUnlockedCard),
      is10mReached: is10mReached ?? this.is10mReached,
      callSecondsElapsed: callSecondsElapsed ?? this.callSecondsElapsed,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }

  InstantConnectState reset() {
    return InstantConnectState(
      femaleStatus: femaleStatus,
      scratchCards: scratchCards,
    );
  }
}

class InstantConnectController extends Notifier<InstantConnectState> {
  Timer? _callTimer;
  bool _listenersRegistered = false;

  sio.Socket? get _socket => ref.read(socketProvider);

  @override
  InstantConnectState build() {
    ref.onDispose(() {
      _callTimer?.cancel();
    });

    ref.listen<sio.Socket?>(socketProvider, (prev, next) {
      if (next != null) {
        _listenersRegistered = false;
        _setupSocketListeners(next);
      } else {
        _listenersRegistered = false;
      }
    });

    ref.listen(authStateProvider, (prev, next) {
      final user = next.value;
      if (user != null && user.isFemale) {
        fetchFemaleStatus();
        fetchScratchCards();
      }
    });

    final existingSocket = ref.read(socketProvider);
    if (existingSocket != null && !_listenersRegistered) {
      Future.microtask(() => _setupSocketListeners(existingSocket));
    }

    final user = ref.read(authStateProvider).value;
    if (user != null && user.isFemale) {
      Future.microtask(() {
        fetchFemaleStatus();
        fetchScratchCards();
      });
    }

    return const InstantConnectState();
  }

  void _setupSocketListeners(sio.Socket socket) {
    if (_listenersRegistered) return;
    _listenersRegistered = true;

    // Incoming 1:2 parallel ring for female
    socket.on('incoming_instant_call', (data) {
      if (data is Map) {
        final req = IncomingPaidCallRequest.fromJson(Map<String, dynamic>.from(data));
        state = state.copyWith(
          phase: InstantPhase.incomingRequest,
          incomingRequest: req,
        );
      }
    });

    // Dismissal when other female answers or 7s timeout
    socket.on('instant_call_dismissed', (data) {
      state = state.copyWith(
        phase: InstantPhase.idle,
        clearIncomingRequest: true,
      );
    });

    // Male queue updates
    socket.on('instant:queue_status', (data) {
      if (data is Map) {
        final rank = (data['queuePosition'] as num?)?.toInt() ?? 1;
        final bid = (data['bidAmount'] as num?)?.toInt() ?? state.bidAmount;
        state = state.copyWith(
          phase: InstantPhase.queued,
          queuePosition: rank,
          bidAmount: bid,
        );
      }
    });

    socket.on('instant:queue_left', (data) {
      state = state.reset();
      ref.invalidate(walletBalanceProvider);
    });

    // Call connected (Agora token received)
    socket.on('instant:call_connected', (data) async {
      if (data is Map) {
        final sessId = data['sessionId'] as String?;
        final cId = data['callId'] as String? ?? 'instant_call';
        final chan = data['agoraChannelName'] as String? ?? '';
        final tok = data['agoraToken'] as String? ?? '';
        final uid = (data['agoraUid'] as num?)?.toInt() ?? 0;
        final rUid = (data['remoteUid'] as num?)?.toInt();
        final appId = data['agoraAppId'] as String?;
        final otherName = data['otherUserName'] as String? ?? 'VIP Partner';

        state = state.copyWith(
          phase: InstantPhase.inCall,
          sessionId: sessId,
          callId: cId,
          clearIncomingRequest: true,
          is10mReached: false,
          callSecondsElapsed: 0,
        );

        _startCallTimer();

        // Connect Agora RTC Engine
        final matchedUserRaw = data['matchedUser'];
        final matchedUser = (matchedUserRaw is Map)
            ? MatchedUserInfo.fromJson(Map<String, dynamic>.from(matchedUserRaw))
            : null;

        if (chan.isNotEmpty && tok.isNotEmpty) {
          await ref.read(matchmakingControllerProvider.notifier).startInstantCall(
            callId: cId,
            agoraChannelName: chan,
            agoraToken: tok,
            agoraUid: uid,
            remoteUid: rUid,
            otherUserName: otherName,
            matchedUser: matchedUser,
            agoraAppId: appId,
          );
        }
      }
    });

    // 10-Minute Milestone reached!
    socket.on('instant:milestone_reached', (data) {
      if (data is Map) {
        ScratchCardModel? unlockedCard;
        if (data['scratchCardId'] != null) {
          unlockedCard = ScratchCardModel(
            id: data['scratchCardId'] as String,
            sessionId: data['sessionId'] as String?,
            coinReward: (data['coinReward'] as num?)?.toInt() ?? 0,
            isScratched: false,
            createdAt: DateTime.now(),
          );
        }

        state = state.copyWith(
          is10mReached: true,
          latestUnlockedCard: unlockedCard,
        );

        fetchFemaleStatus();
        fetchScratchCards();
      }
    });

    socket.on('instant:call_ended', (data) {
      _callTimer?.cancel();
      state = state.reset();
      fetchFemaleStatus();
      fetchScratchCards();
      ref.invalidate(walletBalanceProvider);
      ref.read(matchmakingControllerProvider.notifier).endCall();
    });
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.phase != InstantPhase.inCall) {
        timer.cancel();
        return;
      }
      state = state.copyWith(callSecondsElapsed: state.callSecondsElapsed + 1);
    });
  }

  // ── Public API Methods ──────────────────────────────────────────────────

  /// Male: Join Instant Connect Priority Queue with bid
  Future<bool> joinQueue(int bidAmount) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      state = state.copyWith(errorMessage: 'Connecting to server...');
      return false;
    }

    final completer = Completer<bool>();
    socket.emitWithAck('instant:join_queue', {'bidAmount': bidAmount}, ack: (response) {
      if (response is Map && response['success'] == true) {
        final newBal = (response['newBalance'] as num?)?.toInt();
        if (newBal != null) {
          ref.read(walletBalanceProvider.notifier).setBalance(newBal);
        }
        state = state.copyWith(
          phase: InstantPhase.queued,
          sessionId: response['sessionId'] as String?,
          bidAmount: bidAmount,
          queuePosition: (response['queuePosition'] as num?)?.toInt() ?? 1,
        );
        completer.complete(true);
      } else {
        final errMsg = response is Map ? response['message']?.toString() : 'Failed to join instant queue';
        state = state.copyWith(errorMessage: errMsg);
        completer.complete(false);
      }
    });

    return completer.future;
  }

  /// Male: Cancel Queue and get 100% instant coin refund
  Future<void> leaveQueue() async {
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit('instant:leave_queue');
    }
    state = state.reset();
    ref.invalidate(walletBalanceProvider);
  }

  /// Female: Toggle "Incoming Paid Calls"
  Future<bool> toggleIncomingPaidCalls(bool enabled) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.dio.post('/api/instant/toggle', data: {'enabled': enabled});
      if (res.statusCode == 200 && res.data['success'] == true) {
        state = state.copyWith(
          femaleStatus: state.femaleStatus.copyWith(incomingPaidCallsEnabled: enabled),
        );
        final socket = _socket;
        if (socket != null && socket.connected) {
          socket.emit('instant:toggle_incoming', {'enabled': enabled});
        }
        return true;
      }
    } catch (e) {
      debugPrint('Error toggling incoming paid calls: $e');
    }
    return false;
  }

  /// Female: Accept incoming paid call
  void acceptIncomingCall() {
    final req = state.incomingRequest;
    if (req == null) return;
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emitWithAck(
        'instant:accept_call',
        {'callRequestId': req.callRequestId},
        ack: (response) {
          debugPrint('[Instant Connect] accept_call response: $response');
          if (response is Map && response['success'] == false) {
            state = state.copyWith(
              phase: InstantPhase.idle,
              clearIncomingRequest: true,
              errorMessage: response['message'] as String? ?? 'Call request is no longer available.',
            );
          }
        },
      );
    }
  }

  /// Female: Decline incoming paid call
  void declineIncomingCall() {
    final req = state.incomingRequest;
    if (req != null) {
      _socket?.emit('instant:decline_call', {'callRequestId': req.callRequestId});
    }
    state = state.copyWith(phase: InstantPhase.idle, clearIncomingRequest: true);
  }

  /// End active instant call
  void endCall() {
    _callTimer?.cancel();
    _socket?.emit('instant:end_call');
    state = state.reset();
  }

  /// Fetch female status from REST
  Future<void> fetchFemaleStatus() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.dio.get('/api/instant/status');
      if (res.statusCode == 200 && res.data != null) {
        state = state.copyWith(femaleStatus: FemaleInstantStatus.fromJson(res.data));
      }
    } catch (_) {}
  }

  /// Fetch all scratch cards
  Future<void> fetchScratchCards() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.dio.get('/api/instant/scratch-cards');
      if (res.statusCode == 200 && res.data?['scratchCards'] != null) {
        final list = (res.data['scratchCards'] as List)
            .map((json) => ScratchCardModel.fromJson(json as Map<String, dynamic>))
            .toList();
        state = state.copyWith(scratchCards: list);
      }
    } catch (_) {}
  }

  /// Scratch/Claim a card
  Future<int?> claimScratchCard(String cardId) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.dio.post('/api/instant/scratch-cards/$cardId/scratch');
      if (res.statusCode == 200 && res.data['success'] == true) {
        final reward = (res.data['coinReward'] as num?)?.toInt() ?? 0;
        final newBal = (res.data['newBalance'] as num?)?.toInt();
        if (newBal != null) {
          ref.read(walletBalanceProvider.notifier).setBalance(newBal);
        }

        // Optimistically update card list & female status
        final updatedCards = state.scratchCards.map((c) {
          if (c.id == cardId) {
            return ScratchCardModel(
              id: c.id,
              sessionId: c.sessionId,
              coinReward: reward,
              isScratched: true,
              scratchedAt: DateTime.now(),
              createdAt: c.createdAt,
            );
          }
          return c;
        }).toList();

        final newUnscratched = (state.femaleStatus.unscratchedCount - 1).clamp(0, 999);
        state = state.copyWith(
          scratchCards: updatedCards,
          femaleStatus: state.femaleStatus.copyWith(unscratchedCount: newUnscratched),
          latestUnlockedCard: state.latestUnlockedCard?.id == cardId
              ? ScratchCardModel(
                  id: cardId,
                  sessionId: state.latestUnlockedCard?.sessionId,
                  coinReward: reward,
                  isScratched: true,
                  scratchedAt: DateTime.now(),
                  createdAt: state.latestUnlockedCard?.createdAt ?? DateTime.now(),
                )
              : state.latestUnlockedCard,
        );

        await fetchFemaleStatus();
        await fetchScratchCards();
        return reward;
      }
    } catch (e) {
      debugPrint('Error claiming scratch card: $e');
    }
    return null;
  }
}

final instantConnectControllerProvider =
    NotifierProvider<InstantConnectController, InstantConnectState>(
  InstantConnectController.new,
);
