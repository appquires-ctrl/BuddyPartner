import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/core/widgets/buttons/app_primary_button.dart';

/// AppEmptyState renders a centered layout for empty pages or missing data.
/// It displays an illustration slot, a title, description, and an optional CTA.
class AppEmptyState extends StatelessWidget {
  final Widget? illustration;
  final IconData? icon;
  final String title;
  final String description;
  final String? actionText;
  final VoidCallback? onActionPressed;

  const AppEmptyState({
    super.key,
    this.illustration,
    this.icon,
    required this.title,
    required this.description,
    this.actionText,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (illustration != null)
              illustration!
            else if (icon != null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.space24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary.withOpacity(0.1),
                ),
                child: Icon(
                  icon,
                  size: 64,
                  color: colors.primary,
                ),
              ),
            const SizedBox(height: AppSpacing.space24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: typography.titleCard.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.space12),
            Text(
              description,
              textAlign: TextAlign.center,
              style: typography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (actionText != null && onActionPressed != null) ...[
              const SizedBox(height: AppSpacing.space32),
              AppPrimaryButton(
                text: actionText!,
                onPressed: onActionPressed,
                fullWidth: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
