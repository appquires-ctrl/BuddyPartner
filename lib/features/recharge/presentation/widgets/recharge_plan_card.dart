import 'package:flutter/material.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/features/recharge/presentation/providers/recharge_providers.dart';

/// RechargePlanCard renders a coin pack card with 1:1 pricing and bonus coins.
class RechargePlanCard extends StatelessWidget {
  final RechargePlanUiModel plan;
  final bool isSelected;
  final VoidCallback onTap;

  const RechargePlanCard({
    super.key,
    required this.plan,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? const Color(0xFF24201A) : const Color(0xFFFFFDF5))
              : (isDark ? const Color(0xFF1E1A2E) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF59E0B)
                : (isDark ? Colors.white12 : const Color(0xFFECEBF3)),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
              blurRadius: isSelected ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. Unified Coin Icon
                  const AppCoinIcon(size: 40, withGlow: true),

                  // 2. Coin Count & Bonus Details
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${plan.totalCoins}',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const Text(
                        'Coins',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      if (plan.bonusCoins > 0) ...[
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '+${plan.bonusCoins} Free',
                            style: const TextStyle(
                              color: Color(0xFF059669),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // 3. Price Pill
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      gradient: isSelected
                          ? const LinearGradient(
                              colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected
                          ? null
                          : (isDark ? Colors.white10 : const Color(0xFFF4F4F6)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '₹${plan.price.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white : const Color(0xFF18181B)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Top Badge (e.g. POPULAR, 10% EXTRA, BEST VALUE)
            if (plan.badgeText != null)
              Positioned(
                top: -8,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: plan.isPopular
                          ? [const Color(0xFFEF4444), const Color(0xFFF97316)]
                          : [const Color(0xFFF59E0B), const Color(0xFFD97706)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: (plan.isPopular ? const Color(0xFFEF4444) : const Color(0xFFF59E0B))
                            .withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    plan.badgeText!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),

            // Selection Checkmark Dot
            if (isSelected)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 13,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
