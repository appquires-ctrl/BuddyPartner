import 'package:flutter/material.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';

enum AppCoinBadgeVariant {
  pill, // Standard AppBar / Header pill (light purple background with primary text)
  gold, // Golden glowing pill
  glass, // Translucent glassmorphism pill for dark/gradient backgrounds
  subtle, // Soft grey/dark neutral pill
  green, // Green bonus pill (+10 Free)
}

/// Universal AppCoinBadge chip for displaying coin counts consistently across all screens.
class AppCoinBadge extends StatelessWidget {
  final dynamic coins; // int or String
  final String? prefix;
  final String? suffix;
  final AppCoinBadgeVariant variant;
  final VoidCallback? onTap;
  final double iconSize;
  final double fontSize;
  final EdgeInsetsGeometry? padding;

  const AppCoinBadge({
    super.key,
    required this.coins,
    this.prefix,
    this.suffix,
    this.variant = AppCoinBadgeVariant.pill,
    this.onTap,
    this.iconSize = 16.0,
    this.fontSize = 13.0,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    BoxDecoration decoration;
    Color textColor;

    switch (variant) {
      case AppCoinBadgeVariant.pill:
        decoration = BoxDecoration(
          color: isDark ? const Color(0xFF28213E) : const Color(0xFFF1EFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF7C6AEF).withValues(alpha: 0.25),
            width: 1,
          ),
        );
        textColor = isDark ? const Color(0xFFA594F9) : const Color(0xFF6342E8);
        break;

      case AppCoinBadgeVariant.gold:
        decoration = BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8E1), Color(0xFFFFECB3)],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFFFFB300).withValues(alpha: 0.6),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFB300).withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        );
        textColor = const Color(0xFFB45309);
        break;

      case AppCoinBadgeVariant.glass:
        decoration = BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1,
          ),
        );
        textColor = Colors.white;
        break;

      case AppCoinBadgeVariant.subtle:
        decoration = BoxDecoration(
          color: isDark ? const Color(0xFF1E1A2E) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white10 : const Color(0xFFE5E7EB),
            width: 1,
          ),
        );
        textColor = isDark ? Colors.white70 : const Color(0xFF374151);
        break;

      case AppCoinBadgeVariant.green:
        decoration = BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: 0.3),
            width: 1,
          ),
        );
        textColor = const Color(0xFF059669);
        break;
    }

    final displayText = '${prefix ?? ''}$coins${suffix != null ? ' $suffix' : ''}';

    final content = Container(
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: iconSize * 0.6,
            vertical: iconSize * 0.25,
          ),
      decoration: decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AppCoinIcon(
            size: iconSize,
            withGlow: variant == AppCoinBadgeVariant.gold,
          ),
          SizedBox(width: iconSize * 0.35),
          Text(
            displayText,
            style: TextStyle(
              color: textColor,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      // return InkWell(
      //   onTap: onTap,
      //   borderRadius: BorderRadius.circular(20),
      //   child: content,
      // );
    }

    return content;
  }
}
