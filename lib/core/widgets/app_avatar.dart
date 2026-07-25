import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dating_app/core/constants/avatar_catalog.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';

/// AppAvatar renders bundled SVG avatars based on avatarSeed and avatarStyle,
/// with a graceful fallback to a neutral initials avatar if no seed is available.
class AppAvatar extends StatelessWidget {
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;
  final String initials;
  final double radius;
  final bool isSelected;
  final Color? borderColor;
  final VoidCallback? onTap;

  const AppAvatar({
    super.key,
    this.avatarSeed,
    this.avatarStyle,
    this.gender,
    this.initials = 'U',
    this.radius = 24,
    this.isSelected = false,
    this.borderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final assetPath = AvatarCatalog.getAssetPath(avatarSeed, gender: gender);

    final double size = radius * 2;
    final activeBorderColor = borderColor ?? colors.primary;

    Widget avatarChild;
    if (assetPath != null) {
      avatarChild = ClipOval(
        child: SvgPicture.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholderBuilder: (context) => _buildFallback(colors, typography),
        ),
      );
    } else {
      avatarChild = _buildFallback(colors, typography);
    }

    Widget content = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected ? activeBorderColor : (borderColor ?? Colors.transparent),
          width: isSelected ? 3.0 : (borderColor != null ? 1.5 : 0.0),
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: activeBorderColor.withValues(alpha: 0.35),
                  blurRadius: 8,
                  spreadRadius: 2,
                )
              ]
            : null,
      ),
      child: avatarChild,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: content,
      );
    }

    return content;
  }

  Widget _buildFallback(dynamic colors, dynamic typography) {
    final cleanInitials = initials.isNotEmpty ? initials[0].toUpperCase() : 'U';
    return CircleAvatar(
      radius: radius,
      backgroundColor: colors.primary,
      child: Text(
        cleanInitials,
        style: typography.labelPill.copyWith(
          color: Colors.white,
          fontSize: (radius * 0.8).toDouble(),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
