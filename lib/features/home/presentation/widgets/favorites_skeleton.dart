import 'package:flutter/material.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/skeleton_colors.dart';
import 'package:buddypartner/core/widgets/shimmer/app_shimmer.dart';

/// FavoritesSkeleton provides a high-fidelity component-level shimmer loading
/// layout matching the exact layout and elements of Favorite user cards.
class FavoritesSkeleton extends StatelessWidget {
  const FavoritesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final blockColor = SkeletonColors.baseColor(isDark);
    final secondaryBlockColor = blockColor.withValues(alpha: 0.65);
    final cardBg = isDark
        ? colors.surface.withValues(alpha: 0.6)
        : colors.surface;
    final borderColor = isDark
        ? colors.border.withValues(alpha: 0.3)
        : colors.border.withValues(alpha: 0.6);

    return Scaffold(
      backgroundColor: Colors.transparent,
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
              'Your saved partners',
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
          final double nameWidth = (index % 2 == 0) ? 130 : 110;
          final double statusWidth = (index % 2 == 0) ? 55 : 45;

          return Container(
            height: 88,
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: borderColor, width: 1.2),
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
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    // Avatar circle (52px) with status dot
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

                    // Name & status skeleton details
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: nameWidth,
                            height: 14,
                            decoration: BoxDecoration(
                              color: blockColor,
                              borderRadius: BorderRadius.circular(6),
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
                                width: statusWidth,
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

                    // Action buttons row (3 action circles)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: blockColor.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: blockColor.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: blockColor.withValues(alpha: 0.7),
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
