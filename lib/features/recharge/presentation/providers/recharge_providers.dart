import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

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

/// walletBalanceProvider supplies the user's active wallet balance from Supabase.
final walletBalanceProvider = FutureProvider<int>((ref) async {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  if (user == null) return 0;

  final response = await Supabase.instance.client
      .from('wallets')
      .select('balance')
      .eq('user_id', user.id)
      .maybeSingle();

  if (response == null) return 100; // Default welcome bonus fallback
  return response['balance'] as int? ?? 100;
});

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
