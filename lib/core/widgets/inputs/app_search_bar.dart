import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/app/theme/app_spacing.dart';

/// AppSearchBar renders a geometric, rounded input bar
/// with search icon, tailored to the app themes.
class AppSearchBar extends StatelessWidget {
  final String hintText;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;

  const AppSearchBar({
    super.key,
    this.hintText = 'Search telecallers...',
    this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.pill,
        border: Border.all(color: colors.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: typography.bodyMedium,
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: typography.bodySmall.copyWith(color: colors.textSecondary),
          prefixIcon: Icon(Icons.search, color: colors.textSecondary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: AppSpacing.space12,
            horizontal: AppSpacing.space16,
          ),
        ),
      ),
    );
  }
}
