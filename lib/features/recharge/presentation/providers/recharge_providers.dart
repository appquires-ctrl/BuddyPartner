import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  ];
});
