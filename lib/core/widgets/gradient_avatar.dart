import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/core/widgets/app_avatar.dart';

class GradientAvatar extends StatelessWidget {
  final String initials;
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;
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
    this.radius = 26,
    this.isOnline,
    this.showStatus = false,
    this.statusIndicatorSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    Widget avatarCore;
    if (avatarSeed != null && avatarSeed!.trim().isNotEmpty) {
      avatarCore = AppAvatar(
        avatarSeed: avatarSeed,
        avatarStyle: avatarStyle,
        gender: gender,
        initials: initials,
        radius: radius,
      );
    } else {
      avatarCore = Container(
        width: radius * 2,
        height: radius * 2,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF9B84FF), // Indigo/Purple
              Color(0xFFD088FF), // Purple/Pink
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: (radius * 0.7).toDouble(),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatarCore,
          
          // Online/Offline Status Indicator
          if (showStatus)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: statusIndicatorSize,
                height: statusIndicatorSize,
                decoration: BoxDecoration(
                  color: isOnline == true ? colors.success : colors.textSecondary.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colors.surface,
                    width: statusIndicatorSize * 0.15,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
