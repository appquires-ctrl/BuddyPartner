import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_radius.dart';

/// AppChip renders a simple pill badge or chip, with selection state support.
class AppChip extends StatelessWidget {
  final String label;
  final Widget? avatar;
  final bool isSelected;
  final VoidCallback? onTap;

  const AppChip({
    super.key,
    required this.label,
    this.avatar,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final bgColor = isSelected ? colors.primary : colors.chipLavender;
    final labelColor = isSelected ? colors.surface : colors.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: AppRadius.pill,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (avatar != null) ...[
              avatar!,
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: typography.labelPill.copyWith(
                color: labelColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
