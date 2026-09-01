import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/features/legal/data/legal_document_content.dart';

/// HelpPage renders the Help & Support menu, FAQs, and legal policies.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  String _appVersion = 'v1.0.0';
  int? _expandedFaqIndex;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${info.version}+${info.buildNumber}';
        });
      }
    } catch (_) {
      // Fallback stays v1.0.0
    }
  }

  Future<void> _launchEmail(String email, {String subject = 'Support Inquiry - BuddyPartner'}) async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: email,
      queryParameters: {
        'subject': subject,
      },
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: email));
        if (mounted) {
          AppSnackBar.showSuccess(context, 'Email copied to clipboard: $email');
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: email));
      if (mounted) {
        AppSnackBar.showSuccess(context, 'Email copied to clipboard: $email');
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
              'Help & Legal Center',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Support, FAQs & Policies',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
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
              const SizedBox(height: 8),

              // GET HELP section
              _buildSectionTitle(context, 'GET HELP & SUPPORT'),
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    _buildHelpTile(
                      context,
                      icon: Icons.mail_outline,
                      iconBgColor: const Color(0xFFEFEAFF),
                      iconColor: const Color(0xFF6B4EFF),
                      title: 'Contact Support',
                      subtitle: 'Direct email assistance & response within 24h',
                      onTap: () => _showContactUsModal(context),
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.bug_report_outlined,
                      iconBgColor: const Color(0xFFFFEAEA),
                      iconColor: const Color(0xFFEF4444),
                      title: 'Report an Issue / Bug',
                      subtitle: 'Help us resolve technical or call glitches',
                      onTap: () => _showReportBugModal(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // FREQUENTLY ASKED QUESTIONS section
              _buildSectionTitle(context, 'FREQUENTLY ASKED QUESTIONS'),
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: List.generate(
                    LegalDocumentContent.helpFaqs.length,
                    (index) {
                      final faq = LegalDocumentContent.helpFaqs[index];
                      final isExpanded = _expandedFaqIndex == index;
                      final isLast = index == LegalDocumentContent.helpFaqs.length - 1;

                      return Column(
                        children: [
                          InkWell(
                            onTap: () {
                              setState(() {
                                _expandedFaqIndex = isExpanded ? null : index;
                              });
                            },
                            borderRadius: BorderRadius.vertical(
                              top: index == 0 ? const Radius.circular(16) : Radius.zero,
                              bottom: isLast && !isExpanded ? const Radius.circular(16) : Radius.zero,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.help_outline_rounded,
                                      size: 18,
                                      color: colors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          faq.question,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                            color: colors.textPrimary,
                                          ),
                                        ),
                                        if (isExpanded) ...[
                                          const SizedBox(height: 8),
                                          Text(
                                            faq.answer,
                                            style: typography.bodySmall.copyWith(
                                              color: colors.textSecondary,
                                              fontSize: 13,
                                              height: 1.45,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    color: colors.textSecondary.withValues(alpha: 0.6),
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!isLast) _buildDivider(context),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // LEGAL & POLICIES section
              _buildSectionTitle(context, 'LEGAL, SAFETY & POLICIES'),
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    _buildHelpTile(
                      context,
                      icon: Icons.description_outlined,
                      iconBgColor: const Color(0xFFEAF5FF),
                      iconColor: const Color(0xFF3B82F6),
                      title: 'Terms of Service',
                      subtitle: 'User agreement, eligibility & rules',
                      onTap: () => context.push(RouteNames.termsOfService),
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.shield_outlined,
                      iconBgColor: const Color(0xFFE8F8F0),
                      iconColor: const Color(0xFF22C55E),
                      title: 'Privacy Policy',
                      subtitle: 'Data collection & DPDP privacy protection',
                      onTap: () => context.push(RouteNames.privacyPolicy),
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.groups_outlined,
                      iconBgColor: const Color(0xFFEFEAFF),
                      iconColor: const Color(0xFF6B4EFF),
                      title: 'Community Guidelines',
                      subtitle: 'Conduct, safety & moderation rules',
                      onTap: () => context.push(RouteNames.communityGuidelines),
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.security_rounded,
                      iconBgColor: const Color(0xFFEFF6FF),
                      iconColor: const Color(0xFF2563EB),
                      title: 'Safety & Anti-Fraud Guidelines',
                      subtitle: 'Online dating tips, anti-extortion & scam prevention',
                      onTap: () => context.push(RouteNames.safetyGuidelines),
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.credit_card_outlined,
                      iconBgColor: const Color(0xFFFFF7EA),
                      iconColor: const Color(0xFFF59E0B),
                      title: 'Refund Policy',
                      subtitle: 'Subscription passes & billing rules',
                      onTap: () => context.push(RouteNames.refundPolicy),
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.card_membership_outlined,
                      iconBgColor: const Color(0xFFFFEAF2),
                      iconColor: const Color(0xFFEC4899),
                      title: 'Subscription Terms',
                      subtitle: 'Pass access & validity conditions',
                      onTap: () => context.push(RouteNames.subscriptionTerms),
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.gavel_outlined,
                      iconBgColor: const Color(0xFFF3E8FF),
                      iconColor: const Color(0xFF9333EA),
                      title: 'Grievance Redressal Policy',
                      subtitle: 'Indian IT Rules 2021 statutory mechanism',
                      onTap: () => context.push(RouteNames.grievanceRedressal),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // APP & SYSTEM INFO section
              _buildSectionTitle(context, 'APP & SYSTEM INFO'),
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    _buildHelpTile(
                      context,
                      icon: Icons.info_outline,
                      iconBgColor: const Color(0xFFF0F0F2),
                      iconColor: colors.textSecondary,
                      title: 'App Version',
                      subtitle: _appVersion,
                      showChevron: false,
                      onTap: () {},
                    ),
                    // _buildDivider(context),
                    // _buildHelpTile(
                    //   context,
                    //   icon: Icons.code_rounded,
                    //   iconBgColor: const Color(0xFFF0FDF4),
                    //   iconColor: const Color(0xFF16A34A),
                    //   title: 'Open Source Licenses',
                    //   subtitle: 'Software attributions and third-party notices',
                    //   onTap: () {
                    //     showLicensePage(
                    //       context: context,
                    //       applicationName: 'BuddyPartner',
                    //       applicationVersion: _appVersion,
                    //       applicationLegalese: '© 2026 Appquires Global LLP. All rights reserved.',
                    //     );
                    //   },
                    // ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 72, right: 16),
      child: Divider(color: colors.border, height: 1),
    );
  }

  Widget _buildHelpTile(
    BuildContext context, {
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
    bool showChevron = true,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: iconColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14.5,
            color: colors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
          ),
        ),
        trailing: showChevron
            ? Icon(
                Icons.chevron_right,
                color: colors.textSecondary.withValues(alpha: 0.5),
                size: 18,
              )
            : null,
        onTap: onTap,
      ),
    );
  }

  void _showContactUsModal(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEFEAFF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.headset_mic_outlined, color: Color(0xFF6B4EFF), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BuddyPartner Support',
                            style: typography.titleCard.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          Text(
                            'Official assistance & redressal',
                            style: typography.bodySmall.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Contact details box
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: AppRadius.md,
                      border: Border.all(color: colors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Support Email
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Support Email:', style: typography.bodySmall.copyWith(color: colors.textSecondary, fontSize: 11)),
                            InkWell(
                              onTap: () => _launchEmail(LegalDocumentContent.companyEmail),
                              child: Text(
                                'Tap to Email',
                                style: TextStyle(color: colors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        SelectableText(
                          LegalDocumentContent.companyEmail,
                          style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold, color: colors.primary, fontSize: 13.5),
                        ),
                        const SizedBox(height: 12),


                        // Registered Entity
                        // Text('Operating Business Entity:', style: typography.bodySmall.copyWith(color: colors.textSecondary, fontSize: 11)),
                        // const SizedBox(height: 2),
                        // Text(
                        //   LegalDocumentContent.companyName,
                        //   style: typography.bodyMedium.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                        // ),
                        // const SizedBox(height: 12),

                        // Registered Office Address
                        // Text('Registered Office Address:', style: typography.bodySmall.copyWith(color: colors.textSecondary, fontSize: 11)),
                        // const SizedBox(height: 2),
                        // SelectableText(
                        //   LegalDocumentContent.companyAddress,
                        //   style: typography.bodySmall.copyWith(color: colors.textPrimary, height: 1.35, fontSize: 11.5),
                        // ),
                        // const SizedBox(height: 12),

                        // Response SLA
                        // Container(
                        //   padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        //   decoration: BoxDecoration(
                        //     color: colors.chipLavender,
                        //     borderRadius: BorderRadius.circular(8),
                        //   ),
                        //   child: Row(
                        //     children: [
                        //       Icon(Icons.access_time_rounded, size: 14, color: colors.primary),
                        //       const SizedBox(width: 6),
                        //       Expanded(
                        //         child: Text(
                        //           'SLA: Acknowledgment in 24h; resolution in 15 days.',
                        //           style: TextStyle(
                        //             fontSize: 11,
                        //             fontWeight: FontWeight.w600,
                        //             color: colors.primary,
                        //           ),
                        //         ),
                        //       ),
                        //     ],
                        //   ),
                        // ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            side: BorderSide(color: colors.border),
                          ),
                          onPressed: () {
                            Clipboard.setData(const ClipboardData(text: LegalDocumentContent.companyEmail));
                            Navigator.pop(context);
                            AppSnackBar.showSuccess(context, 'Support email copied to clipboard.');
                          },
                          child: Text('Copy Email', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            _launchEmail(LegalDocumentContent.companyEmail);
                          },
                          child: const Text('Open Mail App', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showReportBugModal(BuildContext context) {
    AppLogger.dialogOpen('Report a Bug', screen: 'HelpPage');
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _ReportBugBottomSheet(),
    );
  }
}

class _ReportBugBottomSheet extends ConsumerStatefulWidget {
  const _ReportBugBottomSheet();

  @override
  ConsumerState<_ReportBugBottomSheet> createState() => _ReportBugBottomSheetState();
}

class _ReportBugBottomSheetState extends ConsumerState<_ReportBugBottomSheet> {
  final TextEditingController _controller = TextEditingController();
  String? _selectedCategory;
  bool _isSubmitting = false;

  static const List<({String key, String title, IconData icon})> _categories = [
    (key: 'Audio / Call Issue', title: 'Audio or Call Connection Issue', icon: Icons.phone_in_talk_rounded),
    (key: 'Video Glitch', title: 'Video Stream / Camera Glitch', icon: Icons.videocam_rounded),
    (key: 'Subscription & Billing', title: 'Subscription, Pass or Billing', icon: Icons.card_membership_outlined),
    (key: 'App Crash / Freeze', title: 'App Crash, Freeze, or Slow Loading', icon: Icons.speed_rounded),
    (key: 'Other Issue', title: 'Other Issue / Feedback', icon: Icons.edit_note_rounded),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    final text = _controller.text.trim();
    if (_selectedCategory == null) {
      AppSnackBar.showError(context, 'Please select an issue category.');
      return;
    }
    if (text.isEmpty) {
      AppSnackBar.showError(context, 'Please describe the issue encountered.');
      return;
    }

    setState(() => _isSubmitting = true);
    AppLogger.button('Submit Bug Report', screen: 'HelpPage');

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.post(
        '/api/support/bug-report',
        data: {
          'category': _selectedCategory,
          'description': text,
          'appVersion': '1.0.0',
          'platform': Theme.of(context).platform.name,
        },
      );

      if (mounted) {
        if (response.statusCode == 200 && response.data['success'] == true) {
          AppLogger.dialogClose('Submit Report', screen: 'HelpPage');
          Navigator.pop(context);
          AppSnackBar.showSuccess(context, 'Thank you! Your report has been submitted to our engineering team.');
        } else {
          final msg = response.data['error'] ?? 'Failed to submit bug report.';
          AppSnackBar.showError(context, msg.toString());
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Unable to submit report. Please check your network connection.');
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1929) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.border.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Header Row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFEF2F2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.bug_report_outlined, color: Color(0xFFDC2626), size: 24),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Report an Issue',
                          style: typography.titleCard.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Help us resolve glitches quickly',
                          style: typography.bodySmall.copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Category Selection Label
                Text(
                  'SELECT CATEGORY',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),

                // Category List
                ..._categories.map((c) {
                  final isSelected = _selectedCategory == c.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedCategory = c.key);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.primary.withValues(alpha: 0.08)
                              : colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? colors.primary
                                : colors.border.withValues(alpha: 0.6),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              c.icon,
                              size: 19,
                              color: isSelected ? colors.primary : colors.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                c.title,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  color: isSelected ? colors.primary : colors.textPrimary,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: colors.primary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(height: 12),

                // Description Field
                Text(
                  'DESCRIPTION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _controller,
                  maxLines: 3,
                  style: typography.bodyMedium.copyWith(color: colors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Describe what happened or steps to reproduce...',
                    hintStyle: typography.bodySmall.copyWith(
                      color: colors.textSecondary.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: colors.surfaceMuted,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colors.border.withValues(alpha: 0.6)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colors.primary, width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          side: BorderSide(color: colors.border),
                        ),
                        onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: _isSubmitting ? null : _submitReport,
                        child: _isSubmitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Submit Report',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
