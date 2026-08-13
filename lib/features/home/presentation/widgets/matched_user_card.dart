import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/home/presentation/providers/matched_users_provider.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart'; // for getInitials
import 'package:buddypartner/core/widgets/gradient_avatar.dart';

class MatchedUserCard extends ConsumerStatefulWidget {
  final MatchedUser user;
  final bool isGrid;

  const MatchedUserCard({
    super.key,
    required this.user,
    this.isGrid = false,
  });

  @override
  ConsumerState<MatchedUserCard> createState() => _MatchedUserCardState();
}

class _MatchedUserCardState extends ConsumerState<MatchedUserCard> {
  void _handleOpenChat() {
    context.push(
      RouteNames.chat,
      extra: {
        'conversationId': 'user:${widget.user.id}',
        'userId': widget.user.id,
        'userName': widget.user.fullName,
        'avatarSeed': widget.user.avatarSeed,
        'avatarStyle': widget.user.avatarStyle,
        'gender': widget.user.gender,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final initials = getInitials(widget.user.fullName);

    final avatarSize = widget.isGrid ? 48.0 : 56.0;

    return Container(
      width: widget.isGrid ? null : 150,
      margin: widget.isGrid ? EdgeInsets.zero : const EdgeInsets.only(right: 16, bottom: 8),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: colors.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar with initials
            GradientAvatar(
              initials: initials,
              avatarSeed: widget.user.avatarSeed,
              avatarStyle: widget.user.avatarStyle,
              gender: widget.user.gender,
              radius: avatarSize / 2,
              showStatus: true,
              isOnline: widget.user.isOnline,
              statusIndicatorSize: widget.isGrid ? 14 : 16,
            ),
            const SizedBox(height: 8),
            
            // Name
            Text(
              widget.user.fullName,
              style: typography.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),

            // Online/Offline status row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.user.isOnline ? colors.success : colors.textSecondary.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.user.isOnline ? 'Online' : 'Offline',
                  style: typography.bodySmall.copyWith(
                    color: widget.user.isOnline ? colors.success : colors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Action Buttons Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Chat Button
                _ActionButton(
                  icon: Icons.chat,
                  color: colors.primary,
                  onTap: _handleOpenChat,
                ),
                // Call Button
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
                // Favorite Button
                _ActionButton(
                  icon: widget.user.isFavorite ? Icons.favorite : Icons.favorite_border_rounded,
                  color: const Color(0xFFFF4E64),
                  onTap: () {
                    ref.read(favoritesNotifierProvider.notifier).toggleFavorite(widget.user.id, widget.user.isFavorite);
                  },
                ),
              ],
            ),
          ],
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
        width: 33,
        height: 33,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color,
          size: 17,
        ),
      ),
    );
  }
}
