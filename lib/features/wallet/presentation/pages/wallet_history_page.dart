import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/widgets/feedback/app_empty_state.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
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
    final dualWalletAsync = ref.watch(dualWalletProvider);
    final walletState = dualWalletAsync.value ?? const UserWalletState();

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
                  'Spendable & Earned ledger',
                  style: typography.bodySmall.copyWith(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(walletTransactionsProvider);
              ref.invalidate(dualWalletProvider);
              ref.invalidate(walletBalanceProvider);
              await ref.read(walletTransactionsProvider.future).catchError((_) => <WalletTransaction>[]);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.space16),
              children: [
                // ── Dual Balance Summary Card ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF241E47), Color(0xFF181432)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF7C6AEF).withValues(alpha: 0.35),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C6AEF).withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'TOTAL BALANCE',
                                style: TextStyle(
                                  color: Color(0xFFB4A9FB),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Text(
                                    '${walletState.balance}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Coins',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            onPressed: () => context.push(RouteNames.recharge),
                            icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
                            label: const Text('Add Coins'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7C6AEF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 24),
                      Row(
                        children: [
                          // Spendable Bucket
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.shopping_bag_outlined, color: Color(0xFFFBBF24), size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Spendable',
                                        style: TextStyle(
                                          color: Color(0xFFFBBF24),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${walletState.spendableBalance}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Recharges',
                                    style: TextStyle(color: Colors.white54, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Earned Bucket
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: const [
                                      Icon(Icons.savings_outlined, color: Color(0xFF34D399), size: 14),
                                      SizedBox(width: 4),
                                      Text(
                                        'Earned',
                                        style: TextStyle(
                                          color: Color(0xFF34D399),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${walletState.earnedBalance}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Withdrawable',
                                    style: TextStyle(color: Color(0xFF34D399), fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── Transactions Section ───────────────────────────────────
                transactionsAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: AppLoadingIndicator(color: Color(0xFF7C6AEF)),
                    ),
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
                              ref.invalidate(dualWalletProvider);
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
                      return Column(
                        children: [
                          const SizedBox(height: 40),
                          AppEmptyState(
                            title: 'No Coin Transactions',
                            description: 'Your coin recharges, meetup rewards, and spends will appear here.',
                            icon: Icons.account_balance_wallet_rounded,
                          ),
                        ],
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: transactions.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        final isCredit = tx.type.toLowerCase() == 'credit';
                        final isRefund = tx.reasonLabel.toLowerCase().contains('refund');
                        final badgeText = isRefund
                            ? 'REFUND'
                            : (isCredit ? 'CREDIT' : 'DEBIT');

                        final statusBg = isCredit
                            ? const Color(0xFF10B981).withValues(alpha: 0.12)
                            : const Color(0xFF7C6AEF).withValues(alpha: 0.12);
                        final statusColor = isCredit ? const Color(0xFF10B981) : const Color(0xFF7C6AEF);

                        final badgeBg = isCredit
                            ? const Color(0xFF10B981).withValues(alpha: 0.12)
                            : const Color(0xFF7C6AEF).withValues(alpha: 0.12);
                        final badgeColor = isCredit ? const Color(0xFF10B981) : const Color(0xFF7C6AEF);
                        final icon = isCredit ? Icons.call_received_rounded : Icons.call_made_rounded;

                        // Build bucket delta breakdown string if available
                        String bucketDetail = '';
                        if (tx.spendableDelta != 0 && tx.earnedDelta != 0) {
                          bucketDetail = '${tx.spendableDelta.abs()}s + ${tx.earnedDelta.abs()}e';
                        } else if (tx.earnedDelta != 0) {
                          bucketDetail = '${tx.earnedDelta > 0 ? "+" : ""}${tx.earnedDelta} earned';
                        } else if (tx.spendableDelta != 0) {
                          bucketDetail = '${tx.spendableDelta > 0 ? "+" : ""}${tx.spendableDelta} spendable';
                        }

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
                                        if (bucketDetail.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Text(
                                            '($bucketDetail)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colors.textSecondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                        const SizedBox(width: 8),
                                        Text(
                                          _formatRelativeTime(tx.createdAt),
                                          style: typography.bodySmall.copyWith(
                                            color: colors.textSecondary,
                                            fontSize: 11.5,
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
                                  const AppCoinIcon(size: 14),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
