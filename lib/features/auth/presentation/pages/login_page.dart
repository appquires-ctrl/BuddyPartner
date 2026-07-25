import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/features/auth/application/auth_controller.dart';
import 'package:dating_app/features/auth/application/auth_error_mapper.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/widgets/buttons/app_primary_button.dart';

/// LoginPage handles phone number entry & 6-digit OTP verification
/// matching the exact design mockup.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final String _selectedCountryCode = '+91';
  bool _otpSent = false;
  
  // 6-digit OTP controllers & focus nodes
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  Timer? _resendTimer;
  int _secondsRemaining = 29;
  bool _canResend = false;

  @override
  void dispose() {
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _secondsRemaining = 29;
      _canResend = false;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        if (mounted) {
          setState(() {
            _canResend = true;
          });
        }
        timer.cancel();
      } else {
        if (mounted) {
          setState(() {
            _secondsRemaining--;
          });
        }
      }
    });
  }

  String get _fullPhoneNumber {
    final rawPhone = _phoneController.text.trim();
    if (rawPhone.startsWith('+')) return rawPhone;
    return '$_selectedCountryCode $rawPhone';
  }

  String get _formattedDisplayPhone {
    final rawPhone = _phoneController.text.trim().replaceAll(' ', '');
    if (rawPhone.length == 10) {
      return '$_selectedCountryCode ${rawPhone.substring(0, 5)} ${rawPhone.substring(5)}';
    }
    return '$_selectedCountryCode $rawPhone';
  }

  String get _enteredOtp => _otpControllers.map((c) => c.text).join();

  Future<void> _handleSendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final phoneToSend = _fullPhoneNumber.replaceAll(' ', '');
    final success = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(phoneToSend);

    if (success && mounted) {
      setState(() {
        _otpSent = true;
      });
      _startResendTimer();
      // Focus first OTP field
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _otpFocusNodes[0].requestFocus();
        }
      });
    }
  }

  Future<void> _handleVerifyOtp() async {
    final otp = _enteredOtp;
    if (otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter all 6 digits of the verification code.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final phoneToSend = _fullPhoneNumber.replaceAll(' ', '');
    final result = await ref
        .read(authControllerProvider.notifier)
        .verifyOtp(phoneToSend, otp);

    if (result['success'] == true && mounted) {
      final isProfileComplete = result['isProfileComplete'] as bool? ?? false;
      if (isProfileComplete) {
        context.go(RouteNames.home);
      } else {
        context.go(RouteNames.signup);
      }
    }
  }

  void _onOtpDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Handle paste of full 6-digit OTP code
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _otpControllers[i].text = digits[i];
      }
      if (_enteredOtp.length == 6) {
        _otpFocusNodes[5].unfocus();
        _handleVerifyOtp();
      }
      return;
    }

    if (value.isNotEmpty) {
      if (index < 5) {
        _otpFocusNodes[index + 1].requestFocus();
      } else {
        _otpFocusNodes[index].unfocus();
      }
    } else {
      if (index > 0) {
        _otpFocusNodes[index - 1].requestFocus();
      }
    }

    setState(() {});

    if (_enteredOtp.length == 6) {
      _handleVerifyOtp();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final timerString = _secondsRemaining < 10 ? '0$_secondsRemaining' : '$_secondsRemaining';

    return Scaffold(
      backgroundColor: isDark ? colors.surface : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Navigation Bar (Back Button on OTP screen)
                Row(
                  children: [
                    if (_otpSent)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _otpSent = false;
                            for (var c in _otpControllers) {
                              c.clear();
                            }
                            _resendTimer?.cancel();
                          });
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
                            border: Border.all(
                              color: isDark ? Colors.white.withValues(alpha: 0.1) : colors.border.withValues(alpha: 0.6),
                            ),
                            boxShadow: [
                              if (!isDark)
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 2),
                                ),
                            ],
                          ),
                          child: Icon(
                            Icons.chevron_left_rounded,
                            color: colors.textPrimary,
                            size: 26,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 42),
                  ],
                ),
                const SizedBox(height: 12),

                // Branding Section (Logo & Tagline)
                Text(
                  'LoopCall',
                  style: typography.displayWordmark.copyWith(
                    color: colors.primary,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Talk Freely. Connect Instantly.',
                  style: typography.bodySmall.copyWith(
                    color: colors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 36),

                // Greeting & Subtitle Section
                Text(
                  _otpSent ? 'Verify Phone' : 'Welcome to LoopCall',
                  style: typography.headlineGreeting.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                if (!_otpSent) ...[
                  Text(
                    'Sign in or register using your phone number.',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  Text(
                    'Enter the 6-digit code sent to',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formattedDisplayPhone,
                    style: typography.bodyMedium.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 32),

                // Error Message Banner
                if (authState is AsyncError) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.space12),
                    margin: const EdgeInsets.only(bottom: AppSpacing.space20),
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
                            AuthErrorMapper.mapMessage((authState as AsyncError).error),
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

                // Form Body: Phone Input OR 6-Digit OTP Grid
                if (!_otpSent) ...[
                  // Phone Number Label & Input Field
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Phone Number',
                      style: typography.bodySmall.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : colors.border.withValues(alpha: 0.8),
                        width: 1.2,
                      ),
                      boxShadow: [
                        if (!isDark)
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.phone_outlined,
                          color: colors.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Row(
                          children: [
                            Text(
                              _selectedCountryCode,
                              style: typography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down,
                              color: colors.textSecondary,
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 1,
                          height: 22,
                          color: colors.border.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            style: typography.bodyMedium.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Enter phone number',
                              hintStyle: typography.bodyMedium.copyWith(
                                color: colors.textSecondary.withValues(alpha: 0.5),
                                fontSize: 15,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your phone number';
                              }
                              if (value.trim().length < 8) {
                                return 'Please enter a valid phone number';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Helper text with Lock Icon
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: colors.primary.withValues(alpha: 0.8),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "We'll send you a verification code",
                        style: typography.bodySmall.copyWith(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Primary Button: Get Verification Code
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: AppPrimaryButton(
                      text: authState.isLoading ? 'Sending Code...' : 'Get Verification Code',
                      onPressed: authState.isLoading ? null : _handleSendOtp,
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Footer Security Note
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        size: 16,
                        color: colors.primary.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Your number is safe with us.',
                        style: typography.bodySmall.copyWith(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // 6-Digit OTP Code Input Grid
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(6, (index) {
                      final hasFocus = _otpFocusNodes[index].hasFocus;
                      final hasText = _otpControllers[index].text.isNotEmpty;

                      return Container(
                        width: 48,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: hasFocus
                                ? colors.primary
                                : (hasText ? colors.primary.withValues(alpha: 0.4) : colors.border.withValues(alpha: 0.7)),
                            width: hasFocus ? 1.5 : 1.0,
                          ),
                          boxShadow: [
                            if (!isDark)
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                          ],
                        ),
                        child: Center(
                          child: TextField(
                            controller: _otpControllers[index],
                            focusNode: _otpFocusNodes[index],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 1,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            style: typography.titleCard.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              counterText: '',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (val) => _onOtpDigitChanged(index, val),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 20),

                  // Resend Code & Change Number Links Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: (authState.isLoading || !_canResend) ? null : _handleSendOtp,
                        child: Text(
                          _canResend ? 'Resend Code' : 'Resend Code (${_secondsRemaining}s)',
                          style: TextStyle(
                            color: _canResend ? colors.primary : colors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _otpSent = false;
                            for (var c in _otpControllers) {
                              c.clear();
                            }
                            _resendTimer?.cancel();
                          });
                        },
                        child: Text(
                          'Change Number',
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Primary Button: Verify & Continue
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: AppPrimaryButton(
                      text: authState.isLoading ? 'Verifying...' : 'Verify & Continue',
                      onPressed: authState.isLoading ? null : _handleVerifyOtp,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Bottom Security / Resend Info Banner Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? colors.primary.withValues(alpha: 0.12)
                          : const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: colors.primary,
                          child: const Icon(
                            Icons.shield_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Didn't receive the code?",
                                style: typography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colors.textPrimary,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              RichText(
                                text: TextSpan(
                                  style: typography.bodySmall.copyWith(
                                    color: colors.textSecondary,
                                    fontSize: 13,
                                  ),
                                  children: [
                                    const TextSpan(text: 'You can request a new code after '),
                                    TextSpan(
                                      text: '00:$timerString',
                                      style: TextStyle(
                                        color: colors.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
