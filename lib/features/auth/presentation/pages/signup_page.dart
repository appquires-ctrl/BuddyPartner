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

/// SignupPage is repurposed as the Profile Onboarding/Completion Setup Page.
/// It collects profile details (Full Name, Date of Birth, Gender, Language)
/// for users who verified their OTP but do not have metadata populated.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  
  final _fullNameController = TextEditingController();
  DateTime? _selectedDob;
  String? _selectedGender;
  String? _selectedLanguage;
  bool _is18Plus = false;
  
  final List<String> _genders = ['Male', 'Female', 'Other'];
  final List<String> _languages = ['English', 'Hindi', 'Spanish', 'French', 'Arabic', 'Portuguese'];

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

  Future<void> _handleCompleteProfile() async {
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

    final success = await ref.read(authControllerProvider.notifier).completeProfile(
          fullName: _fullNameController.text.trim(),
          dob: _selectedDob!,
          gender: _selectedGender!,
          language: _selectedLanguage!,
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space24,
            vertical: AppSpacing.space32,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'LoopCall',
                    style: typography.displayWordmark.copyWith(
                      color: colors.primary,
                      fontSize: 32,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space32),
                
                Text(
                  'Complete Your Profile',
                  style: typography.headlineGreeting.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.space8),
                Text(
                  'Let strangers know a bit about you before connecting.',
                  style: typography.bodySmall.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space24),

                // Error message banner
                if (authState.hasError) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.space12),
                    margin: const EdgeInsets.only(bottom: AppSpacing.space16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEAEA),
                      borderRadius: AppRadius.md,
                      border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AuthErrorMapper.mapMessage(authState.error!),
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
                    hintStyle: typography.bodySmall.copyWith(color: colors.textSecondary.withOpacity(0.6)),
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
                            color: _selectedDob == null ? colors.textSecondary.withOpacity(0.6) : colors.textPrimary,
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
                  onChanged: (val) => setState(() => _selectedGender = val),
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
                const SizedBox(height: AppSpacing.space24),

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
                const SizedBox(height: AppSpacing.space32),

                AppPrimaryButton(
                  text: authState.isLoading ? 'Saving Profile...' : 'Complete Setup',
                  onPressed: authState.isLoading ? null : _handleCompleteProfile,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
