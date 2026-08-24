import 'package:flutter_riverpod/flutter_riverpod.dart';

/// RechargePlanUiModel represents the coin purchase pricing model (1 INR = 1 Coin).
class RechargePlanUiModel {
  final String id;
  final int coins;
  final int bonusCoins;
  final double price; // Price in INR (1 INR = 1 Coin)
  final String? badgeText;
  final bool isPopular;

  const RechargePlanUiModel({
    required this.id,
    required this.coins,
    this.bonusCoins = 0,
    required this.price,
    this.badgeText,
    this.isPopular = false,
  });

  int get totalCoins => coins + bonusCoins;
}

/// rechargePlansProvider supplies list of plans with 1 Rupee = 1 Coin rate.
final rechargePlansProvider = Provider<List<RechargePlanUiModel>>((ref) {
  return const [
    RechargePlanUiModel(
      id: 'plan_20',
      coins: 20,
      bonusCoins: 0,
      price: 20.0,
      badgeText: 'STARTER',
    ),
    RechargePlanUiModel(
      id: 'plan_50',
      coins: 50,
      bonusCoins: 0,
      price: 50.0,
      badgeText: 'POPULAR',
      isPopular: true,
    ),
    RechargePlanUiModel(
      id: 'plan_100',
      coins: 100,
      bonusCoins: 10,
      price: 100.0,
      badgeText: '10% EXTRA',
      isPopular: true,
    ),
    RechargePlanUiModel(
      id: 'plan_200',
      coins: 200,
      bonusCoins: 30,
      price: 200.0,
      badgeText: '15% EXTRA',
    ),
    RechargePlanUiModel(
      id: 'plan_500',
      coins: 500,
      bonusCoins: 100,
      price: 500.0,
      badgeText: '20% VIP BONUS',
    ),
    RechargePlanUiModel(
      id: 'plan_1000',
      coins: 1000,
      bonusCoins: 250,
      price: 1000.0,
      badgeText: '25% BEST VALUE',
    ),
  ];
});
