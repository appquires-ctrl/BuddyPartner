import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:buddypartner/core/constants/avatar_catalog.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';

/// AppAvatar renders bundled SVG avatars or network avatar URLs,
/// with a graceful fallback to a neutral initials avatar if no seed/URL is available.
class AppAvatar extends StatelessWidget {
  final String? avatarSeed;
  final String? avatarStyle;
  final String? gender;
  final String? userAvatar;
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
    this.userAvatar,
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

    final effectiveSeed = (avatarSeed != null && avatarSeed!.trim().isNotEmpty)
        ? avatarSeed!.trim()
        : (userAvatar != null && userAvatar!.trim().isNotEmpty ? userAvatar!.trim() : null);

    final double size = radius * 2;
    final activeBorderColor = borderColor ?? colors.primary;

    Widget avatarChild;
    if (effectiveSeed != null && (effectiveSeed.startsWith('http://') || effectiveSeed.startsWith('https://'))) {
      avatarChild = ClipOval(
        child: Image.network(
          effectiveSeed,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildFallback(colors, typography),
        ),
      );
    } else {
      final safeSeed = (effectiveSeed != null && effectiveSeed.isNotEmpty)
          ? effectiveSeed
          : AvatarCatalog.getDefaultSeedForGender(gender);
      final assetPath = AvatarCatalog.getAssetPath(safeSeed, gender: gender);
      if (assetPath != null) {
        avatarChild = ClipOval(
          child: SvgPicture.asset(
            assetPath,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholderBuilder: (context) => _buildFallback(colors, typography),
            errorBuilder: (context, error, stackTrace) {
              final isFemale = (gender ?? '').toLowerCase().contains('female');
              final guaranteedPath = isFemale
                  ? 'assets/avatars/female/avatar_female_1.svg'
                  : 'assets/avatars/male/avatar_male_2f.svg';
              return SvgPicture.asset(
                guaranteedPath,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error2, stackTrace2) => _buildFallback(colors, typography),
              );
            },
          ),
        );
      } else {
        avatarChild = _buildFallback(colors, typography);
      }
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
      backgroundColor: colors.primary.withValues(alpha: 0.15),
      child: Text(
        cleanInitials,
        style: TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
