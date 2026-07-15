import 'package:flutter/animation.dart';

/// AppDurations holds standard duration settings for transition animations.
class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);

  AppDurations._();
}

/// AppCurves holds standard easing curves for transition animations.
class AppCurves {
  static const Curve standard = Curves.easeOutCubic;

  AppCurves._();
}
