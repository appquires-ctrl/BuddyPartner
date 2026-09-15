import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:buddypartner/core/services/socket_provider.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:buddypartner/features/buddy/data/buddy_service.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/accepter_otp_dialog.dart';

class BuddyState {
  final List<BuddyRequest> openRequests;
  final List<BuddyRequest> myRequests;
  final bool isLoading;
  final String? errorMessage;
  final BuddyRequest? activeInitiatorRequest;
  final BuddyRequest? activeAccepterRequest;

  const BuddyState({
    this.openRequests = const [],
    this.myRequests = const [],
    this.isLoading = false,
    this.errorMessage,
    this.activeInitiatorRequest,
    this.activeAccepterRequest,
  });

  BuddyState copyWith({
    List<BuddyRequest>? openRequests,
    List<BuddyRequest>? myRequests,
    bool? isLoading,
    String? errorMessage,
    bool clearErrorMessage = false,
    BuddyRequest? activeInitiatorRequest,
    bool clearActiveInitiatorRequest = false,
    BuddyRequest? activeAccepterRequest,
    bool clearActiveAccepterRequest = false,
  }) {
    return BuddyState(
      openRequests: openRequests ?? this.openRequests,
      myRequests: myRequests ?? this.myRequests,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      activeInitiatorRequest: clearActiveInitiatorRequest ? null : (activeInitiatorRequest ?? this.activeInitiatorRequest),
      activeAccepterRequest: clearActiveAccepterRequest ? null : (activeAccepterRequest ?? this.activeAccepterRequest),
    );
  }
}

class BuddyController extends Notifier<BuddyState> {
  bool _listenersRegistered = false;

  sio.Socket? get _socket => ref.read(socketProvider);

  @override
  BuddyState build() {
    ref.onDispose(() {
      _removeSocketListeners();
      _listenersRegistered = false;
    });

    ref.listen<sio.Socket?>(socketProvider, (prev, next) {
      if (next != null) {
        _listenersRegistered = false;
        _setupSocketListeners(next);
      } else {
        _listenersRegistered = false;
      }
    });

    final socket = ref.read(socketProvider);
    if (socket != null) {
      _setupSocketListeners(socket);
    }

    // Auto-fetch requests on init
    Future.microtask(() {
      fetchMyRequests();
      final city = ref.read(authStateProvider).value?.city;
      if (city != null && city.isNotEmpty) {
        joinCityRoom(city);
        fetchOpenRequests(city: city);
      }
    });

    return const BuddyState();
  }

  void _setupSocketListeners(sio.Socket socket) {
    if (_listenersRegistered) return;
    _listenersRegistered = true;

    // 1. When a new buddy request is broadcast in the user's city
    socket.on('new_buddy_request', _handleNewBuddyRequest);

    // 2. When an open request is accepted by someone else
    socket.on('buddy_request_taken', _handleBuddyRequestTaken);

    // 3. Directly for initiator: someone accepted their request! (contains 6-digit OTP)
    socket.on('buddy_request_accepted', _handleBuddyRequestAccepted);

    // 4. Directly for initiator: accepter verified the OTP -> chat unlocked!
    socket.on('buddy_request_verified', _handleBuddyRequestVerified);
  }

  void _removeSocketListeners() {
    final socket = _socket;
    if (socket == null) return;
    socket.off('new_buddy_request', _handleNewBuddyRequest);
    socket.off('buddy_request_taken', _handleBuddyRequestTaken);
    socket.off('buddy_request_accepted', _handleBuddyRequestAccepted);
    socket.off('buddy_request_verified', _handleBuddyRequestVerified);
  }

  void _handleNewBuddyRequest(dynamic data) {
    if (data == null || data is! Map) return;
    try {
      final currentUserId = ref.read(authStateProvider).value?.id;
      final request = BuddyRequest.fromJson(
        Map<String, dynamic>.from(data),
        currentUserId: currentUserId,
      );

      // Do not add if it's the initiator's own request
      if (request.initiatorId == currentUserId) return;

      final updated = [
        request,
        ...state.openRequests.where((r) => r.id != request.id),
      ];
      state = state.copyWith(openRequests: updated);

      // In-app card notification for notified users
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        final initiatorName = request.initiator?.fullName ?? 'Someone';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: const Color(0xFF1F2937),
            content: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    request.buddyType.stickerAsset,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) => const Icon(
                      Icons.local_activity,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$initiatorName is finding a ${request.buddyType.title}!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Accept to get ${request.accepterCoinReward} coins',
                        style: const TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            action: SnackBarAction(
              label: 'Accept',
              textColor: const Color(0xFFFBBF24),
              onPressed: () {
                acceptBuddyRequest(request.id).then((accepted) {
                  final ctx = rootNavigatorKey.currentContext;
                  if (ctx != null && ctx.mounted) {
                    AccepterOtpDialog.show(ctx, request: accepted);
                  }
                }).catchError((err) {
                  final ctx = rootNavigatorKey.currentContext;
                  if (ctx != null && ctx.mounted) {
                    AppSnackBar.showError(
                      ctx,
                      err.toString().replaceAll('Exception: ', ''),
                    );
                  }
                });
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('[BuddyController] Error handling new_buddy_request: $e');
    }
  }

  void _handleBuddyRequestTaken(dynamic data) {
    if (data == null || data is! Map) return;
    try {
      final requestId = data['requestId'] as String?;
      if (requestId == null) return;

      final updated = state.openRequests.where((r) => r.id != requestId).toList();
      state = state.copyWith(openRequests: updated);
    } catch (_) {}
  }

  void _handleBuddyRequestAccepted(dynamic data) {
    if (data == null || data is! Map) return;
    try {
      final currentUserId = ref.read(authStateProvider).value?.id;
      final requestData = Map<String, dynamic>.from(data);
      final requestId = requestData['requestId'] as String?;
      final otpCode = requestData['otpCode'] as String?;
      final accepterJson = requestData['accepter'] as Map<String, dynamic>?;

      if (requestId == null) return;

      BuddyUserSummary? accepterSummary;
      if (accepterJson != null) {
        accepterSummary = BuddyUserSummary.fromJson(accepterJson);
      }

      // Update in myRequests
      final updatedMyRequests = state.myRequests.map((r) {
        if (r.id == requestId) {
          return r.copyWith(
            status: BuddyRequestStatus.accepted,
            otpCode: otpCode,
            accepter: accepterSummary,
            accepterId: accepterSummary?.id,
          );
        }
        return r;
      }).toList();

      final matchingReq = state.myRequests.firstWhere(
        (r) => r.id == requestId,
        orElse: () => BuddyRequest(
          id: requestId,
          initiatorId: currentUserId ?? '',
          buddyType: BuddyType.movie,
          city: '',
          targetGender: BuddyTargetGender.all,
          status: BuddyRequestStatus.accepted,
          otpCode: otpCode,
          accepter: accepterSummary,
          accepterId: accepterSummary?.id,
          createdAt: DateTime.now(),
        ),
      );

      final acceptedReq = matchingReq.copyWith(
        status: BuddyRequestStatus.accepted,
        otpCode: otpCode,
        accepter: accepterSummary,
        accepterId: accepterSummary?.id,
      );

      state = state.copyWith(
        myRequests: updatedMyRequests,
        activeInitiatorRequest: acceptedReq,
      );

      // Show in-app alert that someone accepted
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        AppSnackBar.showSuccess(
          context,
          '${accepterSummary?.fullName ?? "Someone"} accepted your ${acceptedReq.buddyType.title}! Share your OTP to verify.',
        );
      }
    } catch (e) {
      debugPrint('[BuddyController] Error handling buddy_request_accepted: $e');
    }
  }

  void _handleBuddyRequestVerified(dynamic data) {
    if (data == null || data is! Map) return;
    try {
      final map = Map<String, dynamic>.from(data);
      final conversationId = map['conversationId'] as String?;
      final accepter = map['accepter'] as Map<String, dynamic>?;

      // Clear active initiator modal
      state = state.copyWith(
        clearActiveInitiatorRequest: true,
      );

      fetchMyRequests();

      // Navigate to chat
      if (conversationId != null && conversationId.isNotEmpty) {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          AppSnackBar.showSuccess(context, 'Handshake verified! Chat unlocked.');
          Navigator.of(context, rootNavigator: true).popUntil((route) => route is! PopupRoute);
          context.push(
            RouteNames.chat,
            extra: {
              'conversationId': conversationId,
              'userId': accepter?['id'] ?? '',
              'userName': accepter?['fullName'] ?? 'Buddy Partner',
              'avatarSeed': accepter?['avatarSeed'],
              'avatarStyle': accepter?['avatarStyle'],
              'gender': accepter?['gender'],
            },
          );
        }
      }
    } catch (e) {
      debugPrint('[BuddyController] Error handling buddy_request_verified: $e');
    }
  }

  void joinCityRoom(String city) {
    if (city.trim().isEmpty) return;
    _socket?.emit('join_buddy_city', {'city': city.trim()});
  }

  Future<void> fetchOpenRequests({String? city, BuddyType? buddyType}) async {
    try {
      state = state.copyWith(isLoading: true, clearErrorMessage: true);
      final requests = await ref.read(buddyServiceProvider).listOpenRequests(
        city: city,
        buddyType: buddyType,
      );
      state = state.copyWith(openRequests: requests, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> fetchMyRequests() async {
    try {
      final requests = await ref.read(buddyServiceProvider).getMyRequests();
      state = state.copyWith(myRequests: requests);
    } catch (_) {}
  }

  /// Initiator posts a new broadcast request. Deducts 100 coins immediately.
  Future<BuddyRequest> createBuddyRequest({
    required BuddyType type,
    required String city,
    required BuddyTargetGender targetGender,
  }) async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    try {
      final newRequest = await ref.read(buddyServiceProvider).createRequest(
        buddyType: type,
        city: city,
        targetGender: targetGender,
      );

      // Refresh wallet balance (100 coins deducted)
      ref.read(walletBalanceProvider.notifier).fetchBalance();

      // Update state
      state = state.copyWith(
        isLoading: false,
        myRequests: [newRequest, ...state.myRequests],
      );

      return newRequest;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  /// Accepter accepts an open buddy request.
  Future<BuddyRequest> acceptBuddyRequest(String requestId) async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    try {
      final accepted = await ref.read(buddyServiceProvider).acceptRequest(requestId);

      // Remove from openRequests feed
      final updatedOpen = state.openRequests.where((r) => r.id != requestId).toList();

      state = state.copyWith(
        isLoading: false,
        openRequests: updatedOpen,
        myRequests: [accepted, ...state.myRequests],
        activeAccepterRequest: accepted,
      );

      return accepted;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  /// Accepter submits OTP to unlock chat and claim 50 coins.
  Future<Map<String, dynamic>> verifyBuddyOtp({
    required String requestId,
    required String otpCode,
  }) async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    try {
      final result = await ref.read(buddyServiceProvider).verifyOtp(
        requestId: requestId,
        otpCode: otpCode,
      );

      // Refresh wallet balance (50 coins reward added)
      ref.read(walletBalanceProvider.notifier).fetchBalance();

      // Clear active accepter state
      state = state.copyWith(
        isLoading: false,
        clearActiveAccepterRequest: true,
      );

      fetchMyRequests();

      return result;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  /// Fetch initiator OTP from authenticated REST endpoint
  Future<String> fetchInitiatorOtp(String requestId) async {
    try {
      final otp = await ref.read(buddyServiceProvider).getInitiatorOtp(requestId);
      if (otp.isNotEmpty) {
        final updatedMy = state.myRequests.map((r) {
          if (r.id == requestId) {
            return r.copyWith(otpCode: otp);
          }
          return r;
        }).toList();
        final currentActive = state.activeInitiatorRequest;
        final updatedActive = currentActive?.id == requestId ? currentActive?.copyWith(otpCode: otp) : currentActive;
        state = state.copyWith(
          myRequests: updatedMy,
          activeInitiatorRequest: updatedActive,
        );
      }
      return otp;
    } catch (e) {
      debugPrint('[BuddyController] Error fetching OTP: $e');
      rethrow;
    }
  }

  void dismissInitiatorOtpModal() {
    state = state.copyWith(clearActiveInitiatorRequest: true);
  }

  void dismissAccepterOtpDialog() {
    state = state.copyWith(clearActiveAccepterRequest: true);
  }
}

final buddyControllerProvider = NotifierProvider<BuddyController, BuddyState>(
  BuddyController.new,
);
