import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/core/services/api_client.dart';
import 'package:dating_app/features/subscription/application/subscription_state.dart';
import 'package:dating_app/features/subscription/domain/subscription_plan.dart';

class SubscriptionNotifier extends AsyncNotifier<SubscriptionState> {
  Timer? _countdownTimer;

  @override
  Future<SubscriptionState> build() async {
    // Session-long scope: setup timer disposal
    ref.onDispose(() {
      _countdownTimer?.cancel();
    });

    return fetchStatus();
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

        final statePayload = _calculateTimeState(isSub: isSub, expiresAt: expiresAt, planDays: planDays);
        _startTimer();
        return statePayload;
      }
    } catch (e) {
      // In case of error (e.g. unauthenticated or network offline), fallback gracefully
    }

    return const SubscriptionState(isSubscribed: false, formattedLabel: 'Not Subscribed');
  }

  SubscriptionState _calculateTimeState({
    required bool isSub,
    required DateTime? expiresAt,
    required int planDays,
  }) {
    if (!isSub || expiresAt == null) {
      return const SubscriptionState(isSubscribed: false, formattedLabel: 'Not Subscribed');
    }

    final now = DateTime.now();
    final diff = expiresAt.difference(now);

    if (diff.isNegative) {
      return SubscriptionState(
        isSubscribed: false,
        expiresAt: expiresAt,
        planDurationDays: planDays,
        formattedLabel: 'Expired',
      );
    }

    final remainingSecs = diff.inSeconds;
    final remainingHrs = diff.inHours;
    final remainingDays = diff.inDays;

    String label;
    if (remainingHrs < 24) {
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
      );

      state = AsyncData(newState);
      if (!newState.isSubscribed) {
        _countdownTimer?.cancel();
      }
    });
  }

  /// Dev method to activate subscription without real payment gateway
  Future<bool> devStartSubscription(SubscriptionPlan plan) async {
    state = const AsyncValue.loading();
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.post('/api/subscriptions/dev-start', data: {
        'planId': plan.id,
        'planDurationDays': plan.durationDays,
        'amountPaid': plan.priceRupees,
      });

      if (response.statusCode == 200) {
        final updatedState = await fetchStatus();
        state = AsyncData(updatedState);
        return true;
      }
    } catch (_) {
      // Graceful local activation fallback for dev testing
    }

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

  /// Dev method to instantly expire subscription for testing
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
