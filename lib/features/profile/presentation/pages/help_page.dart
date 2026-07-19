import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';

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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Contact support clicked')),
                        );
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Report a bug clicked')),
                        );
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
                  'LEGAL',
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
                      icon: Icons.shield_outlined,
                      iconBgColor: const Color(0xFFE8F8F0),
                      iconColor: const Color(0xFF22C55E),
                      title: 'Privacy Policy',
                      subtitle: 'How we handle your data',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Privacy Policy clicked')),
                        );
                      },
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.credit_card_outlined,
                      iconBgColor: const Color(0xFFFFF7EA),
                      iconColor: const Color(0xFFF59E0B),
                      title: 'Payment Policy',
                      subtitle: 'Billing, refunds, and coin usage',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Payment Policy clicked')),
                        );
                      },
                    ),
                    _buildDivider(context),
                    _buildHelpTile(
                      context,
                      icon: Icons.description_outlined,
                      iconBgColor: const Color(0xFFEAF5FF),
                      iconColor: const Color(0xFF3B82F6),
                      title: 'Terms & Conditions',
                      subtitle: 'Rules and guidelines',
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Terms & Conditions clicked')),
                        );
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
    return ListTile(
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
              color: colors.textSecondary.withOpacity(0.5),
              size: 18,
            )
          : null,
      onTap: onTap,
    );
  }
}
