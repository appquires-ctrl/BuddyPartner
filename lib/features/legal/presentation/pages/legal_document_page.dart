import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/widgets/layout/section_header.dart';
import 'package:dating_app/features/legal/data/legal_document_content.dart';

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
              // Draft legal notice banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB), // Amber light fill
                  borderRadius: AppRadius.md,
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.gavel_outlined,
                      color: Color(0xFFD97706),
                      size: 20,
                    ),
                    const SizedBox(width: AppSpacing.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Legal Draft Preview',
                            style: typography.bodySmall.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFB45309),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            document.summaryNotice,
                            style: typography.bodySmall.copyWith(
                              fontSize: 11.5,
                              color: const Color(0xFF92400E),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space16),

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
                    'LoopCall Governance',
                    style: typography.bodySmall.copyWith(
                      fontSize: 11,
                      color: colors.textSecondary.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space20),

              // Document sections list
              ...document.sections.map((section) => _buildSection(context, section)),

              const SizedBox(height: AppSpacing.space24),
              Center(
                child: Text(
                  'End of ${document.title}',
                  style: typography.bodySmall.copyWith(
                    color: colors.textSecondary.withOpacity(0.6),
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
            child: SelectableText.rich(
              _highlightPlaceholders(
                section.content,
                baseStyle: typography.bodyMedium.copyWith(
                  color: colors.textPrimary,
                  fontSize: 13.5,
                  height: 1.5,
                ),
                placeholderStyle: typography.bodyMedium.copyWith(
                  color: const Color(0xFF6B4EFF),
                  fontWeight: FontWeight.bold,
                  backgroundColor: const Color(0xFFF3EFFF),
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Highlights bracketed placeholders like [Company Legal Name]
  TextSpan _highlightPlaceholders(
    String text, {
    required TextStyle baseStyle,
    required TextStyle placeholderStyle,
  }) {
    final RegExp regex = RegExp(r'\[([^\]]+)\]');
    final List<TextSpan> spans = [];
    int start = 0;

    for (final Match match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start), style: baseStyle));
      }
      spans.add(TextSpan(text: match.group(0), style: placeholderStyle));
      start = match.end;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }

    return TextSpan(children: spans);
  }
}
