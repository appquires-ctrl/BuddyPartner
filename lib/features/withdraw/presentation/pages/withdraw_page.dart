import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/widgets/buttons/app_primary_button.dart';
import 'package:buddypartner/core/widgets/cards/app_card.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/features/withdraw/application/rose_providers.dart';
import 'package:buddypartner/features/withdraw/application/withdraw_controller.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';

class WithdrawPage extends ConsumerStatefulWidget {
  const WithdrawPage({super.key});

  @override
  ConsumerState<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends ConsumerState<WithdrawPage> {
  final _amountController = TextEditingController();
  int _enteredCoins = 0;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() {
      final text = _amountController.text;
      final parsed = int.tryParse(text) ?? 0;
      if (parsed != _enteredCoins) {
        setState(() {
          _enteredCoins = parsed;
        });
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submitWithdrawal(int maxCoins) {
    AppLogger.button('Submit Withdrawal Request', screen: 'WithdrawPage');
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      AppSnackBar.showError(context, 'Please enter a valid amount of coins to withdraw.');
      return;
    }

    if (amount > maxCoins) {
      AppSnackBar.showError(context, 'You cannot withdraw more than your balance of $maxCoins coins.');
      return;
    }

    ref.read(withdrawControllerProvider.notifier).requestWithdrawal(amount).then((success) {
      if (success && mounted) {
        _amountController.clear();
        AppSnackBar.showSuccess(context, 'Withdrawal request submitted successfully!');
      }
    });
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = (dt.hour % 12 == 0 ? 12 : dt.hour % 12).toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $year • $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final historyAsync = ref.watch(withdrawalHistoryProvider);
    final withdrawState = ref.watch(withdrawControllerProvider);
    final walletBalance = ref.watch(walletBalanceProvider).value ?? 0;
    final instantState = ref.watch(instantConnectControllerProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: context.canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                onPressed: () => context.pop(),
              )
            : null,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'Earnings & Withdraw',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Manage your payouts & earnings',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 8.0, bottom: 120.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Coin / Earnings Balance Card
            AppCard(
              padding: const EdgeInsets.all(20),
              backgroundColor: colors.primary.withValues(alpha: 0.08),
              border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        '💰',
                        style: TextStyle(fontSize: 32.0),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$walletBalance',
                        style: typography.titleCard.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                          fontSize: 36,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Coins',
                        style: typography.bodyMedium.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Available Earnings Balance (≈ ₹$walletBalance)',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      '1 Coin = ₹1.00 INR (Direct UPI / Bank Payout)',
                      style: typography.labelPill.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scratch Card Earnings summary
            if (instantState.femaleStatus.totalScratchedCoins > 0 || instantState.femaleStatus.unscratchedCount > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFD54F)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.card_giftcard_rounded, color: Color(0xFFD97706), size: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Instant Connect Scratch Cards', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(
                            'Earned ${instantState.femaleStatus.totalScratchedCoins} Coins from ${instantState.femaleStatus.totalScratchedCards} Scratch Cards',
                            style: const TextStyle(color: Colors.black54, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),

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
            const SizedBox(height: 16),

            // Request Withdrawal Form
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Request Withdrawal',
                    style: typography.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter the amount of coins you wish to convert to rupees (₹).',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Coins to Withdraw',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text('🪙', style: TextStyle(fontSize: 20)),
                      ),
                      suffixText: 'Coins',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Dynamic Live Rupee Conversion Display
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Estimated Payout:',
                          style: typography.bodySmall.copyWith(color: colors.textSecondary),
                        ),
                        Text(
                          '₹$_enteredCoins.00',
                          style: typography.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (withdrawState.errorMessage != null) ...[
                    Text(
                      withdrawState.errorMessage!,
                      style: typography.bodySmall.copyWith(color: Colors.red),
                    ),
                    const SizedBox(height: 12),
                  ],

                  AppPrimaryButton(
                    text: 'Request Withdrawal',
                    isLoading: withdrawState.isLoading,
                    onPressed: () => _submitWithdrawal(walletBalance),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Withdrawal History Title
            Text(
              'Past Withdrawal Requests',
              style: typography.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            historyAsync.when(
              loading: () => const Center(child: AppLoadingIndicator()),
              error: (err, _) => Text(
                'Failed to load history: $err',
                style: typography.bodySmall.copyWith(color: Colors.red),
              ),
              data: (history) {
                if (history.isEmpty) {
                  return AppCard(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(
                        'No past withdrawal requests yet.',
                        style: typography.bodySmall.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: history.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = history[index];
                    return _buildWithdrawalTile(context, item);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWithdrawalTile(BuildContext context, WithdrawalRequest item) {
    final colors = context.colors;
    final typography = context.typography;

    final dateStr = _formatDate(item.requestedAt);

    Color badgeColor;
    String statusText = item.status.toUpperCase();

    switch (item.status.toLowerCase()) {
      case 'pending':
        badgeColor = Colors.orange;
        break;
      case 'approved':
      case 'paid':
        badgeColor = Colors.green;
        break;
      case 'rejected':
        badgeColor = Colors.red;
        break;
      default:
        badgeColor = colors.textSecondary;
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Text('🪙', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.coinAmount} Coins  →  ₹${item.rupeeAmount}',
                  style: typography.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dateStr,
                  style: typography.bodySmall.copyWith(
                    color: colors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: typography.labelPill.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
