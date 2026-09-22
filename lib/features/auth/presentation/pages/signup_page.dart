import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/features/auth/application/auth_controller.dart';
import 'package:buddypartner/features/auth/application/auth_error_mapper.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/core/widgets/buttons/app_primary_button.dart';
import 'package:buddypartner/core/constants/avatar_catalog.dart';
import 'package:buddypartner/core/widgets/app_avatar.dart';
import 'package:buddypartner/core/widgets/avatar_grid_picker.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';

/// SignupPage is the multi-step Profile Onboarding Page.
/// Step 1: Basic Details (Full Name, Date of Birth, Gender, Terms).
/// Step 2: Account Details (Unique Username, Password, Confirm Password).
/// Step 3: Avatar Selection (Dedicated page for picking profile avatar).
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  static final RegExp usernameAllowedRegex = RegExp(r'^[a-z0-9._]+$');
  static final RegExp consecutiveSymbolsRegex = RegExp(r'[._]{2,}');
  static final Set<String> reservedUsernames = {
    'admin', 'administrator', 'support', 'help', 'buddypartner',
    'official', 'null', 'undefined', 'system', 'root', 'moderator',
    'api', 'auth', 'user', 'users', 'me'
  };

  /// Validates format according to Instagram username conventions.
  static String? validateUsernameFormat(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please choose a username';
    }
    final normalized = value.trim().toLowerCase();
    if (normalized.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (normalized.length > 20) {
      return 'Username must be at most 20 characters';
    }
    if (!RegExp(r'^[a-z0-9]').hasMatch(normalized)) {
      return 'Username must start with a letter or number';
    }
    if (!RegExp(r'[a-z0-9]$').hasMatch(normalized)) {
      return 'Username must end with a letter or number';
    }
    if (!usernameAllowedRegex.hasMatch(normalized)) {
      return 'Username can only contain letters, numbers, . and _';
    }
    if (consecutiveSymbolsRegex.hasMatch(normalized)) {
      return 'Username cannot contain consecutive dots or underscores';
    }
    if (reservedUsernames.contains(normalized)) {
      return 'it already exist fix it';
    }
    if (RegExp(r'^\d+$').hasMatch(normalized)) {
      return 'Username cannot consist solely of numbers';
    }
    return null;
  }

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _basicDetailsFormKey = GlobalKey<FormState>();
  final _accountDetailsFormKey = GlobalKey<FormState>();
  
  int _currentStep = 1; // 1 = Basic Details, 2 = Account Details, 3 = Avatar Selection
  int get _totalSteps => 3;

  final _fullNameController = TextEditingController();
  final _userNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _userNameInlineError;
  bool _isCheckingUsername = false;

  DateTime? _selectedDob;
  String? _selectedGender;
  String? _selectedAvatarSeed;
  bool _is18Plus = false;
  bool _acceptedTermsAndPrivacy = false;
  
  final List<String> _genders = ['Male', 'Female', 'Other'];

  @override
  void dispose() {
    _fullNameController.dispose();
    _userNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateUsernameFormat(String? value) => SignupPage.validateUsernameFormat(value);

  int _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 100);
    final eighteenYearsAgo = DateTime(now.year - 18, now.month, now.day);
    final initialDate = (_selectedDob != null && _selectedDob!.isBefore(eighteenYearsAgo))
        ? _selectedDob!
        : eighteenYearsAgo;
    
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: eighteenYearsAgo,
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

    if (!mounted) return;

    if (picked != null) {
      if (_calculateAge(picked) < 18) {
        AppSnackBar.showError(context, 'You must be 18 years or older to use this app.');
        return;
      }
      setState(() {
        _selectedDob = picked;
      });
    }
  }

  void _handleNextToAccountStep() {
    AppLogger.button('Next Step: Account Details', screen: 'SignUpPage');
    if (!_basicDetailsFormKey.currentState!.validate()) return;

    if (_selectedDob == null) {
      AppSnackBar.showError(context, 'Please select your date of birth');
      return;
    }

    if (_calculateAge(_selectedDob!) < 18) {
      AppSnackBar.showError(context, 'You must be 18 years or older to use this app.');
      return;
    }

    if (_selectedGender == null) {
      AppSnackBar.showError(context, 'Please select your gender');
      return;
    }
    
    if (!_is18Plus) {
      AppSnackBar.showError(context, 'You must confirm you are 18 or older to register');
      return;
    }

    if (!_acceptedTermsAndPrivacy) {
      AppSnackBar.showError(context, 'You must agree to the Terms of Service and Privacy Policy to register');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _currentStep = 2;
    });
  }

  Future<void> _handleNextToAvatarStep() async {
    AppLogger.button('Next Step: Choose Avatar', screen: 'SignUpPage');
    if (!_accountDetailsFormKey.currentState!.validate()) return;
    
    final formatErr = _validateUsernameFormat(_userNameController.text);
    if (formatErr != null) {
      setState(() {
        _userNameInlineError = formatErr;
      });
      return;
    }

    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (password.isEmpty || password.length < 8) {
      AppSnackBar.showError(context, 'Password must be at least 8 characters long');
      return;
    }

    if (password != confirmPassword) {
      AppSnackBar.showError(context, 'Passwords do not match');
      return;
    }

    FocusScope.of(context).unfocus();

    // Check username availability against backend API before advancing
    setState(() {
      _isCheckingUsername = true;
      _userNameInlineError = null;
    });

    final checkResult = await ref
        .read(authControllerProvider.notifier)
        .checkUsernameAvailable(_userNameController.text.trim().toLowerCase());

    if (!mounted) return;

    setState(() {
      _isCheckingUsername = false;
    });

    if (checkResult['available'] != true) {
      setState(() {
        _userNameInlineError = checkResult['message'] as String? ?? 'it already exist fix it';
      });
      return;
    }

    // Set default avatar seed for the chosen gender if not selected yet
    final availableSeeds = AvatarCatalog.getSeedsForGender(_selectedGender);
    if (_selectedAvatarSeed == null || !availableSeeds.contains(_selectedAvatarSeed)) {
      _selectedAvatarSeed = availableSeeds.isNotEmpty ? availableSeeds[0] : null;
    }

    setState(() {
      _userNameInlineError = null;
      _currentStep = 3;
    });
  }

  void _handleNextFromAvatarStep() {
    if (_selectedAvatarSeed == null) {
      AppSnackBar.showError(context, 'Please select an avatar to continue');
      return;
    }

    _handleFinalSubmission();
  }

  Future<void> _handleFinalSubmission() async {
    if (_selectedAvatarSeed == null) {
      AppSnackBar.showError(context, 'Please select an avatar to complete setup');
      return;
    }

    final success = await ref.read(authControllerProvider.notifier).completeProfile(
          fullName: _fullNameController.text.trim(),
          userName: _userNameController.text.trim().toLowerCase(),
          password: _passwordController.text.trim(),
          dob: _selectedDob!,
          gender: _selectedGender!,
          language: 'English',
          avatarSeed: _selectedAvatarSeed,
          avatarStyle: 'avataaars',
        );

    if (success && mounted) {
      context.go(RouteNames.home);
    } else if (mounted) {
      // If error was username collision, return to Step 2 (Account Details) and highlight inline error
      final authError = ref.read(authControllerProvider).error;
      final errorMsg = authError?.toString() ?? '';
      if (errorMsg.contains('it already exist fix it') || errorMsg.contains('USERNAME_TAKEN')) {
        setState(() {
          _currentStep = 2;
          _userNameInlineError = 'it already exist fix it';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final authState = ref.watch(authControllerProvider);

    return PopScope(
      canPop: _currentStep == 1,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep > 1) {
          FocusScope.of(context).unfocus();
          setState(() {
            _currentStep--;
          });
        }
      },
      child: Scaffold(
        appBar: _currentStep > 1
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    setState(() {
                      _currentStep--;
                    });
                  },
                ),
              )
            : null,
        body: SafeArea(
          child: SingleChildScrollView(
            key: ValueKey<int>(_currentStep),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space24,
              vertical: AppSpacing.space24,
            ),
            child: _buildCurrentStep(colors, typography, authState),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep(dynamic colors, dynamic typography, AsyncValue<void> authState) {
    switch (_currentStep) {
      case 1:
        return _buildStep1BasicDetails(colors, typography, authState);
      case 2:
        return _buildStep2AccountDetails(colors, typography, authState);
      case 3:
      default:
        return _buildStep3AvatarPicker(colors, typography, authState);
    }
  }

  /// Step 1 UI: Basic Details (Name, DOB, Gender, Terms)
  Widget _buildStep1BasicDetails(dynamic colors, dynamic typography, AsyncValue<void> authState) {
    return Form(
      key: _basicDetailsFormKey,
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
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Buddy',
                        style: typography.displayWordmark.copyWith(
                          color: const Color(0xFF1E4FAE), // Blue
                          fontSize: 32.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.0,
                          height: 1.0,
                        ),
                      ),
                      TextSpan(
                        text: 'Partner',
                        style: typography.displayWordmark.copyWith(
                          color: const Color(0xFFE91E63), // Pink
                          fontSize: 32.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.0,
                          height: 1.0,
                        ),
                      ),
                    ],
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
                'Basic Details',
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
            'Enter your personal details to get started.',
            style: typography.bodySmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.space24),

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
            initialValue: _selectedGender,
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
            text: 'Continue to Account Details',
            onPressed: _handleNextToAccountStep,
          ),
        ],
      ),
    );
  }

  /// Step 2 UI: Account Details (Username, Password, Confirm Password)
  Widget _buildStep2AccountDetails(dynamic colors, dynamic typography, AsyncValue<void> authState) {
    return Form(
      key: _accountDetailsFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Account Details',
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
                  'Step 2 of $_totalSteps',
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
            'Create a unique handle and password for your account.',
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

          // Username Field (Instagram-style)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Username',
                style: typography.bodySmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                'Unique handle',
                style: typography.bodySmall.copyWith(
                  fontSize: 11.0,
                  color: colors.textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _userNameController,
            style: typography.bodyMedium,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
              LengthLimitingTextInputFormatter(20),
              TextInputFormatter.withFunction((oldVal, newVal) {
                return newVal.copyWith(text: newVal.text.toLowerCase());
              }),
            ],
            onChanged: (_) {
              if (_userNameInlineError != null) {
                setState(() => _userNameInlineError = null);
              }
            },
            decoration: InputDecoration(
              hintText: 'Choose a username',
              hintStyle: typography.bodySmall.copyWith(color: colors.textSecondary.withValues(alpha: 0.6)),
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                child: Text(
                  '@',
                  style: typography.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
              filled: true,
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space16,
                vertical: AppSpacing.space12,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(
                  color: _userNameInlineError != null ? const Color(0xFFEF4444) : colors.border,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(
                  color: _userNameInlineError != null ? const Color(0xFFEF4444) : colors.border,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.md,
                borderSide: BorderSide(
                  color: _userNameInlineError != null ? const Color(0xFFEF4444) : colors.primary,
                  width: 1.5,
                ),
              ),
            ),
            validator: _validateUsernameFormat,
          ),
          if (_userNameInlineError != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 4.0),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFEF4444)),
                  const SizedBox(width: 4),
                  Text(
                    _userNameInlineError!,
                    style: typography.bodySmall.copyWith(
                      color: const Color(0xFFEF4444),
                      fontSize: 12.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.space20),

          // Password Field
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Password',
                style: typography.bodySmall.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                'Min 8 characters',
                style: typography.bodySmall.copyWith(
                  fontSize: 11.0,
                  color: colors.textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: typography.bodyMedium,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'Create a strong password',
              hintStyle: typography.bodySmall.copyWith(color: colors.textSecondary.withValues(alpha: 0.6)),
              prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: colors.textSecondary),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: colors.textSecondary,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
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
            ),
            validator: (value) {
              if (value == null || value.trim().length < 8) {
                return 'Password must be at least 8 characters long';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space20),

          // Confirm Password Field
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Confirm Password',
              style: typography.bodySmall.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            style: typography.bodyMedium,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'Re-enter your password',
              hintStyle: typography.bodySmall.copyWith(color: colors.textSecondary.withValues(alpha: 0.6)),
              prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: colors.textSecondary),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: colors.textSecondary,
                ),
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
              ),
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
            ),
            validator: (value) {
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.space32),

          AppPrimaryButton(
            text: 'Continue to Avatar Selection',
            isLoading: _isCheckingUsername,
            onPressed: _isCheckingUsername ? null : _handleNextToAvatarStep,
          ),
        ],
      ),
    );
  }

  /// Step 3 UI: Dedicated Avatar Picker Page
  Widget _buildStep3AvatarPicker(dynamic colors, dynamic typography, AsyncValue<void> authState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Choose Your Avatar',
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
                'Step 3 of $_totalSteps',
                style: typography.bodySmall.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Select your favorite avatar for your ${_selectedGender ?? ''} profile.',
            style: typography.bodySmall.copyWith(color: colors.textSecondary),
          ),
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
                    if (_userNameController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${_userNameController.text.trim().toLowerCase()}',
                        style: typography.bodySmall.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.0,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
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
            'Choose Profile Avatar',
            style: typography.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 12),

        AvatarGridPicker(
          selectedGender: _selectedGender,
          selectedAvatarSeed: _selectedAvatarSeed,
          radius: 28,
          onAvatarSelected: (seed) {
            setState(() {
              _selectedAvatarSeed = seed;
            });
          },
        ),
        const SizedBox(height: AppSpacing.space32),

        AppPrimaryButton(
          text: authState.isLoading ? 'Saving Profile...' : 'Complete Setup',
          isLoading: authState.isLoading,
          onPressed: authState.isLoading ? null : _handleNextFromAvatarStep,
        ),
      ],
    );
  }
}
