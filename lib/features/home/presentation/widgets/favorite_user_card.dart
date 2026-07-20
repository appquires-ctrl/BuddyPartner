import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/features/home/presentation/providers/matched_users_provider.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

class FavoriteUserCard extends ConsumerWidget {
  final MatchedUser user;

  const FavoriteUserCard({
    super.key,
    required this.user,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final initials = getInitials(user.fullName);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Premium Glassmorphism styling configuration
    final Color glassBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.65);
    final Color glassBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.25);
    final Color cardShadow = isDark
        ? Colors.black.withValues(alpha: 0.2)
        : colors.textPrimary.withValues(alpha: 0.05);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            color: glassBg,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: glassBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: cardShadow,
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                // Avatar with initials
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5DFFF), // Light lavender
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: Color(0xFF6B4EFF),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Name & status details column (Expanded)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName,
                        style: typography.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: user.isOnline ? colors.success : colors.textSecondary.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            user.isOnline ? 'Online' : 'Offline',
                            style: typography.bodySmall.copyWith(
                              color: user.isOnline ? colors.success : colors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Action Buttons Row (Right)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Chat Action
                    _ActionButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      color: colors.primary,
                      onTap: () {
                        context.push(
                          RouteNames.chat,
                          extra: {
                            'userId': user.id,
                            'userName': user.fullName,
                          },
                        );
                      },
                    ),
                    const SizedBox(width: 8),

                    // Call Action
                    _ActionButton(
                      icon: Icons.phone_forwarded_rounded,
                      color: colors.success,
                      onTap: () {
                        final currentState = ref.read(matchmakingControllerProvider);
                        if (currentState.phase != MatchmakingPhase.idle) return;

                        context.push(RouteNames.calling);
                        ref.read(matchmakingControllerProvider.notifier).callUser(
                          targetUserId: user.id,
                          targetUserName: user.fullName,
                        );
                      },
                    ),
                    const SizedBox(width: 8),

                    // Unfavorite Heart toggle
                    _ActionButton(
                      icon: Icons.favorite,
                      color: const Color(0xFFFF4E64), // Solid pink/red heart
                      onTap: () {
                        ref.read(favoritesNotifierProvider.notifier).toggleFavorite(user.id, user.isFavorite);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color,
          size: 19,
        ),
      ),
    );
  }
}
