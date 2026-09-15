import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';

/// Dialog/Sheet for the accepter to enter the 6-digit OTP provided by the initiator.
class AccepterOtpDialog extends ConsumerStatefulWidget {
  final BuddyRequest request;

  const AccepterOtpDialog({super.key, required this.request});

  static Future<void> show(BuildContext context, {required BuddyRequest request}) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AccepterOtpDialog(request: request),
    );
  }

  @override
  ConsumerState<AccepterOtpDialog> createState() => _AccepterOtpDialogState();
}

class _AccepterOtpDialogState extends ConsumerState<AccepterOtpDialog> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() => _errorMessage = 'Please enter all 6 digits of the OTP.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(buddyControllerProvider.notifier).verifyBuddyOtp(
        requestId: widget.request.id,
        otpCode: code,
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // Close dialog

      AppSnackBar.showSuccess(
        context,
        'Meetup verified! +50 coins added to your wallet.',
      );


    } catch (e) {
      if (mounted) {
        final errText = e.toString().replaceAll('Exception: ', '');
        setState(() {
          _errorMessage = errText;
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final type = widget.request.buddyType;
    final initiatorName = widget.request.initiator?.fullName ?? 'your buddy';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Header
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: type.gradientColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Image.asset(
                    type.stickerAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) => const Icon(
                      Icons.local_activity_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verify Handshake',
                      style: typography.titleCard.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      'Ask $initiatorName for the 6-digit OTP',
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.close, color: colors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Direct Chat button
          SizedBox(
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                final initiator = widget.request.initiator;
                context.push(
                  RouteNames.chat,
                  extra: {
                    'conversationId': widget.request.conversationId ?? '',
                    'userId': initiator?.id ?? widget.request.initiatorId,
                    'userName': (initiator?.fullName != null && initiator!.fullName.isNotEmpty && initiator.fullName != 'User')
                        ? initiator.fullName
                        : 'Buddy Partner',
                    'avatarSeed': initiator?.avatarSeed,
                    'avatarStyle': initiator?.avatarStyle,
                    'gender': initiator?.gender,
                  },
                );
              },
              icon: const Icon(Icons.chat_bubble_rounded, size: 18, color: Colors.white),
              label: Text(
                'Chat with $initiatorName',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: type.accentColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Reward Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              children: [
                const AppCoinIcon(size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '+50 Coins reward will be credited immediately upon OTP verification!',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF065F46),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 6-Digit OTP Input
          Text(
            'ENTER 6-DIGIT OTP CODE',
            style: typography.bodySmall.copyWith(
              color: colors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Visual 6-box input backed by a hidden textfield
          GestureDetector(
            onTap: () => _focusNode.requestFocus(),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  final text = _otpController.text;
                  final digit = index < text.length ? text[index] : '';
                  final isCurrent = index == text.length;

                  return Container(
                    width: 44,
                    height: 52,
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isCurrent
                            ? type.accentColor
                            : (digit.isNotEmpty
                                ? colors.textPrimary
                                : colors.cardBorder),
                        width: isCurrent ? 2.0 : 1.2,
                      ),
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: type.accentColor.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        digit,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // Invisible real TextField to capture keyboard inputs
          Opacity(
            opacity: 0.0,
            child: SizedBox(
              height: 1,
              child: TextField(
                controller: _otpController,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (val) {
                  setState(() => _errorMessage = null);
                  if (val.length == 6) {
                    _verifyOtp();
                  }
                },
              ),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: colors.danger,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 10),

          // Rate limit info
          Center(
            child: Text(
              'Security note: Maximum 5 verification attempts allowed.',
              style: typography.bodySmall.copyWith(
                fontSize: 11,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Submit CTA
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: type.accentColor,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSubmitting
                  ? const AppLoadingIndicator(size: 22, color: Colors.white)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Verify Meetup (+50 🪙)',
                          style: typography.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
