import 'package:flutter/material.dart';

/// AppRadius defines border radius constants used throughout
/// cards, buttons, chips, and sheet components.
class AppRadius {
  static const double smVal = 8.0;
  static const double mdVal = 16.0;
  static const double lgVal = 24.0;
  static const double pillVal = 999.0;

  static const BorderRadius sm = BorderRadius.all(Radius.circular(smVal));
  static const BorderRadius md = BorderRadius.all(Radius.circular(mdVal));
  static const BorderRadius lg = BorderRadius.all(Radius.circular(lgVal));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(pillVal));

  AppRadius._();
}
