import 'package:flutter/material.dart';
import 'package:buddypartner/core/widgets/shimmer/app_shimmer.dart';

/// AppCoinBalanceCard provides a state-of-the-art Dual-Balance Wallet Card
/// reflecting the user's Total Balance, with distinct Spendable (Recharges/Promo)
/// and Earned (Withdrawable) sub-accounts, and a direct "+ Add Coins" action.
class AppCoinBalanceCard extends StatelessWidget {
  final int? balance;
  final int? totalBalance;
  final int spendableBalance;
  final int earnedBalance;
  final String title;
  final bool showAddCoinsButton;
  final VoidCallback? onAddCoinsPressed;
  final VoidCallback? onTopUpPressed;
  final VoidCallback? onHistoryPressed;
  final VoidCallback? onEarnedPressed;
  final bool isLoading;
  final int? activeTabIndex;

  const AppCoinBalanceCard({
    super.key,
    this.balance,
    this.totalBalance,
    this.spendableBalance = 0,
    this.earnedBalance = 0,
    this.title = 'TOTAL BALANCE',
    this.showAddCoinsButton = false,
    this.onAddCoinsPressed,
    this.onTopUpPressed,
    this.onHistoryPressed,
    this.onEarnedPressed,
    this.isLoading = false,
    this.activeTabIndex,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTotal = totalBalance ?? balance ?? (spendableBalance + earnedBalance);
    final effectiveSpendable = (spendableBalance > 0 || earnedBalance > 0)
        ? spendableBalance
        : effectiveTotal;
    final effectiveEarned = earnedBalance;

    final onAddAction = onAddCoinsPressed ?? onTopUpPressed;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E1A34),
            Color(0xFF131022),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFF2C2746),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D0B18).withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top Header Row: Title / Amount & + Add Coins Button ─────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Left Column: "TOTAL BALANCE" + 850 Coins
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFA59EC8),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: isLoading
                          ? Padding(
                              key: const ValueKey('total_balance_loading'),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  AppShimmer(
                                    baseColor: Colors.white.withValues(alpha: 0.12),
                                    highlightColor: Colors.white.withValues(alpha: 0.30),
                                    child: Container(
                                      width: 96,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  AppShimmer(
                                    baseColor: Colors.white.withValues(alpha: 0.12),
                                    highlightColor: Colors.white.withValues(alpha: 0.30),
                                    child: Container(
                                      width: 44,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : Row(
                              key: ValueKey('coin_balance_$effectiveTotal'),
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$effectiveTotal',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Text(
                                  'Coins',
                                  style: TextStyle(
                                    color: Color(0xFFA59EC8),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),

              // Right Button: "+ Add Coins" (optional, hidden by default on Coin Store)
              if (showAddCoinsButton && onAddAction != null)
                GestureDetector(
                  onTap: onAddAction,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF7C5DF9),
                          Color(0xFF6347EA),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6E4BF5).withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '+ Add Coins',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),

          // ── Subtle Divider ──────────────────────────────────────────────
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          const SizedBox(height: 12),

          // ── Bottom Row: Spendable & Earned Sub-Cards ─────────────────────
          Row(
            children: [
              // 1. Spendable Sub-Card
              Expanded(
                child: GestureDetector(
                  onTap: onAddAction,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF231F38),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: activeTabIndex == 0
                            ? const Color(0xFFFBBF24)
                            : Colors.white.withValues(alpha: 0.08),
                        width: activeTabIndex == 0 ? 1.5 : 1,
                      ),
                      boxShadow: activeTabIndex == 0
                          ? [
                              BoxShadow(
                                color: const Color(0xFFFBBF24).withValues(alpha: 0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.shopping_bag_outlined,
                              size: 13,
                              color: Color(0xFFFBBF24),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Spendable',
                              style: TextStyle(
                                color: Color(0xFFFBBF24),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (activeTabIndex == 0)
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFBBF24),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        isLoading
                            ? AppShimmer(
                                baseColor: Colors.white.withValues(alpha: 0.12),
                                highlightColor: Colors.white.withValues(alpha: 0.30),
                                child: Container(
                                  width: 50,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              )
                            : Text(
                                '$effectiveSpendable',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                        const SizedBox(height: 2),
                        const Text(
                          'Recharges',
                          style: TextStyle(
                            color: Color(0xFFA59EC8),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 10),

              // 2. Earned (Withdrawable) Sub-Card
              Expanded(
                child: GestureDetector(
                  onTap: onEarnedPressed,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF142426),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: activeTabIndex == 1
                            ? const Color(0xFF10B981)
                            : const Color(0xFF10B981).withValues(alpha: 0.35),
                        width: activeTabIndex == 1 ? 1.5 : 1,
                      ),
                      boxShadow: activeTabIndex == 1
                          ? [
                              BoxShadow(
                                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.savings_outlined,
                              size: 13,
                              color: Color(0xFF34D399),
                            ),
                            const SizedBox(width: 5),
                            const Text(
                              'Earned',
                              style: TextStyle(
                                color: Color(0xFF34D399),
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            if (activeTabIndex == 1)
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34D399),
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        isLoading
                            ? AppShimmer(
                                baseColor: Colors.white.withValues(alpha: 0.12),
                                highlightColor: Colors.white.withValues(alpha: 0.30),
                                child: Container(
                                  width: 50,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              )
                            : Text(
                                '$effectiveEarned',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                        const SizedBox(height: 2),
                        const Text(
                          'Withdrawable',
                          style: TextStyle(
                            color: Color(0xFF34D399),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
