import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/utils/digital_asset_pricing.dart';

/// RechargePlanUiModel represents the coin purchase pricing model with Option B (18% GST customer pays extra).
@immutable
class RechargePlanUiModel {
  final String id;
  final int coins;
  final int bonusCoins;
  final int basePriceRupees;
  final int gstRupees;
  final int totalPriceRupees;
  final String? badgeText;
  final bool isPopular;

  const RechargePlanUiModel({
    required this.id,
    required this.coins,
    this.bonusCoins = 0,
    required this.basePriceRupees,
    required this.gstRupees,
    required this.totalPriceRupees,
    this.badgeText,
    this.isPopular = false,
  });

  /// Total customer-facing price in INR (inclusive of 18% GST)
  double get price => totalPriceRupees.toDouble();

  /// Total coins delivered to the user wallet
  int get totalCoins => coins + bonusCoins;

  /// Digital asset pricing breakdown model
  DigitalAssetPricing get pricing => DigitalAssetPricing(
        basePriceRupees: basePriceRupees,
        gstRupees: gstRupees,
        totalPriceRupees: totalPriceRupees,
      );
}

/// rechargePlansProvider supplies list of plans with Option B pricing.
final rechargePlansProvider = Provider<List<RechargePlanUiModel>>((ref) {
  return const [
    RechargePlanUiModel(
      id: 'plan_49',
      coins: 49,
      bonusCoins: 0,
      basePriceRupees: 49,
      gstRupees: 9,
      totalPriceRupees: 58,
      badgeText: 'STARTER',
    ),
    RechargePlanUiModel(
      id: 'plan_99',
      coins: 99,
      bonusCoins: 0,
      basePriceRupees: 99,
      gstRupees: 18,
      totalPriceRupees: 117,
      badgeText: 'POPULAR',
      isPopular: true,
    ),
    RechargePlanUiModel(
      id: 'plan_199',
      coins: 199,
      bonusCoins: 0,
      basePriceRupees: 199,
      gstRupees: 36,
      totalPriceRupees: 235,
      badgeText: 'STANDARD',
    ),
    RechargePlanUiModel(
      id: 'plan_499',
      coins: 499,
      bonusCoins: 50,
      basePriceRupees: 499,
      gstRupees: 90,
      totalPriceRupees: 589,
      badgeText: '50 BONUS COINS',
    ),
    RechargePlanUiModel(
      id: 'plan_999',
      coins: 999,
      bonusCoins: 100,
      basePriceRupees: 999,
      gstRupees: 180,
      totalPriceRupees: 1179,
      badgeText: 'BEST VALUE',
    ),
    RechargePlanUiModel(
      id: 'plan_2500',
      coins: 2500,
      bonusCoins: 250,
      basePriceRupees: 2500,
      gstRupees: 450,
      totalPriceRupees: 2950,
      badgeText: '250 BONUS COINS',
    ),
  ];
});

/// Model representing a pending order request to immediately preselect a plan
/// and display the Order Summary bottom sheet on the wallet/recharge screen.
@immutable
class RechargeOrderRequest {
  final String planId;
  final bool autoOpenSummary;
  final String? reason;

  const RechargeOrderRequest({
    required this.planId,
    this.autoOpenSummary = false,
    this.reason,
  });
}

/// Provider that tracks a pending order summary request
final pendingRechargeOrderProvider = StateProvider<RechargeOrderRequest?>((ref) => null);

/// Finds the most optimal coin recharge plan to cover the required coin deficit.
/// Returns the smallest plan where `totalCoins >= neededCoins`, or the highest plan available.
RechargePlanUiModel findRecommendedRechargePlan(List<RechargePlanUiModel> plans, int neededCoins) {
  if (plans.isEmpty) {
    throw StateError('No recharge plans available');
  }

  // Sort plans ascending by total coins delivered
  final sortedPlans = [...plans]..sort((a, b) => a.totalCoins.compareTo(b.totalCoins));

  for (final plan in sortedPlans) {
    if (plan.totalCoins >= neededCoins) {
      return plan;
    }
  }

  return sortedPlans.last;
}

/// Helper that calculates the missing coins, selects the optimal recharge plan,
/// and routes the user directly to the Wallet store with the plan selected.
void openRechargeForDeficit({
  BuildContext? context,
  required WidgetRef ref,
  required int requiredCoins,
  required int currentBalance,
  String? featureName,
}) {
  final deficit = (requiredCoins - currentBalance).clamp(1, 999999);
  final plans = ref.read(rechargePlansProvider);
  final recommendedPlan = findRecommendedRechargePlan(plans, deficit);

  ref.read(pendingRechargeOrderProvider.notifier).state = RechargeOrderRequest(
    planId: recommendedPlan.id,
    autoOpenSummary: false,
    reason: featureName,
  );

  final targetContext = (context != null && context.mounted)
      ? context
      : rootNavigatorKey.currentContext;

  if (targetContext != null && targetContext.mounted) {
    try {
      targetContext.go(RouteNames.plans);
    } catch (_) {
      targetContext.push(RouteNames.recharge);
    }
  }
}

