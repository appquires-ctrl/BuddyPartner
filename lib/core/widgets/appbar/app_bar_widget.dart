import 'package:flutter/material.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/widgets/app_avatar.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_badge.dart';

/// AppBarWidget provides the custom greeting top bar of the application.
/// Displays the profile avatar, welcome text, and top-right coin balance pill.
class AppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  final String greeting;
  final String subtitle;
  final String avatarUrl;
  final String? avatarSeed;
  final String? gender;
  final int coins;
  final VoidCallback? onCoinsPressed;
  final VoidCallback? onAvatarPressed;

  const AppBarWidget({
    super.key,
    required this.greeting,
    required this.subtitle,
    required this.avatarUrl,
    this.avatarSeed,
    this.gender,
    required this.coins,
    this.onCoinsPressed,
    this.onAvatarPressed,
  });

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space16,
          vertical: AppSpacing.space8,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left Side: Avatar + Greeting Header
            Expanded(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onAvatarPressed,
                    child: AppAvatar(
                      avatarSeed: avatarSeed,
                      gender: gender,
                      initials: greeting.isNotEmpty ? greeting[0] : 'U',
                      radius: 22,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          greeting,
                          overflow: TextOverflow.ellipsis,
                          style: typography.headlineGreeting.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          subtitle,
                          overflow: TextOverflow.ellipsis,
                          style: typography.bodySmall.copyWith(
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Right Side: Unified Coin Balance Chip
            AppCoinBadge(
              coins: coins,
              variant: AppCoinBadgeVariant.pill,
              iconSize: 18,
              fontSize: 13.5,
              onTap: onCoinsPressed,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64.0);
}
