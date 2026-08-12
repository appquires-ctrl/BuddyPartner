import 'package:flutter/foundation.dart';

@immutable
class SubscriptionState {
  final bool isSubscribed;
  final DateTime? expiresAt;
  final int planDurationDays;
  final int remainingSeconds;
  final int remainingHours;
  final int remainingDays;
  final String formattedLabel;
  final bool hasClaimedIntroOffer;
  final bool isLoading;
  final String? errorMessage;

  const SubscriptionState({
    this.isSubscribed = false,
    this.expiresAt,
    this.planDurationDays = 0,
    this.remainingSeconds = 0,
    this.remainingHours = 0,
    this.remainingDays = 0,
    this.formattedLabel = 'Not Subscribed',
    this.hasClaimedIntroOffer = false,
    this.isLoading = false,
    this.errorMessage,
  });

  SubscriptionState copyWith({
    bool? isSubscribed,
    DateTime? expiresAt,
    int? planDurationDays,
    int? remainingSeconds,
    int? remainingHours,
    int? remainingDays,
    String? formattedLabel,
    bool? hasClaimedIntroOffer,
    bool? isLoading,
    String? errorMessage,
  }) {
    return SubscriptionState(
      isSubscribed: isSubscribed ?? this.isSubscribed,
      expiresAt: expiresAt ?? this.expiresAt,
      planDurationDays: planDurationDays ?? this.planDurationDays,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      remainingHours: remainingHours ?? this.remainingHours,
      remainingDays: remainingDays ?? this.remainingDays,
      formattedLabel: formattedLabel ?? this.formattedLabel,
      hasClaimedIntroOffer: hasClaimedIntroOffer ?? this.hasClaimedIntroOffer,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}
