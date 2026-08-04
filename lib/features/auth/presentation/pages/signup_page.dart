import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/features/auth/application/auth_controller.dart';
import 'package:dating_app/features/auth/application/auth_error_mapper.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/widgets/buttons/app_primary_button.dart';
import 'package:dating_app/core/constants/avatar_catalog.dart';
import 'package:dating_app/core/widgets/app_avatar.dart';
import 'package:dating_app/core/utils/app_logger.dart';

/// SignupPage is the multi-step Profile Onboarding Page.
/// Step 1: Profile details (Full Name, Date of Birth, Gender, Language, Terms).
/// Step 2: Avatar selection (Dedicated page for picking profile avatar).
/// Step 3: Telecaller Opt-In selection ("Join as Telecaller?" — Female users only).
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  
  int _currentStep = 1; // 1 = Profile Details, 2 = Avatar Selection, 3 = Telecaller Opt-In

  final _fullNameController = TextEditingController();
  DateTime? _selectedDob;
  String? _selectedGender;
  String? _selectedLanguage;
  String? _selectedAvatarSeed;
  bool? _selectedIsTelecaller;
  bool _is18Plus = false;
  bool _acceptedTermsAndPrivacy = false;
  
  final List<String> _genders = ['Male', 'Female', 'Other'];
  final List<String> _languages = ['English', 'Hindi', 'Spanish', 'French', 'Arabic', 'Portuguese'];

  int get _totalSteps => 2;

  @override
  void dispose() {
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 100);
    final lastDate = DateTime(now.year - 18); // Must be 18 or older
    
    final picked = await showDatePicker(
      context: context,
      initialDate: lastDate,
      firstDate: firstDate,
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: context.colors.primary,
              onPrimary: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDob = picked;
      });
    }
  }

  void _handleNextToAvatarStep() {
    AppLogger.button('Next Step: Choose Avatar', screen: 'SignUpPage');
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedDob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth')),
      );
      return;
    }

    if (_selectedGender == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your gender')),
      );
      return;
    }

    if (_selectedLanguage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your language')),
      );
      return;
    }
    
    if (!_is18Plus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must confirm you are 18 or older to register')),
      );
      return;
    }

    if (!_acceptedTermsAndPrivacy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must agree to the Terms of Service and Privacy Policy to register')),
      );
      return;
    }

    // Set default avatar seed for the chosen gender if not selected yet
    final availableSeeds = AvatarCatalog.getSeedsForGender(_selectedGender);
    if (_selectedAvatarSeed == null || !availableSeeds.contains(_selectedAvatarSeed)) {
      _selectedAvatarSeed = availableSeeds.isNotEmpty ? availableSeeds[0] : null;
    }

    setState(() {
      _currentStep = 2;
    });
  }

  void _handleNextFromAvatarStep() {
    if (_selectedAvatarSeed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an avatar to continue')),
      );
      return;
    }

    _handleFinalSubmission();
  }

  Future<void> _handleFinalSubmission() async {
    if (_selectedAvatarSeed == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an avatar to complete setup')),
      );
      return;
    }

    final success = await ref.read(authControllerProvider.notifier).completeProfile(
          fullName: _fullNameController.text.trim(),
          dob: _selectedDob!,
          gender: _selectedGender!,
          language: _selectedLanguage!,
          avatarSeed: _selectedAvatarSeed,
          avatarStyle: 'avataaars',
          isTelecaller: null,
        );

    if (success && mounted) {
      context.go(RouteNames.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: _currentStep == 2
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                onPressed: () {
                  setState(() {
                    _currentStep = 1;
                  });
                },
              ),
              centerTitle: true,
              title: Text(
                'Step 2 of $_totalSteps',
                style: typography.bodySmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space24,
            vertical: AppSpacing.space24,
          ),
          child: _currentStep == 1
              ? _buildStep1ProfileDetails(colors, typography, authState)
              : _buildStep2AvatarPicker(colors, typography, authState),
        ),
      ),
    );
  }

  /// Step 1 UI: Profile details
  Widget _buildStep1ProfileDetails(dynamic colors, dynamic typography, AsyncValue<void> authState) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                Image.asset(
                  'assets/images/app_logo.png',
                  width: 100,
                  height: 100,
                ),
                const SizedBox(height: 8),
                Text(
                  'BuddyPartner',
                  style: typography.displayWordmark.copyWith(
                    color: colors.primary,
                    fontSize: 28.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space24),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Complete Your Profile',
                style: typography.headlineGreeting.copyWith(
                  fontSize: 22.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.pill,
                ),
                child: Text(
                  'Step 1 of $_totalSteps',
                  style: typography.bodySmall.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space8),
          Text(
            'Enter your basic details to start meeting people.',
            style: typography.bodySmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space24),

          // Error message banner
          if (authState is AsyncError) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.space12),
              margin: const EdgeInsets.only(bottom: AppSpacing.space16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEAEA),
                borderRadius: AppRadius.md,
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AuthErrorMapper.mapMessage(authState.error),
                      style: typography.bodySmall.copyWith(
                        color: const Color(0xFFEF4444),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Full Name
          Text(
            'Full Name',
            style: typography.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _fullNameController,
            style: typography.bodyMedium,
            decoration: InputDecoration(
              hintText: 'John Doe',
              hintStyle: typography.bodySmall.copyWith(color: colors.textSecondary.withValues(alpha: 0.6)),
              prefixIcon: const Icon(Icons.person_outline, size: 20),
              filled: true,
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space16,
                vertical: AppSpacing.space12,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(color: colors.primary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: const BorderSide(color: Color(0xFFEF4444)),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your full name';
              }
              if (value.trim().length < 3) {
                return 'Name must be at least 3 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space20),

          // Date of Birth
          Text(
            'Date of Birth',
            style: typography.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _pickDob,
            borderRadius: AppRadius.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space16,
                vertical: AppSpacing.space12,
              ),
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
                    _selectedDob == null
                        ? 'Select Date of Birth'
                        : '${_selectedDob!.day}/${_selectedDob!.month}/${_selectedDob!.year}',
                    style: typography.bodyMedium.copyWith(
                      color: _selectedDob == null ? colors.textSecondary.withValues(alpha: 0.6) : colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space20),

          // Gender
          Text(
            'Gender',
            style: typography.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedGender,
            style: typography.bodyMedium.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.transgender_outlined, size: 20),
              filled: true,
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space16,
                vertical: AppSpacing.space12,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(color: colors.border),
              ),
            ),
            items: _genders.map((gender) {
              return DropdownMenuItem(
                value: gender,
                child: Text(gender),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                _selectedGender = val;
                final availableSeeds = AvatarCatalog.getSeedsForGender(val);
                if (_selectedAvatarSeed == null || !availableSeeds.contains(_selectedAvatarSeed)) {
                  _selectedAvatarSeed = availableSeeds.isNotEmpty ? availableSeeds[0] : null;
                }
              });
            },
            validator: (value) => value == null ? 'Please select your gender' : null,
          ),
          const SizedBox(height: AppSpacing.space20),

          // Preferred Language
          Text(
            'Preferred Language',
            style: typography.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selectedLanguage,
            style: typography.bodyMedium.copyWith(color: colors.textPrimary),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.language_outlined, size: 20),
              filled: true,
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space16,
                vertical: AppSpacing.space12,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(color: colors.border),
              ),
            ),
            items: _languages.map((lang) {
              return DropdownMenuItem(
                value: lang,
                child: Text(lang),
              );
            }).toList(),
            onChanged: (val) => setState(() => _selectedLanguage = val),
            validator: (value) => value == null ? 'Please select your language' : null,
          ),
          const SizedBox(height: AppSpacing.space20),

          // 18+ Checkbox
          CheckboxListTile(
            title: Text(
              'I confirm that I am 18 years of age or older.',
              style: typography.bodySmall.copyWith(color: colors.textSecondary),
            ),
            value: _is18Plus,
            activeColor: colors.primary,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) => setState(() => _is18Plus = val ?? false),
          ),
          const SizedBox(height: AppSpacing.space8),

          // Terms of Service & Privacy Policy Checkbox
          CheckboxListTile(
            title: Text.rich(
              TextSpan(
                style: typography.bodySmall.copyWith(color: colors.textSecondary),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () => context.push(RouteNames.termsOfService),
                      child: Text(
                        'Terms of Service',
                        style: typography.bodySmall.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: ' and '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: GestureDetector(
                      onTap: () => context.push(RouteNames.privacyPolicy),
                      child: Text(
                        'Privacy Policy',
                        style: typography.bodySmall.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
            value: _acceptedTermsAndPrivacy,
            activeColor: colors.primary,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) => setState(() => _acceptedTermsAndPrivacy = val ?? false),
          ),
          const SizedBox(height: AppSpacing.space32),

          AppPrimaryButton(
            text: 'Continue to Avatar Selection',
            onPressed: _handleNextToAvatarStep,
          ),
        ],
      ),
    );
  }

  /// Step 2 UI: Dedicated Avatar Picker Page
  Widget _buildStep2AvatarPicker(dynamic colors, dynamic typography, AsyncValue<void> authState) {
    final availableSeeds = AvatarCatalog.getSeedsForGender(_selectedGender);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Choose Your Avatar',
          style: typography.headlineGreeting.copyWith(
            fontSize: 24.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Select your favorite avatar for your $_selectedGender profile.',
          style: typography.bodySmall.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.space24),

        // Live Selected Avatar Preview Card
        Container(
          padding: const EdgeInsets.all(AppSpacing.space16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.08),
                blurRadius: 16,
                spreadRadius: 2,
              )
            ],
          ),
          child: Row(
            children: [
              AppAvatar(
                avatarSeed: _selectedAvatarSeed,
                gender: _selectedGender,
                radius: 36,
                isSelected: true,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _fullNameController.text.trim().isNotEmpty
                          ? _fullNameController.text.trim()
                          : 'Your Name',
                      style: typography.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18.0,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _selectedGender ?? 'Profile',
                            style: typography.bodySmall.copyWith(
                              color: colors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 11.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedLanguage ?? '',
                          style: typography.bodySmall.copyWith(
                            color: colors.textSecondary,
                            fontSize: 12.0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space24),

        // Avatar Grid Picker
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Available Avatars',
            style: typography.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),

        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.0,
          ),
          itemCount: availableSeeds.length,
          itemBuilder: (context, index) {
            final seed = availableSeeds[index];
            final isSelected = seed == _selectedAvatarSeed;
            return AppAvatar(
              avatarSeed: seed,
              gender: _selectedGender,
              radius: 28,
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  _selectedAvatarSeed = seed;
                });
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.space32),

        AppPrimaryButton(
          text: authState.isLoading ? 'Saving Profile...' : 'Complete Setup',
          onPressed: authState.isLoading ? null : _handleNextFromAvatarStep,
        ),
      ],
    );
  }
}
