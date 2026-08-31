import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';

/// HelpPage renders the Help & Support menu categories.
/// Matches screenshots/help.jpeg exactly.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

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
              'Help',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Support & FAQs',
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
              const SizedBox(height: 12),

              // GET HELP section
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'GET HELP',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
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
                      title: 'Contact Us',
                      subtitle: 'Get in touch with our support team',
                      onTap: () {
                        _showContactUsModal(context);
                      },
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.bug_report_outlined,
                      iconBgColor: const Color(0xFFFFEAEA),
                      iconColor: const Color(0xFFEF4444),
                      title: 'Report a Bug',
                      subtitle: 'Help us improve the app',
                      onTap: () {
                        _showReportBugModal(context);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // LEGAL section
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'LEGAL & POLICIES',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
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
                      onTap: () {
                        context.push(RouteNames.termsOfService);
                      },
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.shield_outlined,
                      iconBgColor: const Color(0xFFE8F8F0),
                      iconColor: const Color(0xFF22C55E),
                      title: 'Privacy Policy',
                      subtitle: 'Data collection & privacy protection',
                      onTap: () {
                        context.push(RouteNames.privacyPolicy);
                      },
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.groups_outlined,
                      iconBgColor: const Color(0xFFEFEAFF),
                      iconColor: const Color(0xFF6B4EFF),
                      title: 'Community Guidelines',
                      subtitle: 'Conduct, safety & moderation rules',
                      onTap: () {
                        context.push(RouteNames.communityGuidelines);
                      },
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.credit_card_outlined,
                      iconBgColor: const Color(0xFFFFF7EA),
                      iconColor: const Color(0xFFF59E0B),
                      title: 'Refund Policy',
                      subtitle: 'Subscription passes, billing & store refunds',
                      onTap: () {
                        context.push(RouteNames.refundPolicy);
                      },
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.account_balance_wallet_outlined,
                      iconBgColor: const Color(0xFFFFEAF2),
                      iconColor: const Color(0xFFEC4899),
                      title: 'Subscription Terms',
                      subtitle: 'Pass rules & subscription guidelines',
                      onTap: () {
                        context.push(RouteNames.withdrawalTerms);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // APP INFO section
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'APP INFO',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: _buildHelpTile(
                  context,
                  icon: Icons.info_outline,
                  iconBgColor: const Color(0xFFF0F0F2),
                  iconColor: colors.textSecondary,
                  title: 'App Version',
                  subtitle: 'v1.0.0',
                  showChevron: false,
                  onTap: () {},
                ),
              ),
              const SizedBox(height: AppSpacing.space24),
            ],
          ),
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
            fontSize: 15,
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
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
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
                        child: const Icon(Icons.mail_outline, color: Color(0xFF6B4EFF), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contact Support',
                            style: typography.titleCard.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                          Text(
                            'We are here to help 24/7',
                            style: typography.bodySmall.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                        Text('Official Support Email:', style: typography.bodySmall.copyWith(color: colors.textSecondary, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text('support@buddypartner.in', style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold, color: colors.primary, fontSize: 13.5)),
                        // const SizedBox(height: 10),
                        // Text('Official Website:', style: typography.bodySmall.copyWith(color: colors.textSecondary, fontSize: 11)),
                        // const SizedBox(height: 2),
                        // Text('www.appquires.com', style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold, color: colors.primary, fontSize: 13.5)),
                        // const SizedBox(height: 10),
                        // Text('Registered Business Entity:', style: typography.bodySmall.copyWith(color: colors.textSecondary, fontSize: 11)),
                        // const SizedBox(height: 2),
                        // Text('Appquires Global LLP', style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold, fontSize: 13.5)),
                        // const SizedBox(height: 10),
                        // Text('Registered Office Address:', style: typography.bodySmall.copyWith(color: colors.textSecondary, fontSize: 11)),
                        // const SizedBox(height: 2),
                        // Text(
                        //   'GF-001, Mauryansh Elanza, Shyamal Cross Rd, Satelite, Jodhpur Char Rasta, Satelite Police Station, Ahmadabad City, Ahmedabad- 380015, Gujarat, India',
                        //   style: typography.bodySmall.copyWith(color: colors.textPrimary, height: 1.25, fontSize: 11.5),
                        // ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
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
    (key: 'Coins & Billing', title: 'Coins, Subscription or Billing', icon: Icons.monetization_on_outlined),
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
        },
      );

      if (mounted) {
        if (response.statusCode == 200 && response.data['success'] == true) {
          AppLogger.dialogClose('Submit Report', screen: 'HelpPage');
          Navigator.pop(context);
          AppSnackBar.showSuccess(context, 'Thank you! Your bug report has been submitted to our team.');
        } else {
          final msg = response.data['error'] ?? 'Failed to submit bug report.';
          AppSnackBar.showError(context, msg.toString());
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Unable to submit report. Please check your network.');
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
                          'Report a Bug',
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

