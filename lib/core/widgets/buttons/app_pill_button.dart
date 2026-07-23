import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/widgets/feedback/app_loading_indicator.dart';

/// AppPillButton is a compact, pill-shaped button typically used for selections,
/// filters, or displaying plan prices (e.g. the lavender price buttons).
class AppPillButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? textColor;
  final double? height;
  final bool isLoading;

  const AppPillButton({
    super.key,
    required this.text,
    this.onPressed,
    this.backgroundColor,
    this.textColor,
    this.height = 36.0,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final bgColor = backgroundColor ?? colors.chipLavender;
    final txtColor = textColor ?? colors.primary;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: txtColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.pill,
          ),
          disabledBackgroundColor: bgColor.withValues(alpha: 0.5),
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? AppLoadingIndicator(
                size: 16,
                color: txtColor,
              )
            : Text(
                text,
                style: typography.labelPill.copyWith(
                  color: txtColor,
                  fontSize: 13,
                ),
              ),
      ),
    );
  }
}
