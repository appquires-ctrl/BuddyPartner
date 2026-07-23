import 'package:flutter/material.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/skeleton_colors.dart';
import 'package:dating_app/core/widgets/shimmer/app_shimmer.dart';

/// FavoritesSkeleton provides a high-fidelity shimmer loading layout
/// where internal card elements (avatar, text lines, action icons) shimmer
/// inside a static card frame.
class FavoritesSkeleton extends StatelessWidget {
  const FavoritesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final blockColor = SkeletonColors.baseColor(isDark);
    final cardBg = isDark
        ? colors.surface.withValues(alpha: 0.5)
        : colors.surface;
    final borderColor = isDark
        ? colors.border.withValues(alpha: 0.4)
        : colors.border;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'Favorites',
              style: typography.titleCard.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Your saved telecallers',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppSpacing.space24),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 5,
        separatorBuilder: (context, index) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
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
                    // Avatar circle (52px)
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: blockColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Name & status skeleton details
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 110,
                            height: 14,
                            decoration: BoxDecoration(
                              color: blockColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: blockColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                width: 45,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: blockColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Action buttons row (3 action circles)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: blockColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: blockColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 36,
                          height: 36,
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
        },
      ),
    );
  }
}
