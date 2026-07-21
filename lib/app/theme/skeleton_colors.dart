import 'package:flutter/material.dart';

class SkeletonColors {
  // Light Theme
  static const Color lightBackground = Color(0xFFFAF8FF);
  static const Color lightBase = Color(0xFFF1EBFF);
  static const Color lightHighlight = Color(0xFFFFFFFF);
  static const Color lightAccent = Color(0xFFE4D8FF);

  // Dark Theme
  static const Color darkBackground = Color(0xFF1A1625);
  static const Color darkBase = Color(0xFF2A2338);
  static const Color darkHighlight = Color(0xFF3B3150);
  static const Color darkAccent = Color(0xFF4A3B67);

  static Color background(bool isDark) => isDark ? darkBackground : lightBackground;
  static Color baseColor(bool isDark) => isDark ? darkBase : lightBase;
  static Color highlightColor(bool isDark) => isDark ? darkHighlight : lightHighlight;
  static Color accentColor(bool isDark) => isDark ? darkAccent : lightAccent;
}
