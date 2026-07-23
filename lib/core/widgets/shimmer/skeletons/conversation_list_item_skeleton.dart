import 'package:flutter/material.dart';
import 'package:dating_app/app/theme/skeleton_colors.dart';
import 'package:dating_app/core/widgets/shimmer/app_shimmer.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';

/// ConversationListItemSkeleton displays a high-fidelity shimmer loading card
/// matching the exact layout, height, and border radius of the Favorites cards.
class ConversationListItemSkeleton extends StatelessWidget {
  const ConversationListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final blockColor = SkeletonColors.baseColor(isDark);
    final cardBg = isDark
        ? colors.surface.withValues(alpha: 0.5)
        : colors.surface;
    final borderColor = isDark
        ? colors.border.withValues(alpha: 0.4)
        : colors.border;

    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: AppShimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              // Circular avatar skeleton (52px diameter)
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: blockColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),

              // Text details column
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120,
                      height: 14,
                      decoration: BoxDecoration(
                        color: blockColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 160,
                      height: 11,
                      decoration: BoxDecoration(
                        color: blockColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Right time and badge skeleton column
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 38,
                    height: 10,
                    decoration: BoxDecoration(
                      color: blockColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: blockColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
