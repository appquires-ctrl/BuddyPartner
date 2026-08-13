import 'package:flutter/material.dart';

/// SkeletonColors provides application theme-based tint colors for loading skeletons.
/// EDIT THESE MASTER COLOR VARIABLES TO CHANGE ALL SKELETON LOADERS IN THE ENTIRE APP FROM ONE LOCATION:
class SkeletonColors {
  // Master Skeleton Loading Colors (Central Control Location)
  static Color background = Colors.transparent;      // Skeleton card container background
  static Color base = const Color(0xFFE8E2FF);       // Shimmer base placeholder block color
  static Color highlight = const Color(0xFFFAF8FF);  // Shimmer animation sweep highlight color
  static Color accent = const Color(0xFFDDD4FE);     // Shimmer accent element color

  // Universal static methods (for backwards compatibility across all skeleton widgets)
  static Color getBackground([bool isDark = false]) => background;
  static Color baseColor([bool isDark = false]) => base;
  static Color highlightColor([bool isDark = false]) => highlight;
  static Color accentColor([bool isDark = false]) => accent;
}


