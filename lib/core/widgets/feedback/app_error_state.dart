import 'package:flutter/material.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/widgets/buttons/app_primary_button.dart';

/// AppErrorState displays standard error alerts and handles retry action setups.
class AppErrorState extends StatelessWidget {
  final String errorMessage;
  final VoidCallback? onRetry;

  const AppErrorState({
    super.key,
    required this.errorMessage,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    final lower = errorMessage.toLowerCase();
    final isOffline = lower.contains('socketexception') ||
        lower.contains('no internet') ||
        lower.contains('network error') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection timeout') ||
        lower.contains('connection error');

    final title = isOffline ? 'No Internet Connection' : 'Something went wrong';
    final displayMsg = isOffline
        ? 'Please check your Wi-Fi or cellular network settings and try again.'
        : errorMessage;
    final iconData = isOffline ? Icons.wifi_off_rounded : Icons.warning_amber_rounded;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.space24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.space16),
              decoration: BoxDecoration(
                color: colors.danger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                iconData,
                color: colors.danger,
                size: 44,
              ),
            ),
            const SizedBox(height: AppSpacing.space20),
            Text(
              title,
              style: typography.titleCard.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.space8),
            Text(
              displayMsg,
              textAlign: TextAlign.center,
              style: typography.bodySmall.copyWith(
                color: colors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.space24),
              AppPrimaryButton(
                text: 'Try Again',
                onPressed: onRetry,
                fullWidth: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
