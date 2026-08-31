import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/services/apptrove_service.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/buttons/app_primary_button.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

class DevRechargePage extends ConsumerStatefulWidget {
  final int coins;
  final int price;

  const DevRechargePage({
    super.key,
    required this.coins,
    required this.price,
  });

  @override
  ConsumerState<DevRechargePage> createState() => _DevRechargePageState();
}

class _DevRechargePageState extends ConsumerState<DevRechargePage> {
  bool _isProcessing = false;

  Future<void> _handleCompleteRecharge([int? customCoins, int? customPrice]) async {
    final coinsToCredit = customCoins ?? widget.coins;
    final priceToPay = customPrice ?? widget.price;

    AppLogger.button(
      'Dev Complete Recharge: $coinsToCredit Coins (₹$priceToPay)',
      screen: 'DevRechargePage',
    );
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    try {
      final apiClient = ref.read(apiClientProvider);
      final refId = 'dev_recharge_${DateTime.now().millisecondsSinceEpoch}';

      final response = await apiClient.dio.post(
        '/api/wallet/recharge',
        data: {
          'amount': coinsToCredit,
          'paymentReference': refId,
        },
      );

      if (!mounted) return;
      setState(() => _isProcessing = false);

      if (response.data != null && response.data['success'] == true) {
        ref.invalidate(walletBalanceProvider);

        // Track Coin Recharge event in AppTrove
        AppTroveService.trackCoinRecharge(
          coins: coinsToCredit,
          priceRupees: priceToPay.toDouble(),
          orderId: response.data['transactionId']?.toString() ?? refId,
          planId: 'COIN_PACK_$coinsToCredit',
        );

        AppSnackBar.showSuccess(
          context,
          'DEV MODE: Successfully credited $coinsToCredit Coins (₹$priceToPay)!',
        );
        context.go(RouteNames.home);
      } else {
        AppSnackBar.showError(
          context,
          response.data?['error'] ?? 'Dev recharge failed on server.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        String msg = e.toString();
        if (e is DioException) {
          msg = e.response?.data?['error']?.toString() ?? e.message ?? 'Server error';
        }
        AppSnackBar.showError(context, 'Recharge failed: $msg');
      }
    }
  }

  void _handleSimulateFailure() {
    AppLogger.button('Simulate Failed Recharge Payment', screen: 'DevRechargePage');
    HapticFeedback.heavyImpact();
    AppSnackBar.showError(
      context,
      'DEV SIMULATION: Payment cancelled or failed by user. No coins credited.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final walletAsync = ref.watch(walletBalanceProvider);
    final currentBalance = walletAsync.valueOrNull ?? 0;

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'Dev Checkout',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Coin recharge payment simulator',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          children: [
            // Prominent DEV MODE Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.space16),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade700, width: 2),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade400, size: 28),
                      const SizedBox(width: AppSpacing.space8),
                      Text(
                        'DEV TESTING MODE',
                        style: typography.bodyMedium.copyWith(
                          color: Colors.amber.shade400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space8),
                  Text(
                    'Real payment gateway is simulated. Use the actions below to simulate coin purchase or test failure responses.',
                    textAlign: TextAlign.center,
                    style: typography.bodySmall.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space20),

            // Coin Pack Summary Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.space20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Selected Pack',
                        style: typography.bodyMedium.copyWith(
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '1 INR = 1 Coin',
                          style: typography.bodySmall.copyWith(
                            color: const Color(0xFFD97706),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space16),
                  Row(
                    children: [
                      const AppCoinIcon(size: 40),
                      const SizedBox(width: AppSpacing.space12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${widget.coins} Coins',
                              style: typography.titleCard.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              'Instant credit to wallet',
                              style: typography.bodySmall.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${widget.price}',
                        style: TextStyle(
                          color: colors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Current Wallet Balance',
                        style: typography.bodySmall.copyWith(color: colors.textSecondary),
                      ),
                      Row(
                        children: [
                          const AppCoinIcon(size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '$currentBalance Coins',
                            style: typography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Balance After Recharge',
                        style: typography.bodySmall.copyWith(
                          color: colors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Row(
                        children: [
                          const AppCoinIcon(size: 16),
                          const SizedBox(width: 4),
                          Text(
                            '${currentBalance + widget.coins} Coins',
                            style: typography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.success,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space24),

            // Action 1: Complete Payment (Success)
            AppPrimaryButton(
              text: 'Complete Payment & Add ${widget.coins} Coins',
              isLoading: _isProcessing,
              onPressed: _isProcessing ? null : () => _handleCompleteRecharge(),
            ),
            const SizedBox(height: AppSpacing.space12),

            // Action 2: Simulate Payment Failure
            OutlinedButton(
              onPressed: _isProcessing ? null : _handleSimulateFailure,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.danger,
                minimumSize: const Size(double.infinity, 50),
                side: BorderSide(color: colors.danger.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.close_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Simulate Failed Payment',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
