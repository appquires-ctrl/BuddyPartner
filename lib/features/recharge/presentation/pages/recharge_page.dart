import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/features/recharge/presentation/providers/recharge_providers.dart';
import 'package:dating_app/features/recharge/presentation/widgets/recharge_plan_card.dart';
import 'package:dating_app/core/widgets/cards/wallet_card.dart';
import 'package:dating_app/core/widgets/layout/section_header.dart';
import 'package:dating_app/app/theme/app_spacing.dart';

/// RechargePage manages the wallet screen, containing
/// the WalletCard balance hero, and a 2-column grid of RechargePlanCards.
class RechargePage extends ConsumerWidget {
  const RechargePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(walletBalanceProvider);
    final balance = balanceAsync.value ?? 100;
    final plans = ref.watch(rechargePlansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recharge Store'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space24,
          vertical: AppSpacing.space8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Subtitle info
            const Center(
              child: Text(
                'Add coins to your wallet',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            const SizedBox(height: AppSpacing.space16),

            // Wallet Card balance display hero
            WalletCard(
              balance: balance,
              onRechargePressed: null, // already on recharge page
            ),
            const SizedBox(height: AppSpacing.space24),
            
            // Section Header title
            const SectionHeader(
              title: 'RECHARGE PLANS',
            ),
            const SizedBox(height: AppSpacing.space12),
            
            // 2-Column Grid of plans
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: plans.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.space16,
                mainAxisSpacing: AppSpacing.space16,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) {
                final plan = plans[index];
                return RechargePlanCard(
                  coins: plan.coins,
                  price: plan.price,
                  originalPrice: plan.originalPrice,
                  badgeText: plan.badgeText,
                  onPurchasePressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Processing purchase for ${plan.coins} coins...')),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: AppSpacing.space32),
          ],
        ),
      ),
    );
  }
}
