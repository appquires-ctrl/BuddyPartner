import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';

/// Extension methods on BuildContext to simplify retrieving
/// AppColors and AppTypography from the theme context.
extension ThemeContextExtension on BuildContext {
  /// Quick access to the custom AppColors theme extension
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.light;

  /// Quick access to the custom AppTypography theme extension
  AppTypography get typography => Theme.of(this).extension<AppTypography>() ?? AppTypography.create(
    textColor: Colors.black,
    textMutedColor: Colors.grey,
  );
}

/// Extension methods on num to format coin numbers consistently.
extension CoinNumberExtension on num {
  /// Appends coins format
  String toCoins() {
    return toString();
  }
}
