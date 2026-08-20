import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/cards/wallet_card.dart';
import 'package:buddypartner/core/widgets/layout/section_header.dart';
import 'package:buddypartner/features/recharge/presentation/providers/recharge_providers.dart';
import 'package:buddypartner/features/recharge/presentation/widgets/recharge_plan_card.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

/// RechargePage manages the wallet screen, containing
/// the WalletCard balance hero, and a 2-column grid of RechargePlanCards.
class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  String? _purchasingPlanId;

  Future<void> _handlePurchase(RechargePlanUiModel plan) async {
    AppLogger.button('Purchase ${plan.coins} Coins', screen: 'RechargePage');
    setState(() => _purchasingPlanId = plan.id);

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.post(
        '/api/wallet/recharge',
        data: {
          'amount': plan.coins,
          'paymentReference': 'recharge_${plan.id}_${DateTime.now().millisecondsSinceEpoch}',
        },
      );

      if (response.data != null && response.data['success'] == true) {
        ref.invalidate(walletBalanceProvider);
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: const Row(
                children: [
                  Text('🪙', style: TextStyle(fontSize: 28)),
                  SizedBox(width: 10),
                  Text('Recharge Successful!'),
                ],
              ),
              content: Text(
                'Successfully added ${plan.coins} Coins to your wallet for ₹${plan.price.toStringAsFixed(0)}.',
                style: const TextStyle(fontSize: 15),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Awesome', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          AppSnackBar.showError(context, response.data?['error'] ?? 'Recharge failed. Please try again.');
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Recharge failed. Please try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _purchasingPlanId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final balanceAsync = ref.watch(walletBalanceProvider);
    final balance = balanceAsync.value ?? 0;
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
                crossAxisCount: MediaQuery.of(context).size.width > 800
                    ? 4
                    : (MediaQuery.of(context).size.width > 600 ? 3 : 2),
                crossAxisSpacing: AppSpacing.space16,
                mainAxisSpacing: AppSpacing.space16,
                childAspectRatio: 1.0,
              ),
              itemBuilder: (context, index) {
                final plan = plans[index];
                final isProcessing = _purchasingPlanId == plan.id;

                return RechargePlanCard(
                  coins: plan.coins,
                  price: plan.price,
                  originalPrice: plan.originalPrice,
                  badgeText: plan.badgeText,
                  onPurchasePressed: isProcessing ? null : () => _handlePurchase(plan),
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
