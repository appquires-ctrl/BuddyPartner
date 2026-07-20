import 'dart:async';
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

/// LoginPage handles phone number OTP authentication.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController(text: '+91');
  final _otpController = TextEditingController();
  bool _otpSent = false;
  
  Timer? _resendTimer;
  int _secondsRemaining = 30;
  bool _canResend = false;

  void _startResendTimer() {
    setState(() {
      _secondsRemaining = 30;
      _canResend = false;
    });
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        setState(() {
          _canResend = true;
        });
        timer.cancel();
      } else {
        setState(() {
          _secondsRemaining--;
        });
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleSendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(_phoneController.text.trim());

    if (success && mounted) {
      setState(() {
        _otpSent = true;
      });
      _startResendTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP sent successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleVerifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final result = await ref
        .read(authControllerProvider.notifier)
        .verifyOtp(_phoneController.text.trim(), _otpController.text.trim());

    if (result['success'] == true && mounted) {
      final isProfileComplete = result['isProfileComplete'] as bool? ?? false;
      if (isProfileComplete) {
        context.go(RouteNames.home);
      } else {
        // Redirect to Profile Onboarding page (which uses RouteNames.signup)
        context.go(RouteNames.signup);
      }
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
                const SizedBox(height: AppSpacing.space20),
                
                // App Logo Wordmark
                Center(
                  child: Column(
                    children: [
                      Text(
                        'LoopCall',
                        style: typography.displayWordmark.copyWith(
                          color: colors.primary,
                          fontSize: 36,
                        ),
                      ),
                      Text(
                        'Talk Freely. Connect Instantly.',
                        style: typography.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.space48),
                
                Text(
                  _otpSent ? 'Verify Phone' : 'Welcome to LoopCall',
                  style: typography.headlineGreeting.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: AppSpacing.space8),
                Text(
                  _otpSent
                      ? 'Enter the 6-digit code sent to ${_phoneController.text.trim()}.'
                      : 'Sign in or register using your phone number.',
                  style: typography.bodySmall.copyWith(color: colors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.space24),

                // Error message banner if authentication fails
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

                if (!_otpSent) ...[
                  // Phone Number entry
                  Text(
                    'Phone Number',
                    style: typography.bodySmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    style: typography.bodyMedium,
                    decoration: InputDecoration(
                      hintText: '+1234567890',
                      hintStyle: typography.bodySmall.copyWith(color: colors.textSecondary.withOpacity(0.6)),
                      prefixIcon: const Icon(Icons.phone_outlined, size: 20),
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
                        return 'Please enter your phone number';
                      }
                      if (value.trim().length < 8) {
                        return 'Please enter a valid phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.space32),

                  AppPrimaryButton(
                    text: authState.isLoading ? 'Sending OTP...' : 'Get Verification Code',
                    onPressed: authState.isLoading ? null : _handleSendOtp,
                  ),
                ] else ...[
                  // OTP entry
                  Text(
                    'Verification Code',
                    style: typography.bodySmall.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: typography.bodyMedium,
                    decoration: InputDecoration(
                      hintText: '6-digit code',
                      counterText: '',
                      hintStyle: typography.bodySmall.copyWith(color: colors.textSecondary.withOpacity(0.6)),
                      prefixIcon: const Icon(Icons.lock_clock_outlined, size: 20),
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
                        return 'Please enter the verification code';
                      }
                      if (value.trim().length != 6) {
                        return 'Code must be exactly 6 digits';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.space16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: (authState.isLoading || !_canResend) ? null : _handleSendOtp,
                        child: Text(
                          _canResend ? 'Resend Code' : 'Resend Code ($_secondsRemaining s)',
                          style: TextStyle(
                            color: _canResend ? colors.primary : colors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _otpSent = false;
                            _otpController.clear();
                            _resendTimer?.cancel();
                          });
                        },
                        child: Text(
                          'Change Number',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space32),

                  AppPrimaryButton(
                    text: authState.isLoading ? 'Verifying...' : 'Verify & Continue',
                    onPressed: authState.isLoading ? null : _handleVerifyOtp,
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
