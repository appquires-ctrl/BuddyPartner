import 'package:flutter/material.dart';
import 'package:buddypartner/core/widgets/shimmer/app_shimmer.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/app/theme/skeleton_colors.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';

/// RechargePlanSkeleton renders a loading layout skeleton
/// matching the RechargePlanCard visual layout block.
class RechargePlanSkeleton extends StatelessWidget {
  const RechargePlanSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? colors.surface.withValues(alpha: 0.5) : colors.surface;
    final blockColor = SkeletonColors.baseColor(isDark);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: colors.border.withValues(alpha: 0.4)),
      ),
      child: AppShimmer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Coin icon & title skeleton
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: blockColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 50,
                  height: 16,
                  decoration: BoxDecoration(
                    color: blockColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),

            // Price button skeleton
            Container(
              width: 80,
              height: 32,
              decoration: BoxDecoration(
                color: blockColor,
                borderRadius: AppRadius.pill,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
