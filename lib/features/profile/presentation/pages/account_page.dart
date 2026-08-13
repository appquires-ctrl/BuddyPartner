import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/features/auth/application/auth_controller.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/core/constants/avatar_catalog.dart';
import 'package:buddypartner/core/widgets/app_avatar.dart';
import 'package:buddypartner/core/utils/app_logger.dart';

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

    final String rawProfileName = profile?.fullName ?? '';
    final String fullName = (rawProfileName.isNotEmpty && rawProfileName != 'User')
        ? rawProfileName
        : (currentUser?.fullName != null && currentUser!.fullName!.trim().isNotEmpty
            ? currentUser.fullName!.trim()
            : 'User');
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
                avatarSeed: profile?.avatarSeed,
                avatarStyle: profile?.avatarStyle,
                gender: profile?.gender,
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

              // Edit Profile Button
              GestureDetector(
                onTap: () {
                  _showEditProfileModal(context, ref, profile);
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
                      label: 'Whatsapp Number',
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

  void _showEditProfileModal(BuildContext context, WidgetRef ref, dynamic profile) {
    final colors = context.colors;
    final typography = context.typography;

    final nameController = TextEditingController(text: profile?.fullName ?? '');
    DateTime selectedDob = profile?.dob ?? DateTime.now().subtract(const Duration(days: 365 * 20));
    String selectedGender = profile?.gender ?? 'Male';
    if (!['Male', 'Female', 'Other'].contains(selectedGender)) {
      if (selectedGender.toLowerCase() == 'male') {
        selectedGender = 'Male';
      } else if (selectedGender.toLowerCase() == 'female') {
        selectedGender = 'Female';
      } else {
        selectedGender = 'Other';
      }
    }
    String selectedLanguage = profile?.language ?? 'English';
    String? selectedAvatarSeed = profile?.avatarSeed ?? AvatarCatalog.getSeedsForGender(selectedGender).first;
    final List<String> languages = ['English', 'Hindi', 'Spanish', 'French', 'Arabic', 'Portuguese'];
    if (!languages.contains(selectedLanguage)) {
      languages.add(selectedLanguage);
    }

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
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
                    Text(
                      'Edit Profile',
                      style: typography.titleCard.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Update your personal information',
                      style: typography.bodySmall.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 20),

                    // Full Name
                    Text('Full Name', style: typography.bodySmall.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameController,
                      style: typography.bodyMedium,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person_outline, size: 20),
                        filled: true,
                        fillColor: colors.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide(color: colors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide(color: colors.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide(color: colors.primary, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Date of Birth
                    Text('Date of Birth', style: typography.bodySmall.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () async {
                        final now = DateTime.now();
                        final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);
                        final initialDate = selectedDob.isBefore(eighteenYearsAgo) ? selectedDob : eighteenYearsAgo;
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: initialDate,
                          firstDate: DateTime(now.year - 100),
                          lastDate: eighteenYearsAgo,
                        );
                        if (picked != null) {
                          setModalState(() => selectedDob = picked);
                        }
                      },
                      borderRadius: AppRadius.md,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: AppRadius.md,
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 20, color: colors.textSecondary),
                            const SizedBox(width: 12),
                            Text(
                              '${selectedDob.day}/${selectedDob.month}/${selectedDob.year}',
                              style: typography.bodyMedium.copyWith(color: colors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Language
                    Text('Language', style: typography.bodySmall.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      initialValue: selectedLanguage,
                      style: typography.bodyMedium.copyWith(color: colors.textPrimary),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.language_outlined, size: 20),
                        filled: true,
                        fillColor: colors.surface,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide(color: colors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: AppRadius.md, borderSide: BorderSide(color: colors.border)),
                      ),
                      items: languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedLanguage = val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Avatar Selection Grid
                    Text('Choose Profile Avatar', style: typography.bodySmall.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.0,
                      ),
                      itemCount: AvatarCatalog.getSeedsForGender(selectedGender).length,
                      itemBuilder: (context, index) {
                        final seed = AvatarCatalog.getSeedsForGender(selectedGender)[index];
                        final isSelected = seed == selectedAvatarSeed;
                        return AppAvatar(
                          avatarSeed: seed,
                          gender: selectedGender,
                          radius: 26,
                          isSelected: isSelected,
                          onTap: () {
                            setModalState(() {
                              selectedAvatarSeed = seed;
                            });
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 24),

                    // Save Changes button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () async {
                          AppLogger.button('Save Profile Changes', screen: 'AccountPage');
                          final nameText = nameController.text.trim();
                          if (nameText.isEmpty || nameText.length < 3) {
                            AppSnackBar.showError(context, 'Please enter a valid full name (at least 3 characters)');
                            return;
                          }

                          final now = DateTime.now();
                          int age = now.year - selectedDob.year;
                          if (now.month < selectedDob.month || (now.month == selectedDob.month && now.day < selectedDob.day)) {
                            age--;
                          }

                          if (age < 18) {
                            AppSnackBar.showError(context, 'You must be 18 years or older to use this app.');
                            return;
                          }

                          Navigator.pop(context);
                          final success = await ref.read(authControllerProvider.notifier).completeProfile(
                                fullName: nameText,
                                dob: selectedDob,
                                gender: selectedGender,
                                language: selectedLanguage,
                                avatarSeed: selectedAvatarSeed,
                                avatarStyle: 'avataaars',
                              );

                          if (context.mounted) {
                            if (success) {
                              AppSnackBar.showSuccess(context, 'Profile updated successfully!');
                            } else {
                              AppSnackBar.showError(context, 'Failed to update profile. Please try again.');
                            }
                          }
                        },
                        child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
