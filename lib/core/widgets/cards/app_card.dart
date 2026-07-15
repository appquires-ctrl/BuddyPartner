import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_elevation.dart';
import 'package:dating_app/app/theme/app_radius.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultElevation = isDark ? AppElevation.cardDark : AppElevation.card;
    final defaultBorder = Border.all(color: colors.border, width: 1);

    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surface,
        borderRadius: borderRadius ?? AppRadius.lg,
        boxShadow: elevation ?? defaultElevation,
        border: border ?? (isDark ? null : defaultBorder),
      ),
      child: child,
    );
  }
}
