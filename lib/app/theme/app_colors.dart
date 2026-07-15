import 'package:flutter/material.dart';

/// AppColors is a custom ThemeExtension that holds the color palette
/// for the LoopCall design system. This enables access to design system
/// colors directly from context using `Theme.of(context).extension<AppColors>()`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color primary;
  final Color primaryGradientStart;
  final Color primaryGradientEnd;
  final Color surface;
  final Color surfaceMuted;
  final List<Color> walletCardBg;
  final Color chipLavender;
  final Color success;
  final Color warningAmber;
  final Color danger;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  const AppColors({
    required this.primary,
    required this.primaryGradientStart,
    required this.primaryGradientEnd,
    required this.surface,
    required this.surfaceMuted,
    required this.walletCardBg,
    required this.chipLavender,
    required this.success,
    required this.warningAmber,
    required this.danger,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });

  /// Light theme color definitions
  static const light = AppColors(
    primary: Color(0xFF7C6AEF),
    primaryGradientStart: Color(0xFF8B7CF6),
    primaryGradientEnd: Color(0xFFE8A9E0),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF5F4FA),
    walletCardBg: [Color(0xFF161616), Color(0xFF2A2A2A)],
    chipLavender: Color(0xFFE7E3FB),
    success: Color(0xFF2FBE7A),
    warningAmber: Color(0xFFF2A93B),
    danger: Color(0xFFEF5350),
    textPrimary: Color(0xFF1A1A1A),
    textSecondary: Color(0xFF8A8A93),
    border: Color(0xFFECEBF3),
  );

  /// Dark theme color definitions
  static const dark = AppColors(
    primary: Color(0xFF9282F2),
    primaryGradientStart: Color(0xFF9B8DF7),
    primaryGradientEnd: Color(0xFFEDBAE7),
    surface: Color(0xFF1E1E24),
    surfaceMuted: Color(0xFF121216),
    walletCardBg: [Color(0xFF0C0C0C), Color(0xFF1A1A1A)],
    chipLavender: Color(0xFF2B273F),
    success: Color(0xFF3DCE89),
    warningAmber: Color(0xFFF5B958),
    danger: Color(0xFFF26B68),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFA1A1AA),
    border: Color(0xFF2E2D38),
  );

  @override
  AppColors copyWith({
    Color? primary,
    Color? primaryGradientStart,
    Color? primaryGradientEnd,
    Color? surface,
    Color? surfaceMuted,
    List<Color>? walletCardBg,
    Color? chipLavender,
    Color? success,
    Color? warningAmber,
    Color? danger,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      primaryGradientStart: primaryGradientStart ?? this.primaryGradientStart,
      primaryGradientEnd: primaryGradientEnd ?? this.primaryGradientEnd,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      walletCardBg: walletCardBg ?? this.walletCardBg,
      chipLavender: chipLavender ?? this.chipLavender,
      success: success ?? this.success,
      warningAmber: warningAmber ?? this.warningAmber,
      danger: danger ?? this.danger,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primary: Color.lerp(primary, other.primary, t)!,
      primaryGradientStart: Color.lerp(primaryGradientStart, other.primaryGradientStart, t)!,
      primaryGradientEnd: Color.lerp(primaryGradientEnd, other.primaryGradientEnd, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      walletCardBg: t < 0.5 ? walletCardBg : other.walletCardBg,
      chipLavender: Color.lerp(chipLavender, other.chipLavender, t)!,
      success: Color.lerp(success, other.success, t)!,
      warningAmber: Color.lerp(warningAmber, other.warningAmber, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      border: Color.lerp(border, other.border, t)!,
    );
  }
}
