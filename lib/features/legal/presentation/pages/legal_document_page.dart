import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/layout/section_header.dart';
import 'package:buddypartner/features/legal/data/legal_document_content.dart';

/// LegalDocumentPage renders legal terms, policies, and community guidelines
/// using design-system tokens and components.
class LegalDocumentPage extends StatelessWidget {
  final LegalDocument document;

  const LegalDocumentPage({
    super.key,
    required this.document,
  });

  factory LegalDocumentPage.fromId(String id) {
    return LegalDocumentPage(document: LegalDocumentContent.getById(id));
  }

  Future<void> _handleEmailContact(BuildContext context) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: LegalDocumentContent.companyEmail,
      queryParameters: {
        'subject': 'Inquiry regarding ${document.title} - BuddyPartner',
      },
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(const ClipboardData(text: LegalDocumentContent.companyEmail));
        if (context.mounted) {
          AppSnackBar.showSuccess(context, 'Support email copied: ${LegalDocumentContent.companyEmail}');
        }
      }
    } catch (_) {
      await Clipboard.setData(const ClipboardData(text: LegalDocumentContent.companyEmail));
      if (context.mounted) {
        AppSnackBar.showSuccess(context, 'Support email copied: ${LegalDocumentContent.companyEmail}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              document.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              document.subtitle,
              style: typography.bodySmall.copyWith(
                fontSize: 11,
                color: colors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space16,
            vertical: AppSpacing.space12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Last updated badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10.0,
                      vertical: AppSpacing.space4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.chipLavender,
                      borderRadius: AppRadius.pill,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.schedule_outlined,
                          size: 13,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Last updated: ${document.lastUpdated}',
                          style: typography.bodySmall.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'BuddyPartner Governance',
                    style: typography.bodySmall.copyWith(
                      fontSize: 11,
                      color: colors.textSecondary.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space20),

              // Document sections list
              ...document.sections.map((section) => _buildSection(context, section)),

              const SizedBox(height: AppSpacing.space20),

              // Support & Grievance Contact Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space16),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.05),
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.primary.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.headset_mic_outlined, size: 20, color: colors.primary),
                        const SizedBox(width: 8),
                        Text(
                          'Need Assistance or Clarification?',
                          style: typography.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'If you have questions about these terms or wish to reach our Grievance Officer, contact our team at support@buddypartner.in.',
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () => _handleEmailContact(context),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.mail_outline, size: 16, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(
                              'Email Support',
                              style: typography.bodySmall.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.space24),
              Center(
                child: Text(
                  'End of ${document.title}',
                  style: typography.bodySmall.copyWith(
                    color: colors.textSecondary.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, LegalDocumentSection section) {
    final colors = context.colors;
    final typography = context.typography;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.space20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: section.title),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.space16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: AppRadius.lg,
              border: Border.all(color: colors.border),
            ),
            child: SelectableText(
              section.content,
              style: typography.bodyMedium.copyWith(
                color: colors.textPrimary,
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
