import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/widgets/feedback/app_empty_state.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';
import 'package:buddypartner/features/wallet/application/wallet_transaction_providers.dart';
import 'package:buddypartner/features/wallet/domain/wallet_transaction.dart';

/// Clean and simple Wallet History Page matching Subscription History layout.
class WalletHistoryPage extends ConsumerWidget {
  const WalletHistoryPage({super.key});

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthStr = months[dt.month - 1];
    return '${dt.day} $monthStr ${dt.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final transactionsAsync = ref.watch(walletTransactionsProvider);

    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/app_bg.jpg',
          fit: BoxFit.cover,
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: colors.textPrimary),
              onPressed: () => context.pop(),
            ),
            centerTitle: true,
            title: Column(
              children: [
                Text(
                  'Wallet History',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'View your coin transactions',
                  style: typography.bodySmall.copyWith(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          body: transactionsAsync.when(
            loading: () => Center(
              child: AppLoadingIndicator(color: colors.primary),
            ),
            error: (err, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48, color: colors.danger),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load wallet history',
                      style: typography.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        ref.invalidate(walletTransactionsProvider);
                        ref.invalidate(walletBalanceProvider);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            data: (transactions) {
              if (transactions.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(walletTransactionsProvider);
                    ref.invalidate(walletBalanceProvider);
                    await ref.read(walletTransactionsProvider.future).catchError((_) => <WalletTransaction>[]);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      AppEmptyState(
                        title: 'No Coin Transactions',
                        description: 'Your coin recharges and spends will appear here.',
                        icon: Icons.account_balance_wallet_rounded,
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: ElevatedButton.icon(
                          onPressed: () => context.push(RouteNames.recharge),
                          icon: const Icon(Icons.add_rounded, color: Colors.white),
                          label: const Text('Recharge Coins'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6B4EFF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(walletTransactionsProvider);
                  ref.invalidate(walletBalanceProvider);
                  await ref.read(walletTransactionsProvider.future).catchError((_) => <WalletTransaction>[]);
                },
                child: ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.space16),
                  itemCount: transactions.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final tx = transactions[index];
                    final isCredit = tx.type.toLowerCase() == 'credit';
                    final isRefund = tx.reasonLabel.toLowerCase().contains('refund');
                    final badgeText = isRefund
                        ? 'REFUND'
                        : (isCredit ? 'ADDED' : 'SPENT');

                    final statusBg = isCredit
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFF7C6AEF).withValues(alpha: 0.12);
                    final statusColor = isCredit ? const Color(0xFF10B981) : const Color(0xFF7C6AEF);

                    final badgeBg = isCredit
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : const Color(0xFF7C6AEF).withValues(alpha: 0.12);
                    final badgeColor = isCredit ? const Color(0xFF10B981) : const Color(0xFF7C6AEF);
                    final icon = isCredit ? Icons.call_received_rounded : Icons.call_made_rounded;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: AppRadius.lg,
                        border: Border.all(
                          color: colors.border.withValues(alpha: 0.6),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: badgeBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              icon,
                              color: badgeColor,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tx.reasonLabel,
                                  style: typography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colors.textPrimary,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: statusBg,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        badgeText,
                                        style: TextStyle(
                                          color: statusColor,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatRelativeTime(tx.createdAt),
                                      style: typography.bodySmall.copyWith(
                                        color: colors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isCredit ? '+${tx.amount}' : '-${tx.amount}',
                                style: typography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: isCredit ? const Color(0xFF10B981) : colors.textPrimary,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Image.asset(
                                'assets/images/coin.png',
                                width: 15,
                                height: 15,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.monetization_on_rounded,
                                  color: Color(0xFFFFD700),
                                  size: 15,
                                ),
                              ),
                              const SizedBox(width: 3),
                              const Text(
                                'Coins',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8E8B9E),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
