import 'package:flutter/material.dart';
import 'package:buddypartner/app/theme/skeleton_colors.dart';
import 'package:buddypartner/core/widgets/shimmer/app_shimmer.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';

/// CallHistorySkeleton provides a high-fidelity, component-level skeleton loader
/// matching the exact layout, card container, avatar, typography, and call button
/// structure of the Call History screen.
class CallHistorySkeleton extends StatelessWidget {
  final int itemIndex;

  const CallHistorySkeleton({
    super.key,
    this.itemIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Lavender/purple-tinted skeleton colors
    final blockColor = SkeletonColors.baseColor(isDark);
    final secondaryBlockColor = blockColor.withValues(alpha: 0.65);
    final cardBg = isDark ? colors.surface.withValues(alpha: 0.6) : colors.surface;
    final borderColor = isDark
        ? colors.border.withValues(alpha: 0.3)
        : colors.border.withValues(alpha: 0.5);

    // Dynamic width presets per item index for a realistic, varied call log list preview
    final double nameWidth;
    final double timeWidth;
    final double durationWidth;

    switch (itemIndex % 5) {
      case 0:
        nameWidth = 120;
        timeWidth = 65;
        durationWidth = 36;
        break;
      case 1:
        nameWidth = 100;
        timeWidth = 80;
        durationWidth = 44;
        break;
      case 2:
        nameWidth = 135;
        timeWidth = 55;
        durationWidth = 28;
        break;
      case 3:
        nameWidth = 110;
        timeWidth = 72;
        durationWidth = 40;
        break;
      case 4:
      default:
        nameWidth = 125;
        timeWidth = 60;
        durationWidth = 32;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: AppShimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 1. Circular Avatar Skeleton (48px diameter)
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: blockColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),

              // 2. Name & Date/Time Skeleton Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // User name skeleton bar
                    Container(
                      width: nameWidth,
                      height: 15,
                      decoration: BoxDecoration(
                        color: blockColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Date/Time ago skeleton bar
                    Container(
                      width: timeWidth,
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

              // 3. Call-back Button & Duration Skeleton Column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Circular call button placeholder (40x40)
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: blockColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Duration text skeleton bar
                  Container(
                    width: durationWidth,
                    height: 10,
                    decoration: BoxDecoration(
                      color: secondaryBlockColor,
                      borderRadius: BorderRadius.circular(4),
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
