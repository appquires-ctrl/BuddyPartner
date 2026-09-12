import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:buddypartner/features/chat/application/presence_provider.dart';

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
  late bool _isFavorite;
  double _heartScale = 1.0;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.user.isFavorite;
  }

  @override
  void didUpdateWidget(covariant FavoriteUserCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.isFavorite != widget.user.isFavorite) {
      _isFavorite = widget.user.isFavorite;
    }
  }

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
        'gender': widget.user.gender,
      },
    );
  }

  void _toggleFavorite() {
    HapticFeedback.lightImpact();
    setState(() {
      _isFavorite = !_isFavorite;
      _heartScale = 1.35;
    });

    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted) {
        setState(() => _heartScale = 1.0);
      }
    });

    ref.read(favoritesNotifierProvider.notifier).toggleFavorite(
          widget.user.id,
          _isFavorite,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final initials = getInitials(widget.user.fullName);
    final Color glassBg = colors.cardBackground;
    final Color glassBorder = colors.cardBorder;
    final Color cardShadow = colors.cardShadow;
    final isOnline = ref.watch(presenceProvider)[widget.user.id] ?? widget.user.isOnline;

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
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar with Status
                GradientAvatar(
                  initials: initials,
                  avatarSeed: widget.user.avatarSeed,
                  avatarStyle: widget.user.avatarStyle,
                  gender: widget.user.gender,
                  radius: 28,
                  showStatus: true,
                  isOnline: isOnline,
                  statusIndicatorSize: 14,
                ),
                const SizedBox(width: 14),

                // Name & Gender/Details
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.user.fullName,
                              style: typography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.user.userName != null && widget.user.userName!.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Text(
                              '@${widget.user.userName!}',
                              style: typography.bodySmall.copyWith(
                                color: colors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: isOnline ? colors.success : colors.textSecondary.withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: typography.bodySmall.copyWith(
                              color: isOnline ? colors.success : colors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.user.gender != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '•',
                              style: TextStyle(
                                color: colors.textSecondary.withValues(alpha: 0.5),
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.user.gender!,
                              style: typography.bodySmall.copyWith(
                                color: colors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ],
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

                    // Favorite Heart toggle (Instant 0ms update + micro bounce animation)
                    _ActionButton(
                      icon: _isFavorite ? Icons.favorite : Icons.favorite_border_rounded,
                      color: const Color(0xFFFF4E64),
                      scale: _heartScale,
                      onTap: _toggleFavorite,
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
  final double scale;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: AppThrottler.wrap(onTap),
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
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
      ),
    );
  }
}
