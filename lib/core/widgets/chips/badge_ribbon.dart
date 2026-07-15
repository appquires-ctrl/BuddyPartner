import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../extensions/context_extensions.dart';

/// BadgeRibbon is a diagonal label overlaid on the corner of a card.
/// Designed to be used inside a Stack, where the parent card has `clipBehavior: Clip.antiAlias`.
class BadgeRibbon extends StatelessWidget {
  final String text;
  final Color? color;

  const BadgeRibbon({
    super.key,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSpecialOffer = text.toUpperCase().contains('SPECIAL');
    final defaultBgColor = isSpecialOffer ? colors.warningAmber : colors.success;

    return Positioned(
      top: 12,
      left: -28,
      child: Transform.rotate(
        angle: -math.pi / 4,
        child: Container(
          width: 110,
          padding: const EdgeInsets.symmetric(vertical: 4),
          color: color ?? defaultBgColor,
          alignment: Alignment.center,
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
