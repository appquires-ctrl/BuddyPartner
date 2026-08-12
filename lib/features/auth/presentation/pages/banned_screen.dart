import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';

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
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Warning Icon Hero Badge
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFCA5A5),
                    width: 2,
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.block_rounded,
                    color: Color(0xFFDC2626),
                    size: 48,
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.space24),

              // Title
              Text(
                'Account Banned',
                style: typography.titleCard.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFDC2626),
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: AppSpacing.space12),

              // Description
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text(
                  'Your account has been permanently suspended for violating community guidelines and safety rules.',
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const Spacer(flex: 2),

              // Help & Support Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: AppRadius.lg,
                  border: Border.all(
                    color: colors.border,
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      'Think this was a mistake?',
                      style: typography.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Contact our support team to request an appeal',
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
                        AppSnackBar.showInfo(context, 'Support email copied to clipboard!');
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
