import 'package:flutter/material.dart';
import 'package:dating_app/core/widgets/shimmer/app_shimmer.dart';
import 'package:dating_app/app/theme/skeleton_colors.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';

/// WalletCardSkeleton displays a hero card skeleton matching
/// the WalletCard balance hero layout on the Recharge store screen.
class WalletCardSkeleton extends StatelessWidget {
  const WalletCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blockColor = SkeletonColors.baseColor(isDark);
    final cardBg = isDark ? colors.surface.withValues(alpha: 0.5) : colors.surface;

    return Container(
      height: 140,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border.withValues(alpha: 0.4)),
      ),
      child: AppShimmer(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 100,
                    height: 12,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 140,
                    height: 28,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: blockColor,
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
