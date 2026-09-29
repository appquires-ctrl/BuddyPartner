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

/// Extension methods on BuildContext for safe insets and navigation bar clearance.
extension SafeInsetsExtension on BuildContext {
  /// Returns safe bottom padding that guarantees UI content and CTA buttons
  /// are NEVER covered by system navigation bars (Samsung 3-button nav, gesture bars,
  /// iPhone home indicator) or the onscreen keyboard.
  double safeBottomPadding({double extra = 16.0}) {
    final media = MediaQuery.of(this);
    final navBarHeight = media.padding.bottom;
    final keyboardHeight = media.viewInsets.bottom;
    return keyboardHeight + (navBarHeight > 0 ? navBarHeight : 12.0) + extra;
  }
}
