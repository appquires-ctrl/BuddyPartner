import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:buddypartner/app/theme/skeleton_colors.dart';

/// AppShimmer wraps arbitrary layout structures with animated theme color bands.
/// Uses application theme tint colors by default for consistent brand aesthetics.
class AppShimmer extends StatelessWidget {
  final Widget child;
  final bool enabled;
  final Color? baseColor;
  final Color? highlightColor;

  const AppShimmer({
    super.key,
    required this.child,
    this.enabled = true,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBase = SkeletonColors.baseColor(isDark);
    final defaultHighlight = SkeletonColors.highlightColor(isDark);

    return Shimmer.fromColors(
      baseColor: baseColor ?? defaultBase,
      highlightColor: highlightColor ?? defaultHighlight,
      child: child,
    );
  }
}
