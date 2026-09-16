import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/buttons/app_primary_button.dart';
import 'package:buddypartner/features/auth/application/auth_controller.dart';
import 'package:buddypartner/core/constants/country_codes.dart';
import 'package:buddypartner/core/widgets/country_code_picker_modal.dart';

class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  int _step = 1; // 1 = Enter Phone/Username, 2 = Enter OTP & New Password

  final _identifierController = TextEditingController();
  CountryCode _selectedCountry = CountryCodes.defaultCountry;

  // OTP & New Password state
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  String _resolvedCountryCode = '91';
  String _resolvedMobile = '';
  String? _phoneHint;

  Timer? _resendTimer;
  int _secondsRemaining = 29;
  bool _canResend = false;

  @override
  void dispose() {
    _identifierController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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
        if (mounted) setState(() => _canResend = true);
        timer.cancel();
      } else {
        if (mounted) setState(() => _secondsRemaining--);
      }
    });
  }

  String get _enteredOtp => _otpControllers.map((c) => c.text).join();

  Future<void> _handleSendOtp() async {
    final rawInput = _identifierController.text.trim();
    if (rawInput.isEmpty) {
      AppSnackBar.showError(context, 'Please enter your phone number or username.');
      return;
    }

    final digits = rawInput.replaceAll(RegExp(r'\D'), '');
    final bool hasLetters = RegExp(r'[a-zA-Z]').hasMatch(rawInput) || rawInput.startsWith('@');
    final bool isPhone = !hasLetters && digits.length >= 7;

    final result = await ref.read(authControllerProvider.notifier).sendForgotPasswordOtp(
      login: isPhone ? null : rawInput,
      countryCode: isPhone ? _selectedCountry.code : null,
      mobile: isPhone ? digits : null,
    );

    if (result['success'] == true && mounted) {
      setState(() {
        _resolvedCountryCode = result['countryCode'] ?? _selectedCountry.code;
        _resolvedMobile = result['mobile'] ?? digits;
        _phoneHint = result['phoneHint'];
        _step = 2;
      });
      _startResendTimer();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _otpFocusNodes[0].requestFocus();
      });
      AppSnackBar.showSuccess(context, result['message'] ?? 'Verification code sent to WhatsApp');
    } else if (mounted) {
      AppSnackBar.showError(context, result['error'] ?? 'Failed to send reset code.');
    }
  }

  Future<void> _handleResetPassword() async {
    final otp = _enteredOtp;
    if (otp.length != 6) {
      AppSnackBar.showError(context, 'Please enter all 6 digits of the verification code.');
      return;
    }

    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (newPass.length < 8) {
      AppSnackBar.showError(context, 'New password must be at least 8 characters long.');
      return;
    }

    if (newPass != confirmPass) {
      AppSnackBar.showError(context, 'Passwords do not match.');
      return;
    }

    final result = await ref.read(authControllerProvider.notifier).resetPasswordWithOtp(
      countryCode: _resolvedCountryCode,
      mobile: _resolvedMobile,
      otp: otp,
      newPassword: newPass,
    );

    if (result['success'] == true && mounted) {
      AppSnackBar.showSuccess(context, 'Password reset successfully! Please log in with your new password.');
      context.pop();
    } else if (mounted) {
      AppSnackBar.showError(context, result['error'] ?? 'Failed to reset password.');
    }
  }

  void _onOtpDigitChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6 && i < digits.length; i++) {
        _otpControllers[i].text = digits[i];
      }
      if (_enteredOtp.length == 6) {
        _otpFocusNodes[5].unfocus();
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
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? colors.surface : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.textPrimary, size: 20),
          onPressed: () {
            if (_step == 2) {
              setState(() => _step = 1);
            } else {
              context.pop();
            }
          },
        ),
        title: Text(
          'Reset Password',
          style: typography.titleCard.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // Header Icon & Guidance
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.primary.withValues(alpha: 0.1),
                  ),
                  child: Icon(
                    _step == 1 ? Icons.lock_reset_rounded : Icons.shield_outlined,
                    color: colors.primary,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  _step == 1 ? 'Forgot Your Password?' : 'Enter Verification Code',
                  style: typography.headlineGreeting.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _step == 1
                      ? 'Enter your registered WhatsApp phone number or username to receive a 6-digit recovery code.'
                      : 'Enter the 6-digit code sent to WhatsApp ${_phoneHint ?? _resolvedMobile} and create your new password.',
                  textAlign: TextAlign.center,
                  style: typography.bodySmall.copyWith(
                    color: colors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              if (_step == 1) ...[
                // Phone Number / Username Input
                Text(
                  'WhatsApp Number or Username',
                  style: typography.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                    fontSize: 14,
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
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          CountryCodePickerModal.show(
                            context,
                            selectedCountry: _selectedCountry,
                            onSelected: (country) {
                              setState(() {
                                _selectedCountry = country;
                              });
                            },
                          );
                        },
                        child: Row(
                          children: [
                            Text(_selectedCountry.flag, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 4),
                            Text(
                              _selectedCountry.code,
                              style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.keyboard_arrow_down, size: 18),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(width: 1, height: 22, color: colors.border),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _identifierController,
                          keyboardType: TextInputType.text,
                          style: typography.bodyMedium.copyWith(fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Enter phone or @username',
                            hintStyle: typography.bodyMedium.copyWith(
                              color: colors.textSecondary.withValues(alpha: 0.5),
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: AppPrimaryButton(
                    text: authState.isLoading ? 'Sending Code...' : 'Send Recovery Code',
                    onPressed: authState.isLoading ? null : _handleSendOtp,
                  ),
                ),
              ] else ...[
                // OTP Grid
                Text(
                  '6-Digit Verification Code',
                  style: typography.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
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
                      ),
                      child: Center(
                        child: TextField(
                          controller: _otpControllers[index],
                          focusNode: _otpFocusNodes[index],
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 1,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: typography.titleCard.copyWith(fontSize: 22, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                          onChanged: (val) => _onOtpDigitChanged(index, val),
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: (authState.isLoading || !_canResend) ? null : _handleSendOtp,
                    child: Text(
                      _canResend ? 'Resend Code' : 'Resend Code (${_secondsRemaining}s)',
                      style: TextStyle(
                        color: _canResend ? colors.primary : colors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // New Password Field
                Text(
                  'New Password',
                  style: typography.bodySmall.copyWith(fontWeight: FontWeight.bold, color: colors.textPrimary),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, color: colors.textSecondary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _newPasswordController,
                          obscureText: _obscureNewPassword,
                          decoration: const InputDecoration(
                            hintText: 'Min 8 characters',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _obscureNewPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                          color: colors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscureNewPassword = !_obscureNewPassword),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Confirm New Password Field
                Text(
                  'Confirm New Password',
                  style: typography.bodySmall.copyWith(fontWeight: FontWeight.bold, color: colors.textPrimary),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline_rounded, color: colors.textSecondary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          decoration: const InputDecoration(
                            hintText: 'Re-enter your new password',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                          color: colors.textSecondary,
                        ),
                        onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: AppPrimaryButton(
                    text: authState.isLoading ? 'Resetting...' : 'Reset Password & Save',
                    onPressed: authState.isLoading ? null : _handleResetPassword,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
