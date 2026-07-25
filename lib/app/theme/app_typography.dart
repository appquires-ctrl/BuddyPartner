import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AppTypography defines the typographic styles for the LoopCall design system.
/// It uses Poppins as the geometric rounded/geometric sans font family.
@immutable
class AppTypography extends ThemeExtension<AppTypography> {
  final TextStyle displayWordmark;
  final TextStyle headlineGreeting;
  final TextStyle titleCard;
  final TextStyle bodyMedium;
  final TextStyle bodySmall;
  final TextStyle labelPill;

  const AppTypography({
    required this.displayWordmark,
    required this.headlineGreeting,
    required this.titleCard,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelPill,
  });

  /// Factory constructor to generate text styles adapted to theme-specific colors
  factory AppTypography.create({required Color textColor, required Color textMutedColor}) {
    return AppTypography(
      displayWordmark: GoogleFonts.poppins(
        fontSize: 32.0,
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      headlineGreeting: GoogleFonts.poppins(
        fontSize: 28.0,
        fontWeight: FontWeight.bold,
        color: textColor,
      ),
      titleCard: GoogleFonts.poppins(
        fontSize: 20.0,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
      bodyMedium: GoogleFonts.poppins(
        fontSize: 16.0,
        fontWeight: FontWeight.normal,
        color: textColor,
      ),
      bodySmall: GoogleFonts.poppins(
        fontSize: 14.0,
        fontWeight: FontWeight.normal,
        color: textMutedColor,
      ),
      labelPill: GoogleFonts.poppins(
        fontSize: 14.0,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
        color: textColor,
      ),
    );
  }

  @override
  AppTypography copyWith({
    TextStyle? displayWordmark,
    TextStyle? headlineGreeting,
    TextStyle? titleCard,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? labelPill,
  }) {
    return AppTypography(
      displayWordmark: displayWordmark ?? this.displayWordmark,
      headlineGreeting: headlineGreeting ?? this.headlineGreeting,
      titleCard: titleCard ?? this.titleCard,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      labelPill: labelPill ?? this.labelPill,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      displayWordmark: TextStyle.lerp(displayWordmark, other.displayWordmark, t)!,
      headlineGreeting: TextStyle.lerp(headlineGreeting, other.headlineGreeting, t)!,
      titleCard: TextStyle.lerp(titleCard, other.titleCard, t)!,
      bodyMedium: TextStyle.lerp(bodyMedium, other.bodyMedium, t)!,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
      labelPill: TextStyle.lerp(labelPill, other.labelPill, t)!,
    );
  }
}
