import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/utils/app_snack_bar.dart';
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
    const balance = 0;
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

            WalletCard(
              balance: balance,
              onRechargePressed: null, // already on recharge page
            ),
            const SizedBox(height: AppSpacing.space12),

            // View Transaction History Link
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push(RouteNames.transactionHistory),
                icon: const Icon(Icons.history_rounded, size: 18),
                label: const Text(
                  'View History',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.space16),
            
            // Section Header title
            const SectionHeader(
              title: 'RECHARGE PLANS',
            ),
            const SizedBox(height: AppSpacing.space12),
            
            // Dynamic column count responsive Grid of plans
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: plans.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width > 800 ? 4 : (MediaQuery.of(context).size.width > 600 ? 3 : 2),
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
                    AppSnackBar.showInfo(context, 'Processing purchase for ${plan.coins} coins...');
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
