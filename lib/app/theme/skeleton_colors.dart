import 'package:flutter/material.dart';

class SkeletonColors {
  // Light Theme
  static const Color lightBackground = Color(0xFFFAF8FF);
  static const Color lightBase = Color(0xFFE5DFFF);
  static const Color lightHighlight = Color(0xFFF1EBFF);
  static const Color lightAccent = Color(0xFFD6C8FF);

  // Dark Theme
  static const Color darkBackground = Color(0xFF1A1625);
  static const Color darkBase = Color(0xFF322745);
  static const Color darkHighlight = Color(0xFF42345B);
  static const Color darkAccent = Color(0xFF58457D);

  static Color background(bool isDark) => isDark ? darkBackground : lightBackground;
  static Color baseColor(bool isDark) => isDark ? darkBase : lightBase;
  static Color highlightColor(bool isDark) => isDark ? darkHighlight : lightHighlight;
  static Color accentColor(bool isDark) => isDark ? darkAccent : lightAccent;
}
