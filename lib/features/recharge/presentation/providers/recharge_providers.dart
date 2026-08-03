import 'package:flutter_riverpod/flutter_riverpod.dart';

/// RechargePlanUiModel represents the coin purchase pricing model.
class RechargePlanUiModel {
  final String id;
  final int coins;
  final double price;
  final double? originalPrice;
  final String? badgeText;

  const RechargePlanUiModel({
    required this.id,
    required this.coins,
    required this.price,
    this.originalPrice,
    this.badgeText,
  });
}



/// rechargePlansProvider supplies list of plans with rupee costs matching screenshots.
final rechargePlansProvider = Provider<List<RechargePlanUiModel>>((ref) {
  return const [
    RechargePlanUiModel(
      id: 'plan_1',
      coins: 100,
      price: 9.0,
      badgeText: 'SPECIAL OFFER',
    ),
    RechargePlanUiModel(
      id: 'plan_2',
      coins: 150,
      price: 49.0,
      badgeText: 'SPECIAL OFFER',
    ),
    RechargePlanUiModel(
      id: 'plan_3',
      coins: 250,
      price: 189.0,
      originalPrice: 210.0,
      badgeText: '10.0% OFF',
    ),
    RechargePlanUiModel(
      id: 'plan_4',
      coins: 300,
      price: 249.0,
    ),
    RechargePlanUiModel(
      id: 'plan_5',
      coins: 500,
      price: 399.0,
    ),
    RechargePlanUiModel(
      id: 'plan_6',
      coins: 1000,
      price: 799.0,
      badgeText: 'BEST VALUE',
    ),
  ];
});
