import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/core/widgets/buttons/app_primary_button.dart';
import 'package:dating_app/core/widgets/cards/app_card.dart';
import 'package:dating_app/core/widgets/feedback/app_loading_indicator.dart';
import 'package:dating_app/features/withdraw/application/rose_providers.dart';
import 'package:dating_app/features/withdraw/application/withdraw_controller.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

class WithdrawPage extends ConsumerStatefulWidget {
  const WithdrawPage({super.key});

  @override
  ConsumerState<WithdrawPage> createState() => _WithdrawPageState();
}

class _WithdrawPageState extends ConsumerState<WithdrawPage> {
  final _amountController = TextEditingController();
  int _enteredRoses = 0;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() {
      final text = _amountController.text;
      final parsed = int.tryParse(text) ?? 0;
      if (parsed != _enteredRoses) {
        setState(() {
          _enteredRoses = parsed;
        });
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _submitWithdrawal(int maxRoses) {
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount of roses to withdraw.')),
      );
      return;
    }

    if (amount > maxRoses) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You cannot withdraw more than your balance of $maxRoses roses.')),
      );
      return;
    }

    ref.read(withdrawControllerProvider.notifier).requestWithdrawal(amount).then((success) {
      if (success && mounted) {
        _amountController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Withdrawal request submitted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
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

    const currentRoses = 0;

    final currentUser = ref.watch(authStateProvider).value;
    if (currentUser != null && !currentUser.isTelecallerActive) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Withdraw Earnings'),
          centerTitle: true,
          backgroundColor: colors.surface,
          elevation: 0,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.do_not_disturb_on_outlined,
                  size: 64,
                  color: Color(0xFF8B5CF6),
                ),
                const SizedBox(height: 16),
                Text(
                  'Telecaller Mode Disabled',
                  style: typography.titleCard.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Withdrawals and rose earnings are only available when Telecaller Mode is enabled.',
                  textAlign: TextAlign.center,
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                AppPrimaryButton(
                  text: 'Go to Settings',
                  onPressed: () {
                    context.go(RouteNames.settings);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Withdraw Earnings'),
        centerTitle: true,
        backgroundColor: colors.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rose Balance Card
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
                        '🌹',
                        style: TextStyle(fontSize: 32),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$currentRoses',
                        style: typography.titleCard.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                          fontSize: 36,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current Rose Balance',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
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
                      '1 Rose = ₹1.00 (Flat 1:1 Rate)',
                      style: typography.labelPill.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                    'Enter the amount of roses you wish to convert to rupees.',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Roses to Withdraw',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text('🌹', style: TextStyle(fontSize: 20)),
                      ),
                      suffixText: 'Roses',
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
                          '₹$_enteredRoses.00',
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
                    onPressed: () => _submitWithdrawal(currentRoses),
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
            child: const Text('🌹', style: TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.roseAmount} Roses  →  ₹${item.rupeeAmount}',
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
