import 'package:flutter/material.dart';
import 'package:buddypartner/core/widgets/app_avatar.dart';
import 'package:buddypartner/core/constants/avatar_catalog.dart';

class GradientAvatar extends StatelessWidget {
  final String initials;
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;
  final String? userAvatar;
  final double radius;
  final bool? isOnline;
  final bool showStatus;
  final double statusIndicatorSize;
  final bool showGlowRing;

  const GradientAvatar({
    super.key,
    required this.initials,
    this.avatarSeed,
    this.avatarStyle,
    this.gender,
    this.userAvatar,
    this.radius = 26,
    this.isOnline,
    this.showStatus = false,
    this.statusIndicatorSize = 14,
    this.showGlowRing = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasAvatarSeed = avatarSeed != null && avatarSeed!.trim().isNotEmpty;
    final hasUserAvatar = userAvatar != null && userAvatar!.trim().isNotEmpty;

    final effectiveSeed = (hasAvatarSeed || hasUserAvatar)
        ? (hasAvatarSeed ? avatarSeed : userAvatar)
        : AvatarCatalog.getDefaultSeedForGender(gender);

    final Widget avatarCore = AppAvatar(
      avatarSeed: effectiveSeed,
      avatarStyle: avatarStyle,
      gender: gender,
      userAvatar: userAvatar,
      initials: initials,
      radius: radius,
    );

    final Widget ringAvatar = showGlowRing
        ? Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF06B6D4), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.38),
                  blurRadius: 8,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
                BoxShadow(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.25),
                  blurRadius: 6,
                  spreadRadius: 0,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: avatarCore,
            ),
          )
        : avatarCore;

    final totalSize = showGlowRing ? (radius * 2 + 5) : (radius * 2);

    return SizedBox(
      width: totalSize,
      height: totalSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ringAvatar,
          
          // Sharper Online Status Indicator with Neon Glow
          if (showStatus && isOnline == true)
            Positioned(
              bottom: showGlowRing ? 1 : 0,
              right: showGlowRing ? 1 : 0,
              child: Container(
                width: statusIndicatorSize,
                height: statusIndicatorSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981), // Emerald green
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white,
                    width: 2.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.85),
                      blurRadius: 5,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
