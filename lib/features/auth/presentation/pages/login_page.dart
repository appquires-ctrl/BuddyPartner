import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/features/auth/application/auth_controller.dart';
import 'package:buddypartner/features/auth/application/auth_error_mapper.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/core/widgets/buttons/app_primary_button.dart';
import 'package:buddypartner/core/constants/country_codes.dart';
import 'package:buddypartner/core/widgets/country_code_picker_modal.dart';

enum LoginMethod { password, otp }

/// LoginPage handles username/phone + password authentication as primary (0 SMS cost)
/// and WhatsApp phone number + 6-digit OTP verification as fallback.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  LoginMethod _loginMethod = LoginMethod.otp;
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  CountryCode _selectedCountry = CountryCodes.defaultCountry;
  bool _otpSent = false;
  
  // 6-digit OTP controllers & focus nodes
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  Timer? _resendTimer;
  int _secondsRemaining = 29;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _phoneFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _phoneFocusNode.removeListener(_onFocusChange);
    _loginController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _otpSent && mounted) {
      _checkClipboardForOtp();
    }
  }

  /// Automatically checks clipboard for a 6-digit OTP code when user returns to app
  Future<void> _checkClipboardForOtp() async {
    if (!_otpSent || !mounted) return;
    if (_enteredOtp.length == 6) return;

    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      final text = clipboardData?.text ?? '';
      if (text.isEmpty) return;

      final match = RegExp(r'\b\d{6}\b').firstMatch(text);
      if (match != null) {
        final code = match.group(0)!;
        if (_enteredOtp == code) return;

        AppLogger.click('Auto-pasted OTP from clipboard: $code', screen: 'LoginScreen');
        if (mounted) {
          setState(() {
            for (int i = 0; i < 6; i++) {
              _otpControllers[i].text = code[i];
            }
          });
          _otpFocusNodes[5].unfocus();
          AppSnackBar.showSuccess(context, 'Auto-filled OTP from clipboard');
          _handleVerifyOtp();
        }
      }
    } catch (e) {
      // Swallowed safely if clipboard permission is unavailable
    }
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

  String get _formattedDisplayPhone {
    final rawPhone = _phoneController.text.trim().replaceAll(' ', '');
    return '${_selectedCountry.flag} ${_selectedCountry.code} $rawPhone';
  }

  String get _enteredOtp => _otpControllers.map((c) => c.text).join();

  Future<void> _handlePasswordLogin() async {
    AppLogger.button('Log In with Password', screen: 'LoginScreen');
    final login = _loginController.text.trim();
    final password = _passwordController.text;

    if (login.isEmpty) {
      AppSnackBar.showError(context, 'Please enter your username or phone number.');
      return;
    }

    if (password.isEmpty) {
      AppSnackBar.showError(context, 'Please enter your password.');
      return;
    }

    final result = await ref.read(authControllerProvider.notifier).loginWithPassword(
      login: login,
      password: password,
    );

    if (result['success'] == true && mounted) {
      final isProfileComplete = result['isProfileComplete'] as bool? ?? false;
      if (isProfileComplete) {
        context.go(RouteNames.home);
      } else {
        context.go(RouteNames.signup);
      }
    } else if (mounted) {
      final errorCode = result['errorCode'] as String?;
      final errorMsg = result['error'] as String? ?? 'Invalid credentials.';

      if (errorCode == 'NO_PASSWORD_SET') {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Password Not Set'),
            content: Text(errorMsg),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _loginMethod = LoginMethod.otp;
                    final digits = login.replaceAll(RegExp(r'\D'), '');
                    if (digits.length >= 10) {
                      _phoneController.text = digits.length > 10 ? digits.substring(digits.length - 10) : digits;
                    }
                  });
                },
                child: const Text('Log In with OTP'),
              ),
            ],
          ),
        );
      } else {
        AppSnackBar.showError(context, errorMsg);
      }
    }
  }

  Future<void> _handleSendOtp() async {
    AppLogger.button('Send Verification Code', screen: 'LoginScreen');
    if (!_formKey.currentState!.validate()) return;

    final mobile = _phoneController.text.trim().replaceAll(' ', '');
    if (mobile.isEmpty || mobile.length < _selectedCountry.minLength) {
      AppSnackBar.showError(context, 'Please enter a valid mobile number (${_selectedCountry.minLength}–${_selectedCountry.maxLength} digits).');
      return;
    }

    final success = await ref
        .read(authControllerProvider.notifier)
        .sendOtp(countryCode: _selectedCountry.code, mobile: mobile);

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
    } else if (mounted) {
      final authState = ref.read(authControllerProvider);
      final rawError = authState.error;
      final cleanMsg = rawError != null ? AuthErrorMapper.mapMessage(rawError) : 'Failed to send OTP.';
      AppSnackBar.showError(context, cleanMsg);
    }
  }

  Future<void> _handleVerifyOtp() async {
    AppLogger.button('Verify Code & Login', screen: 'LoginScreen');
    final otp = _enteredOtp;
    if (otp.length != 6) {
      AppSnackBar.showError(context, 'Please enter all 6 digits of the verification code.');
      return;
    }

    final mobile = _phoneController.text.trim().replaceAll(' ', '');
    final result = await ref
        .read(authControllerProvider.notifier)
        .verifyOtp(countryCode: _selectedCountry.code, mobile: mobile, otp: otp);

    if (result['success'] == true && mounted) {
      final isProfileComplete = result['isProfileComplete'] as bool? ?? false;
      if (isProfileComplete) {
        context.go(RouteNames.home);
      } else {
        context.go(RouteNames.signup);
      }
    } else if (mounted) {
      final errorMsg = result['error'] as String? ?? 'Invalid verification code.';
      AppSnackBar.showError(context, errorMsg);
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
      backgroundColor: isDark ? colors.surface : Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24, vertical: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Top Navigation Bar (Back button when OTP is sent)
                if (_otpSent)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
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
                        width: 38,
                        height: 38,
                        margin: const EdgeInsets.only(top: 4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white,
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.1) : colors.border.withValues(alpha: 0.6),
                          ),
                        ),
                        child: Icon(
                          Icons.chevron_left_rounded,
                          color: colors.textPrimary,
                          size: 24,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 12),

                const SizedBox(height: 8),

                // Branding Section (App Logo & Tagline)
                Image.asset(
                  'assets/images/app_logo.png',
                  width: 108,
                  height: 108,
                ),
                const SizedBox(height: 8),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Buddy',
                        style: typography.displayWordmark.copyWith(
                          color: const Color(0xFF1E4FAE),
                          fontSize: 28.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          height: 1.0,
                        ),
                      ),
                      TextSpan(
                        text: 'Partner',
                        style: typography.displayWordmark.copyWith(
                          color: const Color(0xFFE91E63),
                          fontSize: 28.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '. MEET. CONNECT. BE FRIENDS.',
                  style: typography.bodySmall.copyWith(
                    color: colors.textSecondary.withValues(alpha: 0.8),
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 22),

                if (!_otpSent) ...[
                  Text(
                    'Welcome Back',
                    style: typography.headlineGreeting.copyWith(
                      fontSize: 24.0,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _loginMethod == LoginMethod.password
                        ? 'Log in with your username or password.'
                        : 'Sign in or register using your WhatsApp number.',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
                      fontSize: 14.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                ] else ...[
                  // Header when 6-digit OTP code is sent
                  Text(
                    'Verify Phone',
                    style: typography.headlineGreeting.copyWith(
                      fontSize: 22.0,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter the 6-digit code sent to',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
                      fontSize: 13.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formattedDisplayPhone,
                    style: typography.bodyMedium.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 15.0,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                ],

                // Error Message Banner
                if (authState is AsyncError) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.space12),
                    margin: const EdgeInsets.only(bottom: 14),
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

                // Form Body
                if (_loginMethod == LoginMethod.password)
                  _buildPasswordLoginForm(context)
                else if (!_otpSent)
                  _buildPhoneInputForm(context)
                else
                  _buildOtpVerificationForm(context, timerString),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOrDivider() {
    return Row(
      children: const [
        Expanded(
          child: Divider(
            color: Color(0xFFF1F5F9),
            thickness: 1,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: Divider(
            color: Color(0xFFF1F5F9),
            thickness: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneInputForm(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isFocused = _phoneFocusNode.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WhatsApp Number',
          style: typography.bodySmall.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
            fontSize: 14.0,
          ),
        ),
        const SizedBox(height: 8),

        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _phoneFocusNode.requestFocus(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 54,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isFocused
                    ? colors.primary
                    : (isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0)),
                width: isFocused ? 1.6 : 1.2,
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: isFocused
                        ? colors.primary.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.02),
                    blurRadius: isFocused ? 10 : 4,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Country Code Picker Selector
                InkWell(
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
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _selectedCountry.flag,
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _selectedCountry.code,
                          style: typography.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                            fontSize: 15.0,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: colors.textSecondary.withValues(alpha: 0.7),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1.2,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                ),

                // Text Input Field (Vertically centered)
                Expanded(
                  child: Center(
                    child: TextFormField(
                      controller: _phoneController,
                      focusNode: _phoneFocusNode,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _handleSendOtp(),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(_selectedCountry.maxLength),
                      ],
                      style: typography.bodyMedium.copyWith(
                        fontSize: 15.0,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        letterSpacing: 0.3,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        isCollapsed: true,
                        hintText: 'Enter WhatsApp number',
                        hintStyle: typography.bodyMedium.copyWith(
                          color: colors.textSecondary.withValues(alpha: 0.45),
                          fontSize: 14.5,
                          fontWeight: FontWeight.normal,
                          letterSpacing: 0,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter your whatsapp number';
                        }
                        if (value.trim().length < 8) {
                          return 'Please enter a valid whatsapp number';
                        }
                        return null;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Helper text with Lock Icon
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: colors.primary.withValues(alpha: 0.8),
            ),
            const SizedBox(width: 6),
            Text(
              "We'll send you a verification code",
              style: typography.bodySmall.copyWith(
                color: colors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Primary Button: Get Verification Code
        SizedBox(
          width: double.infinity,
          height: 52,
          child: AppPrimaryButton(
            text: authState.isLoading ? 'Sending Code...' : 'Get Verification Code',
            onPressed: authState.isLoading ? null : _handleSendOtp,
          ),
        ),
        const SizedBox(height: 22),

        // OR Divider
        _buildOrDivider(),
        const SizedBox(height: 16),

        // Bottom Helper for WhatsApp OTP screen
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have a password? ',
              style: typography.bodySmall.copyWith(
                color: colors.textSecondary,
                fontSize: 13.5,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _loginMethod = LoginMethod.password;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(
                  'Log in here',
                  style: typography.bodySmall.copyWith(
                    color: const Color(0xFF6366F1),
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildOtpVerificationForm(BuildContext context, String timerString) {
    final colors = context.colors;
    final typography = context.typography;
    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // 6-Digit OTP Code Input Grid
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            final hasFocus = _otpFocusNodes[index].hasFocus;
            final hasText = _otpControllers[index].text.isNotEmpty;

            return Container(
              width: 48,
              height: 54,
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
                    fontSize: 22.0,
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

        const SizedBox(height: 18),

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
                  fontSize: 13.5,
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
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Primary Button: Verify & Continue
        SizedBox(
          width: double.infinity,
          height: 52,
          child: AppPrimaryButton(
            text: authState.isLoading ? 'Verifying...' : 'Verify & Continue',
            onPressed: authState.isLoading ? null : _handleVerifyOtp,
          ),
        ),

        const SizedBox(height: 20),

        // Bottom Security / Resend Info Banner Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark
                ? colors.primary.withValues(alpha: 0.12)
                : const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: colors.primary,
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Didn't receive the code?",
                      style: typography.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    RichText(
                      text: TextSpan(
                        style: typography.bodySmall.copyWith(
                          color: colors.textSecondary,
                          fontSize: 12.5,
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
    );
  }

  Widget _buildPasswordLoginForm(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Username / Phone label & field
        Text(
          'Username or Phone Number',
          style: typography.bodySmall.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
            fontSize: 14.0,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                color: colors.textSecondary.withValues(alpha: 0.6),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _loginController,
                  textInputAction: TextInputAction.next,
                  style: typography.bodyMedium.copyWith(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter @username or phone',
                    hintStyle: typography.bodyMedium.copyWith(
                      color: colors.textSecondary.withValues(alpha: 0.4),
                      fontSize: 14.5,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Password label & field
        Text(
          'Password',
          style: typography.bodySmall.copyWith(
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
            fontSize: 14.0,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: colors.textSecondary.withValues(alpha: 0.6),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _handlePasswordLogin(),
                  style: typography.bodyMedium.copyWith(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Enter your password',
                    hintStyle: typography.bodyMedium.copyWith(
                      color: colors.textSecondary.withValues(alpha: 0.4),
                      fontSize: 14.5,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: colors.textSecondary.withValues(alpha: 0.6),
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Forgot password link
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () => context.push(RouteNames.forgotPassword),
            child: Text(
              'Forgot Password?',
              style: typography.bodySmall.copyWith(
                color: const Color(0xFF6366F1),
                fontWeight: FontWeight.w600,
                fontSize: 13.0,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Log In button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: AppPrimaryButton(
            text: authState.isLoading ? 'Logging In...' : 'Log In',
            onPressed: authState.isLoading ? null : _handlePasswordLogin,
          ),
        ),
        const SizedBox(height: 22),

        // OR Divider
        _buildOrDivider(),
        const SizedBox(height: 16),

        // Bottom Helper for Password screen
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'New to BuddyPartner? ',
              style: typography.bodySmall.copyWith(
                color: colors.textSecondary,
                fontSize: 13.5,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _loginMethod = LoginMethod.otp;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(
                  'Get Started with WhatsApp',
                  style: typography.bodySmall.copyWith(
                    color: const Color(0xFF6366F1),
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
