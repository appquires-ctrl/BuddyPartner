import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/features/home/presentation/providers/matched_users_provider.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart'; // for getInitials
import 'package:dating_app/features/chat/data/chat_repository.dart';

class MatchedUserCard extends ConsumerWidget {
  final MatchedUser user;
  final bool isGrid;

  const MatchedUserCard({
    super.key,
    required this.user,
    this.isGrid = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final initials = getInitials(user.fullName);

    final avatarSize = isGrid ? 48.0 : 56.0;

    return Container(
      width: isGrid ? null : 150,
      margin: isGrid ? EdgeInsets.zero : const EdgeInsets.only(right: 16, bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.textPrimary.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar with initials
            Container(
              width: avatarSize,
              height: avatarSize,
              decoration: const BoxDecoration(
                color: Color(0xFFE5DFFF), // Light lavender
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: TextStyle(
                  color: const Color(0xFF6B4EFF),
                  fontSize: isGrid ? 16 : 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            // Name
            Text(
              user.fullName,
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
                    color: user.isOnline ? colors.success : colors.textSecondary.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  user.isOnline ? 'Online' : 'Offline',
                  style: typography.bodySmall.copyWith(
                    color: user.isOnline ? colors.success : colors.textSecondary,
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
                  icon: Icons.chat_bubble_outline_rounded,
                  color: colors.primary,
                  onTap: () async {
                    try {
                      final repo = ref.read(chatRepositoryProvider);
                      final conv = await repo.findOrCreateConversation(user.id);
                      if (context.mounted) {
                        context.push(
                          RouteNames.chat,
                          extra: {
                            'conversationId': conv.id,
                            'userId': user.id,
                            'userName': user.fullName,
                          },
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to open chat: $e')),
                        );
                      }
                    }
                  },
                ),
                // Call Button
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
                // Favorite Button
                _ActionButton(
                  icon: user.isFavorite ? Icons.favorite : Icons.favorite_border_rounded,
                  color: const Color(0xFFFF4E64),
                  onTap: () {
                    ref.read(favoritesNotifierProvider.notifier).toggleFavorite(user.id, user.isFavorite);
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
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color,
          size: 14,
        ),
      ),
    );
  }
}
