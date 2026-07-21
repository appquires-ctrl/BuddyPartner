import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/widgets/gradient_avatar.dart';

/// AccountPage renders the profile details page.
/// Displays user information dynamically loaded from Supabase profile state.
class AccountPage extends ConsumerWidget {
  const AccountPage({super.key});

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
    final String gender = profile?.gender.toUpperCase() ?? 'OTHER';
    
    // Format date of birth: "DD Month YYYY"
    String dobStr = 'Not Provided';
    if (profile != null) {
      final dob = profile.dob;
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      dobStr = '${dob.day} ${months[dob.month - 1]} ${dob.year}';
    }
    final String language = profile?.language ?? 'English';

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
              'Account',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Manage your profile',
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),

              GradientAvatar(
                initials: initials,
                radius: 60,
              ),
              const SizedBox(height: AppSpacing.space16),

              // Dynamic User details name
              Text(
                fullName,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                phoneNumber,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: AppSpacing.space16),

              // Edit Profile Button (Placeholder)
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Edit Profile tapped')),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3EFFF), // light lavender fill
                    borderRadius: AppRadius.pill,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.edit,
                        color: Color(0xFF6B4EFF),
                        size: 14,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Edit Profile',
                        style: TextStyle(
                          color: Color(0xFF6B4EFF),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // PERSONAL INFORMATION section header
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'PERSONAL INFORMATION',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),

              // Details card list container populated dynamically
              Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    _buildInfoTile(
                      context,
                      icon: Icons.person_outline,
                      iconBgColor: const Color(0xFFEFEAFF),
                      iconColor: const Color(0xFF6B4EFF),
                      label: 'Full Name',
                      value: fullName,
                    ),
                    _buildDivider(context),
                    _buildInfoTile(
                      context,
                      icon: Icons.phone_outlined,
                      iconBgColor: const Color(0xFFE8F8F0),
                      iconColor: const Color(0xFF22C55E),
                      label: 'Phone Number',
                      value: phoneNumber,
                    ),
                    _buildDivider(context),
                    _buildInfoTile(
                      context,
                      icon: Icons.transgender_outlined,
                      iconBgColor: const Color(0xFFFFEAF2),
                      iconColor: const Color(0xFFEC4899),
                      label: 'Gender',
                      value: gender,
                    ),
                    _buildDivider(context),
                    _buildInfoTile(
                      context,
                      icon: Icons.calendar_today_outlined,
                      iconBgColor: const Color(0xFFFFF7EA),
                      iconColor: const Color(0xFFF59E0B),
                      label: 'Date of Birth',
                      value: dobStr,
                    ),
                    _buildDivider(context),
                    _buildInfoTile(
                      context,
                      icon: Icons.language,
                      iconBgColor: const Color(0xFFEAF5FF),
                      iconColor: const Color(0xFF3B82F6),
                      label: 'Language',
                      value: language,
                    ),
                  ],
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

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Icon Container box
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 16),
          
          // Data column fields
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
