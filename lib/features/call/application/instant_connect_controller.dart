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
import 'package:buddypartner/features/home/presentation/providers/matched_users_provider.dart';
import 'package:buddypartner/features/history/data/call_history_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';

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
  DateTime? _callStartedAt;
  Timer? _coldStartConnectTimer;
  bool _listenersRegistered = false;
  final Set<String> _declinedRequestIds = {};
  final Set<String> _inFlightClaimSessionIds = <String>{};
  final Map<String, Timer> _inFlightClaimTimers = <String, Timer>{};
  String? _pendingSurgeSessionId;
  int? _pendingSurgeBidAmount;

  sio.Socket? get _socket => ref.read(socketProvider);

  bool get isClaimingOrPending =>
      _inFlightClaimSessionIds.isNotEmpty ||
      (_pendingSurgeSessionId != null && _pendingSurgeSessionId!.isNotEmpty);

  @override
  InstantConnectState build() {
    ref.onDispose(() {
      _callTimer?.cancel();
      _coldStartConnectTimer?.cancel();
      for (final timer in _inFlightClaimTimers.values) {
        timer.cancel();
      }
      _inFlightClaimTimers.clear();
      _inFlightClaimSessionIds.clear();
      _listenersRegistered = false;
    });

    ref.listen<sio.Socket?>(socketProvider, (prev, next) {
      if (next != null) {
        _listenersRegistered = false;
        _setupSocketListeners(next);
        _checkAndEmitPendingSurge(next);
      } else {
        _listenersRegistered = false;
      }
    });

    ref.listen(authStateProvider, (prev, next) {
      final prevUser = prev?.value;
      final nextUser = next.value;

      if (nextUser == null || (prevUser != null && prevUser.id != nextUser.id)) {
        _callTimer?.cancel();
        _declinedRequestIds.clear();
        state = const InstantConnectState();
      }

      if (nextUser != null && nextUser.isFemale) {
        fetchFemaleStatus();
        fetchScratchCards();
      }
    });

    final existingSocket = ref.read(socketProvider);
    if (existingSocket != null && !_listenersRegistered) {
      Future.microtask(() {
        _setupSocketListeners(existingSocket);
        _checkAndEmitPendingSurge(existingSocket);
      });
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

  void _emitClaimAndJoin(sio.Socket socket, String sId, int bAmt) {
    debugPrint('🚀 [InstantConnect] Emitting instant:claim_and_join for session: $sId');
    socket.emitWithAck(
      'instant:claim_and_join',
      {'sessionId': sId, 'bidAmount': bAmt},
      ack: (response) {
        debugPrint('📡 [InstantConnect] instant:claim_and_join response: $response');
        _inFlightClaimTimers.remove(sId)?.cancel();
        _inFlightClaimSessionIds.remove(sId);

        if (response is Map && response['success'] == false) {
          final isSubRequired = response['error'] == 'SUBSCRIPTION_REQUIRED';
          if (isSubRequired) {
            final navContext = rootNavigatorKey.currentContext;
            if (navContext != null && navContext.mounted) {
              AppSnackBar.showError(
                navContext,
                response['message'] as String? ?? 'Active VIP Subscription Pass required to answer VIP calls.',
              );
              navContext.push(RouteNames.subscribe);
            }
          }

          // Guard: If the call already connected (e.g. instant:call_connected arrived before ack), do NOT revert to idle!
          if (state.phase == InstantPhase.inCall && state.sessionId == sId) {
            debugPrint('ℹ️ [InstantConnect] Received failure ack for $sId after call was already established. Preserving active call.');
            return;
          }

          final errMsg = response['message'] as String? ?? 'Another buddy already answered this VIP call.';
          state = state.copyWith(
            phase: InstantPhase.idle,
            clearIncomingRequest: true,
            errorMessage: errMsg,
          );
        }
      },
    );
  }

  void _checkAndEmitPendingSurge(sio.Socket socket) {
    if (_pendingSurgeSessionId != null && _pendingSurgeSessionId!.isNotEmpty) {
      final sessId = _pendingSurgeSessionId!;
      final bid = _pendingSurgeBidAmount ?? 99;
      _pendingSurgeSessionId = null;
      _pendingSurgeBidAmount = null;
      _coldStartConnectTimer?.cancel();
      _coldStartConnectTimer = null;
      debugPrint('🚀 [InstantConnect] Socket available! Emitting cached instant:claim_and_join: $sessId');
      _emitClaimAndJoin(socket, sessId, bid);
    }
  }

  void _syncIncomingPaidCallsState(sio.Socket socket) {
    final user = ref.read(authStateProvider).value;
    if (user != null && user.isFemale) {
      debugPrint('⚡ [InstantConnect] Female socket connected, syncing instant:toggle_incoming enabled=true');
      socket.emit('instant:toggle_incoming', {'enabled': true});
    }
  }

  void _setupSocketListeners(sio.Socket socket) {
    if (_listenersRegistered) return;
    _listenersRegistered = true;

    socket.on('connect', (_) {
      _checkAndEmitPendingSurge(socket);
      _syncIncomingPaidCallsState(socket);
    });
    if (socket.connected) {
      _checkAndEmitPendingSurge(socket);
      _syncIncomingPaidCallsState(socket);
    }

    // Incoming 1:2 parallel ring for female
    socket.on('incoming_instant_call', (data) {
      debugPrint('📞 [InstantConnect] Received incoming_instant_call payload: $data');
      if (data is Map) {
        final req = IncomingPaidCallRequest.fromJson(Map<String, dynamic>.from(data));

        // If we are currently claiming this surge session via notification tap, auto-join directly and suppress dialog
        if (_inFlightClaimSessionIds.contains(req.sessionId) || _pendingSurgeSessionId == req.sessionId) {
          debugPrint('[InstantConnect] Suppressed incoming popup for one-tap surge claim session: ${req.sessionId}');
          return;
        }

        // Drop if user previously declined this request
        if (_declinedRequestIds.contains(req.callRequestId)) {
          debugPrint('[InstantConnect] Dropped already declined request: ${req.callRequestId}');
          return;
        }

        // Guard: Drop incoming paid call if already in any active call or handling another incoming request
        final matchmakingPhase = ref.read(matchmakingControllerProvider).phase;
        if (state.phase == InstantPhase.inCall ||
            state.phase == InstantPhase.incomingRequest ||
            matchmakingPhase != MatchmakingPhase.idle) {
          debugPrint('[InstantConnect] Dropped incoming_instant_call: User is busy (instantPhase: ${state.phase}, mmPhase: $matchmakingPhase)');
          return;
        }

        debugPrint('🔔 [InstantConnect] Setting state to incomingRequest for callRequestId: ${req.callRequestId}, session: ${req.sessionId}');
        state = state.copyWith(
          phase: InstantPhase.incomingRequest,
          incomingRequest: req,
        );
      }
    });

    // Dismissal when other female answers or 15s timeout
    socket.on('instant_call_dismissed', (data) {
      if (state.phase == InstantPhase.inCall) {
        ref.read(matchmakingControllerProvider.notifier).endCall();
      }
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

        if (sessId != null && sessId.isNotEmpty) {
          _inFlightClaimTimers.remove(sessId)?.cancel();
          _inFlightClaimSessionIds.remove(sessId);
        }

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
        final sessId = data['sessionId'] as String?;
        // Ignore milestones belonging to stale or previous sessions
        if (sessId != null && state.sessionId != null && sessId != state.sessionId) {
          debugPrint('⚠️ [InstantConnect] Ignored milestone for outdated session $sessId (current: ${state.sessionId})');
          return;
        }

        ScratchCardModel? unlockedCard;
        if (data['scratchCardId'] != null) {
          unlockedCard = ScratchCardModel(
            id: data['scratchCardId'] as String,
            sessionId: sessId,
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
      _callStartedAt = null;
      state = state.reset();
      final authUser = ref.read(authStateProvider).value;
      if (authUser != null && authUser.isFemale) {
        fetchFemaleStatus();
        fetchScratchCards();
      }
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(matchedUsersProvider);
      ref.invalidate(callHistoryProvider);
      ref.read(matchmakingControllerProvider.notifier).endCall();
    });
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callStartedAt = DateTime.now();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.phase != InstantPhase.inCall) {
        timer.cancel();
        return;
      }
      final elapsed = _callStartedAt != null
          ? DateTime.now().difference(_callStartedAt!).inSeconds
          : state.callSecondsElapsed + 1;
      state = state.copyWith(callSecondsElapsed: elapsed);
    });
  }

  // ── Public API Methods ──────────────────────────────────────────────────

  /// Male: Join Instant Connect Priority Queue with coins
  Future<bool> joinQueue(int bidAmount) async {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      ref.read(socketProvider.notifier).setPresenceOnline();
      state = state.copyWith(errorMessage: 'Connecting to server. Please try again.');
      return false;
    }

    final completer = Completer<bool>();
    socket.emitWithAck('instant:join_queue', {'bidAmount': bidAmount}, ack: (response) {
      if (completer.isCompleted) return;
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

    return completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () {
        if (!completer.isCompleted) {
          state = state.copyWith(errorMessage: 'Connection timed out. Please try again.');
        }
        return false;
      },
    );
  }

  /// End active instant connect call and reset state
  void endCall() {
    final socket = _socket;
    final callId = state.callId;
    if (socket != null && socket.connected) {
      socket.emit('instant:end_call', {'callId': callId});
      socket.emit('end_call', {'callId': callId});
    }
    _callTimer?.cancel();
    state = state.reset();
    final authUser = ref.read(authStateProvider).value;
    if (authUser != null && authUser.isFemale) {
      fetchFemaleStatus();
      fetchScratchCards();
    }
    ref.invalidate(walletBalanceProvider);
    ref.invalidate(matchedUsersProvider);
    ref.invalidate(callHistoryProvider);
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

  /// Female: Toggle "Incoming Paid Calls" with 0ms Optimistic UI updates
  Future<bool> toggleIncomingPaidCalls(bool enabled) async {
    final previous = state.femaleStatus.incomingPaidCallsEnabled;
    
    // 1. Optimistic instant state update (0ms latency for UI Switch)
    state = state.copyWith(
      femaleStatus: state.femaleStatus.copyWith(incomingPaidCallsEnabled: enabled),
    );
    
    final socket = _socket;
    if (socket != null && socket.connected) {
      socket.emit('instant:toggle_incoming', {'enabled': enabled});
    }

    try {
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.dio.post('/api/instant/toggle', data: {'enabled': enabled});
      if (res.statusCode == 200 && res.data['success'] == true) {
        return true;
      } else {
        // Rollback state if server returns failure
        state = state.copyWith(
          femaleStatus: state.femaleStatus.copyWith(incomingPaidCallsEnabled: previous),
        );
        return false;
      }
    } catch (e) {
      debugPrint('Error toggling incoming paid calls: $e');
      // Rollback state on network error
      state = state.copyWith(
        femaleStatus: state.femaleStatus.copyWith(incomingPaidCallsEnabled: previous),
      );
      return false;
    }
  }

  /// Female: Accept incoming paid call (handles both live socket ring and push surge call)
  void acceptIncomingCall() {
    final req = state.incomingRequest;
    if (req == null) return;
    final socket = _socket;
    if (socket != null && socket.connected) {
      if (req.callRequestId.isNotEmpty) {
        socket.emitWithAck(
          'instant:accept_call',
          {'callRequestId': req.callRequestId},
          ack: (response) {
            debugPrint('[Instant Connect] accept_call response: $response');
            if (response is Map && response['success'] == false) {
              final isSubRequired = response['error'] == 'SUBSCRIPTION_REQUIRED';
              state = state.copyWith(
                phase: InstantPhase.idle,
                clearIncomingRequest: true,
                errorMessage: response['message'] as String? ?? 'Call request is no longer available.',
              );
              if (isSubRequired) {
                final navContext = rootNavigatorKey.currentContext;
                if (navContext != null && navContext.mounted) {
                  AppSnackBar.showError(
                    navContext,
                    response['message'] as String? ?? 'Active VIP Subscription Pass required to answer VIP calls.',
                  );
                  navContext.push(RouteNames.subscribe);
                }
              }
            }
          },
        );
      } else if (req.sessionId != null && req.sessionId!.isNotEmpty) {
        _emitClaimAndJoin(socket, req.sessionId!, req.bidAmount);
      }
    }
  }

  /// Female: Decline incoming paid call
  void declineIncomingCall() {
    final req = state.incomingRequest;
    if (req != null) {
      if (req.callRequestId.isNotEmpty) {
        _declinedRequestIds.add(req.callRequestId);
        _socket?.emit('instant:decline_call', {'callRequestId': req.callRequestId});
      }
      if (req.sessionId != null && req.sessionId!.isNotEmpty) {
        _declinedRequestIds.add(req.sessionId!);
      }
    }
    state = state.copyWith(phase: InstantPhase.idle, clearIncomingRequest: true);
  }

  /// Female: Show incoming surge call dialog with Accept/Decline options
  void showIncomingSurgeCall({required String sessionId, required int bidAmount}) {
    debugPrint('🔔 [InstantConnect] showIncomingSurgeCall called: session=$sessionId, bid=$bidAmount');
    if (sessionId.isEmpty) return;

    // Drop if user previously declined this request
    if (_declinedRequestIds.contains(sessionId)) {
      debugPrint('[InstantConnect] Dropped already declined surge session: $sessionId');
      return;
    }

    // Guard: If already in call or handling an incoming request, do not overwrite
    final mmPhase = ref.read(matchmakingControllerProvider).phase;
    if (state.phase == InstantPhase.inCall ||
        state.phase == InstantPhase.incomingRequest ||
        mmPhase != MatchmakingPhase.idle) {
      debugPrint('ℹ️ [InstantConnect] User busy (phase: ${state.phase}), suppressing incoming surge call.');
      return;
    }

    final req = IncomingPaidCallRequest(
      callRequestId: '',
      sessionId: sessionId,
      bidAmount: bidAmount,
      timeoutSeconds: 25,
    );

    state = state.copyWith(
      phase: InstantPhase.incomingRequest,
      incomingRequest: req,
    );
  }

  /// Female: Handle app launch from an Instant VIP push notification click (One-tap direct join)
  void handleNotificationLaunch({required String sessionId, required int bidAmount}) {
    if (sessionId.isEmpty) return;

    // Check female subscription state before claiming VIP call
    final isSubscribed = ref.read(subscriptionStatusProvider).value?.isSubscribed ?? false;
    if (!isSubscribed) {
      debugPrint('🚫 [InstantConnect] Unsubscribed female tapped VIP push notification. Redirecting to SubscribePage.');
      final navContext = rootNavigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        AppSnackBar.showError(
          navContext,
          'Active VIP Subscription Pass required to answer VIP calls.',
        );
        navContext.push(RouteNames.subscribe);
      }
      return;
    }

    // 1. Guard against duplicate launches if already in an active call for this session
    if (state.phase == InstantPhase.inCall && state.sessionId == sessionId) {
      debugPrint('ℹ️ [InstantConnect] Already in active call for session: $sessionId. Ignoring duplicate launch.');
      return;
    }

    // 2. Guard against duplicate in-flight claims (warm socket path)
    if (_inFlightClaimSessionIds.contains(sessionId)) {
      debugPrint('⏳ [InstantConnect] Claim for session $sessionId is already in flight. Ignoring duplicate launch.');
      return;
    }

    // 3. Guard against duplicate cold-start queueing (cold-start path)
    if (_pendingSurgeSessionId == sessionId) {
      debugPrint('⏳ [InstantConnect] Surge claim for session $sessionId is already queued for socket connect. Ignoring duplicate launch.');
      return;
    }

    // Register in-flight claim with 10-second safety timeout
    _inFlightClaimSessionIds.add(sessionId);
    _inFlightClaimTimers[sessionId]?.cancel();
    _inFlightClaimTimers[sessionId] = Timer(const Duration(seconds: 10), () {
      _inFlightClaimTimers.remove(sessionId);
      _inFlightClaimSessionIds.remove(sessionId);
    });

    final socket = _socket;
    if (socket != null && socket.connected) {
      _coldStartConnectTimer?.cancel();
      _coldStartConnectTimer = null;
      _emitClaimAndJoin(socket, sessionId, bidAmount);
    } else {
      debugPrint('⏳ [InstantConnect] Caching pending surge session: $sessionId until socket connects');
      _pendingSurgeSessionId = sessionId;
      _pendingSurgeBidAmount = bidAmount;

      _coldStartConnectTimer?.cancel();
      _coldStartConnectTimer = Timer(const Duration(seconds: 8), () {
        if (_pendingSurgeSessionId == sessionId) {
          debugPrint('⏱️ [InstantConnect] Cold-start socket connect timed out for session: $sessionId');
          final timedOutSessionId = _pendingSurgeSessionId!;
          _pendingSurgeSessionId = null;
          _pendingSurgeBidAmount = null;
          _inFlightClaimTimers.remove(timedOutSessionId)?.cancel();
          _inFlightClaimSessionIds.remove(timedOutSessionId);

          if (state.phase != InstantPhase.inCall) {
            state = state.copyWith(
              phase: InstantPhase.idle,
              errorMessage: 'Connection timed out. Please check your network and try again.',
            );
          }
        }
      });

      if (socket != null) {
        socket.once('connect', (_) {
          _checkAndEmitPendingSurge(socket);
        });
      }
    }
  }

  /// Fetch female status from REST
  Future<void> fetchFemaleStatus() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final res = await apiClient.dio.get('/api/instant/status');
      if (res.statusCode == 200 && res.data != null) {
        final status = FemaleInstantStatus.fromJson(res.data);
        state = state.copyWith(femaleStatus: status);
        if (status.incomingPaidCallsEnabled) {
          final socket = _socket;
          if (socket != null && socket.connected) {
            debugPrint('⚡ [InstantConnect] Status fetched: syncing toggle_incoming enabled=true');
            socket.emit('instant:toggle_incoming', {'enabled': true});
          }
        }
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

        // Refresh full status in background without blocking UI response
        unawaited(Future.wait([
          fetchFemaleStatus(),
          fetchScratchCards(),
        ]));
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
