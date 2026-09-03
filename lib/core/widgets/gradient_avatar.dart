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

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatarCore,
          
          // Online Status Indicator (Only display when user is active online)
          if (showStatus && isOnline == true)
            Positioned(
              bottom: 0,
              right: 0,
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
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
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
