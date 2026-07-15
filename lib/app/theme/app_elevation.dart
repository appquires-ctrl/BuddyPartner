import 'package:flutter/material.dart';

/// AppElevation defines shadows and offsets that replace default Material elevations
/// with premium subtle, colored shadows for a clean look.
class AppElevation {
  static const List<BoxShadow> none = [];

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x0C7C6AEF), // subtle purple tint
      offset: Offset(0, 8),
      blurRadius: 16,
      spreadRadius: -4,
    ),
    BoxShadow(
      color: Color(0x057C6AEF),
      offset: Offset(0, 2),
      blurRadius: 4,
      spreadRadius: -2,
    ),
  ];

  static const List<BoxShadow> cardDark = [
    BoxShadow(
      color: Color(0x33000000), // dark neutral shadow
      offset: Offset(0, 8),
      blurRadius: 16,
      spreadRadius: -4,
    ),
  ];

  AppElevation._();
}
