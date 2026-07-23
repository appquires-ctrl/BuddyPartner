import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/widgets/feedback/app_loading_indicator.dart';

/// AppPrimaryButton is the main call-to-action button in the design system.
/// Features a primary color background, circular/pill border radius, and loading support.
class AppPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;
  final bool fullWidth;

  const AppPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final buttonContent = isLoading
        ? AppLoadingIndicator(
            size: 20,
            color: colors.surface,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                icon!,
                const SizedBox(width: 8),
              ],
              Text(
                text,
                style: typography.labelPill.copyWith(
                  color: colors.surface,
                ),
              ),
            ],
          );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.surface,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.pill,
          ),
          disabledBackgroundColor: colors.primary.withOpacity(0.5),
        ),
        onPressed: isLoading ? null : onPressed,
        child: buttonContent,
      ),
    );
  }
}
