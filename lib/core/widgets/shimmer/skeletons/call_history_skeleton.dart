import 'package:flutter/material.dart';
import 'package:dating_app/core/widgets/shimmer/app_shimmer.dart';
import 'package:dating_app/app/theme/skeleton_colors.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';

/// CallHistorySkeleton displays a list item shimmer skeleton
/// matching the CallHistoryPage log item structure.
class CallHistorySkeleton extends StatelessWidget {
  const CallHistorySkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blockColor = SkeletonColors.baseColor(isDark);
    final cardBg = isDark ? colors.surface.withValues(alpha: 0.5) : colors.surface;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.withValues(alpha: 0.4)),
      ),
      child: AppShimmer(
        child: Row(
          children: [
            // Circle avatar
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: blockColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 14),
            // Info text lines
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 130,
                    height: 14,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 90,
                    height: 11,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            // Trailing action circle
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: blockColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
