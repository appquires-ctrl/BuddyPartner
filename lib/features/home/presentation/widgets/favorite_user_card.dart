import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/home/presentation/providers/matched_users_provider.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/core/utils/app_throttler.dart';

class FavoriteUserCard extends ConsumerStatefulWidget {
  final MatchedUser user;

  const FavoriteUserCard({
    super.key,
    required this.user,
  });

  @override
  ConsumerState<FavoriteUserCard> createState() => _FavoriteUserCardState();
}

class _FavoriteUserCardState extends ConsumerState<FavoriteUserCard> {
  void _handleOpenChat() {
    if (!AppThrottler.canProcess(actionId: 'open_chat_${widget.user.id}')) return;
    context.push(
      RouteNames.chat,
      extra: {
        'conversationId': 'user:${widget.user.id}',
        'userId': widget.user.id,
        'userName': widget.user.fullName,
        'avatarSeed': widget.user.avatarSeed,
        'avatarStyle': widget.user.avatarStyle,
        'userAvatar': widget.user.avatarUrl,
        'gender': widget.user.gender,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final initials = getInitials(widget.user.fullName);
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
                GradientAvatar(
                  initials: initials,
                  avatarSeed: widget.user.avatarSeed,
                  avatarStyle: widget.user.avatarStyle,
                  gender: widget.user.gender,
                  radius: 26,
                  showStatus: true,
                  isOnline: widget.user.isOnline,
                  statusIndicatorSize: 14,
                ),
                const SizedBox(width: 14),

                // Name & status details column (Expanded)
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.user.fullName,
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
                              color: widget.user.isOnline ? colors.success : colors.textSecondary.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.user.isOnline ? 'Online' : 'Offline',
                            style: typography.bodySmall.copyWith(
                              color: widget.user.isOnline ? colors.success : colors.textSecondary,
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
                      icon: Icons.chat,
                      color: colors.primary,
                      onTap: _handleOpenChat,
                    ),
                    const SizedBox(width: 8),

                    // Call Action
                    _ActionButton(
                      icon: Icons.phone_forwarded_rounded,
                      color: colors.success,
                      onTap: () {
                        final currentState = ref.read(matchmakingControllerProvider);
                        if (currentState.phase != MatchmakingPhase.idle) return;

                        ref.read(matchmakingControllerProvider.notifier).callUser(
                          targetUserId: widget.user.id,
                          targetUserName: widget.user.fullName,
                        );
                      },
                    ),
                    const SizedBox(width: 8),

                    // Unfavorite Heart toggle
                    _ActionButton(
                      icon: Icons.favorite,
                      color: const Color(0xFFFF4E64), // Solid pink/red heart
                      onTap: () {
                        ref.read(favoritesNotifierProvider.notifier).toggleFavorite(widget.user.id, widget.user.isFavorite);
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
      onTap: AppThrottler.wrap(onTap),
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
