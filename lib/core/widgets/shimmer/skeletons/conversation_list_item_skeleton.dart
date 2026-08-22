import 'package:flutter/material.dart';
import 'package:buddypartner/app/theme/skeleton_colors.dart';
import 'package:buddypartner/core/widgets/shimmer/app_shimmer.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';

/// ConversationListItemSkeleton provides a high-fidelity, component-level
/// skeleton loader matching the exact layout, dimensions, and typography
/// of the real Conversation card in Messages screen.
class ConversationListItemSkeleton extends StatelessWidget {
  final int itemIndex;

  const ConversationListItemSkeleton({
    super.key,
    this.itemIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Soft lavender-tinted skeleton colors matching design system
    final blockColor = SkeletonColors.baseColor(isDark);
    final secondaryBlockColor = blockColor.withValues(alpha: 0.65);
    final cardBg = isDark
        ? colors.surface.withValues(alpha: 0.6)
        : Colors.white;
    final borderColor = isDark
        ? colors.border.withValues(alpha: 0.3)
        : colors.border.withValues(alpha: 0.6);

    // Dynamic width presets per item index for a realistic, varied conversation list preview
    final double nameWidth;
    final double previewWidth;
    final double timeWidth;
    final bool showBadge;

    switch (itemIndex % 5) {
      case 0:
        nameWidth = 130;
        previewWidth = 175;
        timeWidth = 38;
        showBadge = true;
        break;
      case 1:
        nameWidth = 105;
        previewWidth = 140;
        timeWidth = 44;
        showBadge = false;
        break;
      case 2:
        nameWidth = 140;
        previewWidth = 165;
        timeWidth = 34;
        showBadge = true;
        break;
      case 3:
        nameWidth = 115;
        previewWidth = 190;
        timeWidth = 40;
        showBadge = false;
        break;
      case 4:
      default:
        nameWidth = 125;
        previewWidth = 150;
        timeWidth = 36;
        showBadge = false;
        break;
    }

    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: colors.textPrimary.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: AppShimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          child: Row(
            children: [
              // 1. Circular Avatar Skeleton (52px diameter) with status dot placeholder
              Stack(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: blockColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isDark ? colors.surface : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(2),
                      child: Container(
                        decoration: BoxDecoration(
                          color: blockColor.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),

              // 2. Name & Message Preview Skeleton Column
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User name skeleton bar
                    Container(
                      width: nameWidth,
                      height: 14,
                      decoration: BoxDecoration(
                        color: blockColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Last message preview skeleton bar
                    Container(
                      width: previewWidth,
                      height: 11,
                      decoration: BoxDecoration(
                        color: secondaryBlockColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // 3. Right Date/Time & Unread Badge Skeleton Column
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Time/date skeleton placeholder on right
                  Container(
                    width: timeWidth,
                    height: 10,
                    decoration: BoxDecoration(
                      color: secondaryBlockColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Unread badge indicator placeholder
                  if (showBadge)
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: blockColor,
                        shape: BoxShape.circle,
                      ),
                    )
                  else
                    const SizedBox(height: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
