import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/features/auth/application/auth_controller.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/widgets/cards/app_card.dart';
import 'package:dating_app/core/widgets/gradient_avatar.dart';

/// ProfilePage renders the Settings screen dashboard matching the screenshot layout exactly.
/// Displays user info card, general settings categories, support links, and logout.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final userAsync = ref.watch(authStateProvider);
    final profileAsync = ref.watch(userProfileProvider);
    
    final currentUser = userAsync.value;
    final profile = profileAsync.value;
    
    final String fullName = profile?.fullName ?? 'User';
    final String phoneNumber = currentUser?.phoneNumber ?? '';
    final String initials = getInitials(fullName);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'Settings',
              style: typography.titleCard.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Manage your preferences',
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
              // User profile header card
              
              GestureDetector(
                onTap: () {
                  context.push(RouteNames.account);
                },
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.space16),
                  child: Row(
                    children: [
                      GradientAvatar(
                        initials: initials,
                        avatarSeed: profile?.avatarSeed,
                        avatarStyle: profile?.avatarStyle,
                        gender: profile?.gender,
                        radius: 32,
                      ),
                      const SizedBox(width: AppSpacing.space16),
                      
                      // User names and phone badge
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName,
                              style: typography.titleCard.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Email pill badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3EFFF), // light lavender fill
                                borderRadius: AppRadius.pill,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.phone_outlined,
                                    color: Color(0xFF6B4EFF),
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    phoneNumber,
                                    style: TextStyle(
                                      color: const Color(0xFF6B4EFF),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: typography.bodySmall.fontFamily,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Color(0xFF6B4EFF),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // GENERAL section title
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'GENERAL',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // General Options container list
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    _buildSettingsTile(
                      context,
                      icon: Icons.card_membership_outlined,
                      iconBgColor: const Color(0xFFF5E6FF),
                      iconColor: const Color(0xFF8B5CF6),
                      title: 'My Subscription',
                      subtitle: 'Manage subscription plans & duration',
                      onTap: () {
                        context.push(RouteNames.subscribe);
                      },
                    ),
                    _buildDivider(context),
                    _buildSettingsTile(
                      context,
                      icon: Icons.person_outline,
                      iconBgColor: const Color(0xFFEFEAFF),
                      iconColor: const Color(0xFF6B4EFF),
                      title: 'Account',
                      subtitle: 'Manage your profile',
                      onTap: () {
                        context.push(RouteNames.account);
                      },
                    ),
                    _buildDivider(context),
                    _buildSettingsTile(
                      context,
                      icon: Icons.phone_outlined,
                      iconBgColor: const Color(0xFFE8F8F0),
                      iconColor: const Color(0xFF22C55E),
                      title: 'Call History',
                      subtitle: 'View your recent calls',
                      onTap: () {
                        // Navigate to history page path
                        context.push(RouteNames.history);
                      },
                    ),
                    _buildDivider(context),
                    _buildSettingsTile(
                      context,
                      icon: Icons.receipt_long_outlined,
                      iconBgColor: const Color(0xFFEAF5FF),
                      iconColor: const Color(0xFF3B82F6),
                      title: 'Transaction History',
                      subtitle: 'View your payments',
                      onTap: () {
                        context.push(RouteNames.transactionHistory);
                      },
                    ),
                    _buildDivider(context),
                    _buildSettingsTile(
                      context,
                      icon: Icons.favorite_border,
                      iconBgColor: const Color(0xFFFFEAF2),
                      iconColor: const Color(0xFFEC4899),
                      title: 'Favorites',
                      subtitle: 'View favorite telecallers',
                      onTap: () {
                        context.push(RouteNames.home); // go to favorite list
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // SUPPORT section title
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'SUPPORT',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),

              // Support Options container
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: _buildSettingsTile(
                  context,
                  icon: Icons.help_outline,
                  iconBgColor: const Color(0xFFFFF7EA),
                  iconColor: const Color(0xFFF59E0B),
                  title: 'Help & Legal Center',
                  subtitle: 'Help center, policies & legal terms',
                  onTap: () {
                    context.push(RouteNames.help);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // LEGAL section title
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

              // Legal Options container
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    _buildSettingsTile(
                      context,
                      icon: Icons.gavel_outlined,
                      iconBgColor: const Color(0xFFEAF5FF),
                      iconColor: const Color(0xFF3B82F6),
                      title: 'Terms of Service',
                      subtitle: 'User agreement & conditions',
                      onTap: () {
                        context.push(RouteNames.termsOfService);
                      },
                    ),
                    _buildDivider(context),
                    _buildSettingsTile(
                      context,
                      icon: Icons.shield_outlined,
                      iconBgColor: const Color(0xFFE8F8F0),
                      iconColor: const Color(0xFF22C55E),
                      title: 'Privacy Policy',
                      subtitle: 'Data usage & privacy rights',
                      onTap: () {
                        context.push(RouteNames.privacyPolicy);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space20),

              // Logout Option card
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: _buildSettingsTile(
                  context,
                  icon: Icons.logout,
                  iconBgColor: const Color(0xFFFFEAEA),
                  iconColor: const Color(0xFFEF4444),
                  title: 'Log out',
                  subtitle: 'Sign out of your account',
                  onTap: () {
                    _showLogoutBottomSheet(context, ref);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.space24),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutBottomSheet(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: colors.surface,
      builder: (context) {
        final typography = context.typography;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              
              // Logout Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEAEA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.logout,
                  color: Color(0xFFEF4444),
                  size: 28,
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              Text(
                'Log Out',
                style: typography.titleCard.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 12),
              
              // Subtitle description
              Text(
                'Are you sure you want to log out? You will need to sign in again to receive and make calls.',
                textAlign: TextAlign.center,
                style: typography.bodySmall.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 28),
              
              // Actions Button Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        side: BorderSide(color: colors.border),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        ref.read(authControllerProvider.notifier).signOut();
                      },
                      child: const Text(
                        'Log Out',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDivider(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 72, right: 16),
      child: Divider(color: colors.border, height: 1),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required String subtitle,
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
      trailing: Icon(
        Icons.chevron_right,
        color: colors.textSecondary.withValues(alpha: 0.5),
        size: 18,
      ),
      onTap: onTap,
    );
  }
}
