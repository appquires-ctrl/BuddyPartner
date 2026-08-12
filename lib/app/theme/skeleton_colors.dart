import 'package:flutter/material.dart';

/// SkeletonColors provides application theme-based tint colors for loading skeletons
/// replacing generic dark/grey colors with rich brand lavender & purple theme tones.
class SkeletonColors {
  // Light Theme (Soft Brand Lavender Tint)
  static const Color lightBackground = Color(0xFFFAF9FE);
  static const Color lightBase = Color(0xFFE8E2FF);
  static const Color lightHighlight = Color(0xFFFAF8FF);
  static const Color lightAccent = Color(0xFFDDD4FE);

  // Dark Theme (Deep Brand Purple Tint)
  static const Color darkBackground = Color(0xFF12101A);
  static const Color darkBase = Color(0xFF262137);
  static const Color darkHighlight = Color(0xFF3C3456);
  static const Color darkAccent = Color(0xFF4A4068);

  static Color background(bool isDark) => isDark ? darkBackground : lightBackground;
  static Color baseColor(bool isDark) => isDark ? darkBase : lightBase;
  static Color highlightColor(bool isDark) => isDark ? darkHighlight : lightHighlight;
  static Color accentColor(bool isDark) => isDark ? darkAccent : lightAccent;
}

