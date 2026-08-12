import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// AppTheme provides ThemeData setup for both light and dark modes
/// using the customized ThemeExtensions.
class AppTheme {
  static ThemeData get light {
    final colors = AppColors.light;
    final typography = AppTypography.create(
      textColor: colors.textPrimary,
      textMutedColor: colors.textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: colors.primary,
      scaffoldBackgroundColor: colors.surfaceMuted,
      cardColor: colors.surface,
      dividerColor: colors.border,
      textTheme: GoogleFonts.interTextTheme(),
      extensions: [
        colors,
        typography,
      ],
      colorScheme: ColorScheme.light(
        primary: colors.primary,
        surface: colors.surface,
        error: colors.danger,
      ),
    );
  }

  static ThemeData get dark {
    final colors = AppColors.dark;
    final typography = AppTypography.create(
      textColor: colors.textPrimary,
      textMutedColor: colors.textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: colors.primary,
      scaffoldBackgroundColor: colors.surfaceMuted,
      cardColor: colors.surface,
      dividerColor: colors.border,
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      extensions: [
        colors,
        typography,
      ],
      colorScheme: ColorScheme.dark(
        primary: colors.primary,
        surface: colors.surface,
        error: colors.danger,
      ),
    );
  }

  AppTheme._();
}
