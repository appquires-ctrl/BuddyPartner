import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/core/widgets/cards/app_card.dart';
import 'package:dating_app/core/widgets/chips/badge_ribbon.dart';
import 'package:dating_app/core/widgets/buttons/app_pill_button.dart';
import 'package:dating_app/app/theme/app_spacing.dart';

/// RechargePlanCard is a card rendering a coin recharge plan option.
/// Wraps AppCard, BadgeRibbon, and AppPillButton in a layout with pricing headers.
class RechargePlanCard extends StatelessWidget {
  final int coins;
  final double price;
  final double? originalPrice;
  final String? badgeText;
  final VoidCallback? onPurchasePressed;

  const RechargePlanCard({
    super.key,
    required this.coins,
    required this.price,
    this.originalPrice,
    this.badgeText,
    this.onPurchasePressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16.0), // match AppCard rounding
      clipBehavior: Clip.antiAlias,
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [
          // Outer elevated container block - forced to fill the grid cell constraints
          Positioned.fill(
            child: AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space12,
                vertical: AppSpacing.space12,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Coin representation count header
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.monetization_on,
                        color: Color(0xFFF2A93B), // Gold coin color
                        size: 24,
                      ),
                      const SizedBox(height: AppSpacing.space4),
                      Text(
                        '$coins.0',
                        style: typography.titleCard.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        'coins',
                        style: typography.bodySmall.copyWith(
                          color: colors.textSecondary,
                          fontSize: 11,
                      ),
                    ),
                  ],
                ),

                // Strikethrough pricing and Action price button
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (originalPrice != null)
                      Text(
                        '₹${originalPrice!.toStringAsFixed(0)}',
                        style: typography.bodySmall.copyWith(
                          color: colors.textSecondary.withOpacity(0.6),
                          decoration: TextDecoration.lineThrough,
                          fontSize: 10,
                        ),
                      )
                    else
                      const SizedBox(height: 14),
                    const SizedBox(height: 4),
                    AppPillButton(
                      text: '₹${price.toStringAsFixed(0)}',
                      onPressed: onPurchasePressed,
                      height: 32.0,
                    ),
                  ],
                ),
              ],
            ),
          ),
          ),
          
          // Badge Ribbon Diagonal overlay if provided
          if (badgeText != null)
            BadgeRibbon(text: badgeText!),
        ],
      ),
    );
  }
}
