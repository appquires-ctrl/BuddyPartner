import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/services/apptrove_service.dart';
import 'package:buddypartner/core/services/socket_provider.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/subscription/application/subscription_state.dart';
import 'package:buddypartner/features/subscription/domain/subscription_plan.dart';

class SubscriptionNotifier extends AsyncNotifier<SubscriptionState> {
  Timer? _countdownTimer;

  @override
  Future<SubscriptionState> build() async {
    ref.onDispose(() {
      _countdownTimer?.cancel();
    });

    // Auto-refresh subscription state whenever socket connects
    ref.listen<sio.Socket?>(socketProvider, (prev, next) {
      if (next != null) {
        reload();
      }
    });

    final authUser = ref.watch(authStateProvider).value;
    if (authUser == null) {
      _countdownTimer?.cancel();
      return const SubscriptionState(isSubscribed: false, formattedLabel: 'Not Subscribed');
    }

    return fetchStatus();
  }

  Future<void> reload() async {
    final newState = await fetchStatus();
    state = AsyncData(newState);
  }

  Future<SubscriptionState> fetchStatus() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get('/api/subscriptions/status');

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final isSub = data['isSubscribed'] as bool? ?? false;
        final expiresAtStr = data['expiresAt'] as String?;
        final expiresAt = expiresAtStr != null ? DateTime.tryParse(expiresAtStr) : null;
        final planDays = (data['planDurationDays'] as num?)?.toInt() ?? 0;
        final hasClaimedIntroOffer = data['hasClaimedIntroOffer'] as bool? ?? false;

        final statePayload = _calculateTimeState(
          isSub: isSub,
          expiresAt: expiresAt,
          planDays: planDays,
          hasClaimedIntroOffer: hasClaimedIntroOffer,
        );
        _startTimer();
        return statePayload;
      }
    } catch (_) {
      // Fail gracefully without blind timer loops; retry is handled via socket reconnect / user action
    }

    return const SubscriptionState(isSubscribed: false, formattedLabel: 'Not Subscribed');
  }

  SubscriptionState _calculateTimeState({
    required bool isSub,
    required DateTime? expiresAt,
    required int planDays,
    bool hasClaimedIntroOffer = false,
  }) {
    if (!isSub || expiresAt == null) {
      return SubscriptionState(
        isSubscribed: false,
        formattedLabel: 'Not Subscribed',
        hasClaimedIntroOffer: hasClaimedIntroOffer,
      );
    }

    final now = DateTime.now();
    final diff = expiresAt.difference(now);

    if (diff.isNegative) {
      return SubscriptionState(
        isSubscribed: false,
        expiresAt: expiresAt,
        planDurationDays: planDays,
        formattedLabel: 'Expired',
        hasClaimedIntroOffer: hasClaimedIntroOffer,
      );
    }

    final remainingSecs = diff.inSeconds;
    final remainingHrs = (remainingSecs / 3600).ceil();
    final remainingDays = (remainingHrs / 24).ceil();

    String label;
    if (remainingHrs <= 24) {
      final hrs = remainingHrs <= 0 ? 1 : remainingHrs;
      label = '$hrs hour${hrs == 1 ? '' : 's'} left';
    } else {
      final days = remainingDays <= 0 ? 1 : remainingDays;
      label = '$days day${days == 1 ? '' : 's'} left';
    }

    return SubscriptionState(
      isSubscribed: true,
      expiresAt: expiresAt,
      planDurationDays: planDays,
      remainingSeconds: remainingSecs,
      remainingHours: remainingHrs,
      remainingDays: remainingDays,
      formattedLabel: label,
      hasClaimedIntroOffer: hasClaimedIntroOffer,
    );
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final currentVal = state.value;
      if (currentVal == null || !currentVal.isSubscribed || currentVal.expiresAt == null) {
        _countdownTimer?.cancel();
        return;
      }

      final newState = _calculateTimeState(
        isSub: true,
        expiresAt: currentVal.expiresAt,
        planDays: currentVal.planDurationDays,
        hasClaimedIntroOffer: currentVal.hasClaimedIntroOffer,
      );

      state = AsyncData(newState);
      if (!newState.isSubscribed) {
        _countdownTimer?.cancel();
      }
    });
  }

  /// Activate subscription via backend API (with fallback for dev mode)
  Future<bool> devStartSubscription(SubscriptionPlan plan) async {
    state = const AsyncValue.loading();
    try {
      final apiClient = ref.read(apiClientProvider);
      Response? response;
      try {
        response = await apiClient.dio.post('/api/subscriptions/dev-start', data: {
          'planId': plan.id,
          'planDurationDays': plan.durationDays,
          'amountPaid': plan.priceRupees,
        });
      } on DioException catch (e) {
        if (e.response?.statusCode == 400) {
          final serverErr = e.response?.data?['error'] ?? 'Subscription request failed.';
          state = AsyncError(Exception(serverErr), StackTrace.current);
          return false;
        }
        if (e.response?.statusCode == 403 || e.response?.statusCode == 404) {
          response = await apiClient.dio.post('/api/subscriptions/subscribe', data: {
            'planId': plan.id,
            'planDurationDays': plan.durationDays,
            'amountPaid': plan.priceRupees,
          });
        } else {
          rethrow;
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Track subscription purchase in Apptrove
        AppTroveService.trackSubscriptionPurchase(
          planId: plan.id,
          planTitle: plan.title,
          priceRupees: plan.priceRupees.toDouble(),
          durationDays: plan.durationDays,
        );

        // Refresh auth state and profile so hasClaimedIntroOffer updates across app
        Future.microtask(() {
          ref.invalidate(authStateProvider);
          ref.invalidate(userProfileProvider);
        });
        final updatedState = await fetchStatus();
        state = AsyncData(updatedState);
        return true;
      }
    } catch (e, stack) {
      if (e is DioException && e.response?.data is Map) {
        final serverErr = e.response?.data['error'] ?? 'Subscription activation failed.';
        state = AsyncError(Exception(serverErr), stack);
        return false;
      }
    }

    // Track subscription purchase in Apptrove (fallback mode)
    AppTroveService.trackSubscriptionPurchase(
      planId: plan.id,
      planTitle: plan.title,
      priceRupees: plan.priceRupees.toDouble(),
      durationDays: plan.durationDays,
    );

    final expiresAt = DateTime.now().add(Duration(days: plan.durationDays));
    final devState = SubscriptionState(
      isSubscribed: true,
      expiresAt: expiresAt,
      planDurationDays: plan.durationDays,
      remainingSeconds: plan.durationDays * 86400,
      remainingHours: plan.durationDays * 24,
      remainingDays: plan.durationDays,
      formattedLabel: '${plan.durationDays} day${plan.durationDays == 1 ? '' : 's'} left',
    );
    state = AsyncData(devState);
    _startTimer();
    return true;
  }

  /// Instantly expire subscription for testing
  Future<bool> devExpireSubscription() async {
    state = const AsyncValue.loading();
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.post('/api/subscriptions/dev-expire');

      if (response.statusCode == 200) {
        final updatedState = await fetchStatus();
        state = AsyncData(updatedState);
        return true;
      }
    } catch (_) {
      // Graceful local expiration fallback
    }

    _countdownTimer?.cancel();
    state = const AsyncData(SubscriptionState(isSubscribed: false, formattedLabel: 'Not Subscribed'));
    return true;
  }
}

final subscriptionStatusProvider = AsyncNotifierProvider<SubscriptionNotifier, SubscriptionState>(
  SubscriptionNotifier.new,
);
