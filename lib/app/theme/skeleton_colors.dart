import 'package:flutter/material.dart';

/// SkeletonColors provides application theme-based tint colors for loading skeletons
/// replacing generic dark/grey colors with rich brand lavender & purple theme tones.
class SkeletonColors {
  // Light Theme (Soft Brand Lavender Tint)
  static const Color lightBackground = Color(0xFFFAF9FE);
  static const Color lightBase = Color(0xFFE8E3FD);
  static const Color lightHighlight = Color(0xFFF7F5FE);
  static const Color lightAccent = Color(0xFFDDD5FC);

  // Dark Theme (Deep Brand Purple Tint)
  static const Color darkBackground = Color(0xFF14121E);
  static const Color darkBase = Color(0xFF28233A);
  static const Color darkHighlight = Color(0xFF383150);
  static const Color darkAccent = Color(0xFF453D60);

  static Color background(bool isDark) => isDark ? darkBackground : lightBackground;
  static Color baseColor(bool isDark) => isDark ? darkBase : lightBase;
  static Color highlightColor(bool isDark) => isDark ? darkHighlight : lightHighlight;
  static Color accentColor(bool isDark) => isDark ? darkAccent : lightAccent;
}
