import 'package:flutter/material.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/core/utils/app_throttler.dart';

/// AppPrimaryButton is the main call-to-action button in the design system.
/// Features a pink gradient background (#E91E63 -> #FF4081), pill border radius, and loading support.
class AppPrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? icon;
  final bool fullWidth;
  final Gradient? gradient;

  const AppPrimaryButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.fullWidth = true,
    this.gradient,
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
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          );

    final effectiveGradient = gradient ??
        const LinearGradient(
          colors: [
            Color(0xFF3B82F6),
            Color(0xFFE91E63), // Vibrant Pink
             // Light Pink Accent
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        );

    final isDisabled = isLoading || onPressed == null;

    return Container(
      width: fullWidth ? double.infinity : null,
      height: 54,
      decoration: BoxDecoration(
        gradient: isDisabled
            ? LinearGradient(
                colors: [
                  const Color(0xFF3B82F6).withValues(alpha: 0.4),
                  const Color(0xFFE91E63).withValues(alpha: 0.4),
                  
                ],
              )
            : effectiveGradient,
        borderRadius: AppRadius.pill,
        boxShadow: isDisabled
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: colors.surface,
          elevation: 0,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.pill,
          ),
        ),
        onPressed: isLoading ? null : AppThrottler.wrap(onPressed),
        child: buttonContent,
      ),
    );
  }
}
