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

/// SignupPage collects user details during registration and registers them on Supabase.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  DateTime? _selectedDob;
  String? _selectedGender;
  String? _selectedLanguage;
  bool _is18Plus = false;
  
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final List<String> _genders = ['Male', 'Female', 'Other'];
  final List<String> _languages = ['English', 'Hindi', 'Spanish', 'French', 'Arabic', 'Portuguese'];

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedDob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth')),
      );
      return;
    }
    
    if (!_is18Plus) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must confirm you are 18 or older to register')),
      );
      return;
    }

    final success = await ref.read(authControllerProvider.notifier).signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _fullNameController.text.trim(),
          dob: _selectedDob!,
          gender: _selectedGender ?? 'Other',
          language: _selectedLanguage ?? 'English',
        );

    if (success && mounted) {
      // Supabase email confirmation is disabled, so we route immediately
      context.go(RouteNames.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final authState = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.space24,
            vertical: AppSpacing.space16,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create Account',
                  style: typography.headlineGreeting.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.space8),
                Text(
                  'Join LoopCall and start connecting instantly.',
                  style: typography.bodySmall.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space24),

                // Error Banner
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

                // Full Name field
                _buildLabel('Full Name'),
                TextFormField(
                  controller: _fullNameController,
                  style: typography.bodyMedium,
                  decoration: _getInputDecoration(
                    hintText: 'John Doe',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.space16),

                // Email field
                _buildLabel('Email Address'),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style: typography.bodyMedium,
                  decoration: _getInputDecoration(
                    hintText: 'john@example.com',
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                    if (!emailRegex.hasMatch(value.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.space16),

                // Password field
                _buildLabel('Password'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: typography.bodyMedium,
                  decoration: _getInputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                        color: Colors.black45,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.space16),

                // Confirm Password field
                _buildLabel('Confirm Password'),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirmPassword,
                  style: typography.bodyMedium,
                  decoration: _getInputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20,
                        color: Colors.black45,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.space16),

                // Date of Birth selection
                _buildLabel('Date of Birth'),
                GestureDetector(
                  onTap: _pickDob,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: AppRadius.md,
                      border: Border.all(color: const Color(0xFFF0F0F2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_outlined, color: Colors.black45, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          _selectedDob == null
                              ? 'Select Date of Birth'
                              : '${_selectedDob!.day}/${_selectedDob!.month}/${_selectedDob!.year}',
                          style: typography.bodyMedium.copyWith(
                            color: _selectedDob == null ? Colors.black38 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.space16),

                // Gender Selection (Dropdown)
                _buildLabel('Gender'),
                DropdownButtonFormField<String>(
                  value: _selectedGender,
                  style: typography.bodyMedium.copyWith(color: Colors.black87),
                  decoration: _getInputDecoration(
                    hintText: 'Select Gender',
                    prefixIcon: const Icon(Icons.transgender_outlined, size: 20),
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
                    });
                  },
                  validator: (val) => val == null ? 'Please select your gender' : null,
                ),
                const SizedBox(height: AppSpacing.space16),

                // Preferred Language (Dropdown)
                _buildLabel('Preferred Language'),
                DropdownButtonFormField<String>(
                  value: _selectedLanguage,
                  style: typography.bodyMedium.copyWith(color: Colors.black87),
                  decoration: _getInputDecoration(
                    hintText: 'Select Preferred Language',
                    prefixIcon: const Icon(Icons.language_outlined, size: 20),
                  ),
                  items: _languages.map((lang) {
                    return DropdownMenuItem(
                      value: lang,
                      child: Text(lang),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedLanguage = val;
                    });
                  },
                  validator: (val) => val == null ? 'Please select your language' : null,
                ),
                const SizedBox(height: AppSpacing.space24),

                // 18+ Checkbox (Required)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _is18Plus,
                        activeColor: colors.primary,
                        onChanged: (val) {
                          setState(() {
                            _is18Plus = val ?? false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'I confirm that I am 18 years of age or older. I understand that this app contains services intended for adult users.',
                        style: typography.bodySmall.copyWith(
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.space32),

                // Sign Up trigger Button
                AppPrimaryButton(
                  text: authState.isLoading ? 'Registering...' : 'Create Account',
                  onPressed: authState.isLoading ? null : _handleSignup,
                ),
                const SizedBox(height: AppSpacing.space24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String labelText) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        labelText,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: colors.textPrimary,
          fontSize: 13,
        ),
      ),
    );
  }

  InputDecoration _getInputDecoration({required String hintText, required Widget prefixIcon, Widget? suffixIcon}) {
    final colors = context.colors;
    return InputDecoration(
      hintText: hintText,
      hintStyle: context.typography.bodySmall.copyWith(color: colors.textSecondary.withOpacity(0.6)),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
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
    );
  }
}
