import 'package:flutter/material.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_radius.dart';

/// AppCard is a stylized container that applies the design system's
/// shadows, borders, and rounded corners depending on light or dark theme.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? elevation;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.width,
    this.height,
    this.borderRadius,
    this.elevation,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final defaultBorder = Border.all(color: colors.cardBorder, width: 1);
    final defaultElevation = [
      BoxShadow(
        color: colors.cardShadow,
        blurRadius: 10,
        offset: const Offset(0, 4),
      ),
    ];

    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.cardBackground,
        borderRadius: borderRadius ?? AppRadius.lg,
        boxShadow: elevation ?? defaultElevation,
        border: border ?? defaultBorder,
      ),
      child: child,
    );
  }
}
