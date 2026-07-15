import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/app/theme/app_spacing.dart';

/// AppBarWidget provides the custom greeting top bar of the application.
/// Displays the profile avatar, welcome text, and top-right coin balance pill.
class AppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  final String greeting;
  final String subtitle;
  final String avatarUrl;
  final int coins;
  final VoidCallback? onCoinsPressed;
  final VoidCallback? onAvatarPressed;

  const AppBarWidget({
    super.key,
    required this.greeting,
    required this.subtitle,
    required this.avatarUrl,
    required this.coins,
    this.onCoinsPressed,
    this.onAvatarPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
            Row(
              children: [
                GestureDetector(
                  onTap: onAvatarPressed,
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: colors.primary,
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty
                        ? Text(
                            greeting.isNotEmpty ? greeting[0].toUpperCase() : 'U',
                            style: typography.labelPill.copyWith(color: colors.surface),
                          )
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpacing.space12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      greeting,
                      style: typography.headlineGreeting.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: typography.bodySmall.copyWith(
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            // Right Side: Coin Balance Chip
            InkWell(
              onTap: onCoinsPressed,
              borderRadius: AppRadius.pill,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space12,
                  vertical: AppSpacing.space4,
                ),
                decoration: BoxDecoration(
                  color: colors.chipLavender,
                  borderRadius: AppRadius.pill,
                  border: Border.all(color: colors.primary.withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      color: Color(0xFFF2A93B), // warningAmber Gold Color
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$coins',
                      style: typography.labelPill.copyWith(
                        color: colors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(64.0);
}
