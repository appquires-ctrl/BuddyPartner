import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';

class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: colors.danger.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.block,
                  size: 48,
                  color: colors.danger,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Account Permanently Banned',
                style: typography.titleCard.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your account has accumulated 3 moderation strikes and has been permanently banned for violating LoopCall terms of service.',
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: AppRadius.md,
                  border: Border.all(color: colors.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.support_agent_rounded, color: colors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'If you believe this was an error, please contact support@loopcall.app.',
                        style: typography.bodySmall.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
