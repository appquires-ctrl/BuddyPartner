import 'package:flutter/material.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';

/// WalletCard renders a premium credit-card style balance summary card.
/// Features a dark, rich gradient, gold accents, and coin representations.
class WalletCard extends StatelessWidget {
  final int balance;
  final VoidCallback? onRechargePressed;

  const WalletCard({
    super.key,
    required this.balance,
    this.onRechargePressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.space16),
      decoration: BoxDecoration(
        borderRadius: AppRadius.lg,
        gradient: LinearGradient(
          colors: colors.walletCardBg,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: Stack(
        children: [
          // Background soft glow shape decoration
          Positioned(
            right: -20,
            bottom: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Available Balance',
                    style: typography.bodySmall.copyWith(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const AppCoinIcon(size: 28, withGlow: true),
                ],
              ),
              // const SizedBox(height: AppSpacing.space8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$balance',
                    style: typography.displayWordmark.copyWith(
                      color: Colors.white,
                      fontSize: 40,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Coins',
                    style: typography.titleCard.copyWith(
                      color: colors.primaryGradientEnd,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              // const SizedBox(height: AppSpacing.space20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Wallet',
                    style: typography.bodySmall.copyWith(
                      color: Colors.white38,
                      fontSize: 15,
                      letterSpacing: 1.0,
                    ),
                  ),
                  if (onRechargePressed != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.primaryGradientEnd,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onRechargePressed,
                      child: Row(
                        children: [
                          Text(
                            'Top Up',
                            style: typography.labelPill.copyWith(
                              color: colors.primaryGradientEnd,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 12,
                            color: colors.primaryGradientEnd,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
