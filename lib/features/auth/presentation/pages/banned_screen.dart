import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';

/// BannedScreen renders the single hard-block account screen when a user is banned.
/// Matches section 4 of the report ban rework requirements.
class BannedScreen extends StatelessWidget {
  const BannedScreen({super.key});

  static const String _supportEmail = 'support@buddypartner.com';

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
              // Icon Badge
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: colors.danger.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.block_rounded,
                  size: 48,
                  color: colors.danger,
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Account Blocked',
                style: typography.titleCard.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Primary Message
              Text(
                'Your account has been blocked due to multiple reports from other users.',
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                  fontSize: 15,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Appeal & Instructions Container
              Container(
                padding: const EdgeInsets.all(AppSpacing.space20),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.mark_email_unread_outlined, color: colors.primary, size: 24),
                        const SizedBox(width: 12),
                        Text(
                          'How to Appeal',
                          style: typography.titleCard.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'If you believe this was a mistake, please send an apology/appeal email to $_supportEmail along with your registered mobile number, explaining your situation.',
                      style: typography.bodySmall.copyWith(
                        color: colors.textPrimary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Accounts are typically reviewed and reactivated within 24 hours.',
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Copy Email Chip
                    InkWell(
                      onTap: () {
                        Clipboard.setData(const ClipboardData(text: _supportEmail));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Support email copied to clipboard!'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      borderRadius: AppRadius.pill,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadius.pill,
                          border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.email_outlined, size: 16, color: colors.primary),
                            const SizedBox(width: 8),
                            Text(
                              _supportEmail,
                              style: typography.bodySmall.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.copy_rounded, size: 14, color: colors.primary),
                          ],
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
