import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';

/// Modal dialog shown to the initiator when broadcasting or when someone accepts.
class InitiatorOtpModal extends ConsumerWidget {
  final BuddyRequest request;

  const InitiatorOtpModal({super.key, required this.request});

  static Future<void> show(BuildContext context, {required BuddyRequest request}) {
    return showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => InitiatorOtpModal(request: request),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final type = request.buddyType;

    // Check if live state has updated
    final buddyState = ref.watch(buddyControllerProvider);
    final currentReq = buddyState.myRequests.firstWhere(
      (r) => r.id == request.id,
      orElse: () => request,
    );

    final isAccepted = currentReq.status == BuddyRequestStatus.accepted ||
        (currentReq.otpCode != null && currentReq.otpCode!.isNotEmpty);
    final otp = currentReq.otpCode ?? '';

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
          const SizedBox(height: 20),

          if (!isAccepted) ...[
            // STATE A: Waiting for someone to accept
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: type.accentColor.withValues(alpha: 0.12),
                    ),
                  ),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: type.accentColor.withValues(alpha: 0.2),
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 68,
                      height: 68,
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
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            Text(
              'Broadcast Live in ${currentReq.city} 🚀',
              style: typography.titleCard.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                'Notifying nearby buddies for ${type.title}. The first person to accept will lock in and verify with your secret OTP.',
                style: typography.bodySmall.copyWith(
                  color: colors.textSecondary,
                  fontSize: 13.5,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // Live status badge
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: type.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: type.accentColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: type.accentColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Waiting for someone to accept...',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: type.accentColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.border, width: 1.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Keep Browsing',
                  style: typography.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
          ] else ...[
            // STATE B: Someone has accepted! Display 6-digit OTP
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.success.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.verified_rounded,
                  color: colors.success,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 12),

            Text(
              'Buddy Found! 🎉',
              style: typography.titleCard.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),

            // Accepter user card
            if (currentReq.accepter != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.cardBorder),
                ),
                child: Row(
                  children: [
                    GradientAvatar(
                      initials: currentReq.accepter!.fullName.isNotEmpty
                          ? currentReq.accepter!.fullName[0].toUpperCase()
                          : 'B',
                      avatarSeed: currentReq.accepter!.avatarSeed,
                      avatarStyle: currentReq.accepter!.avatarStyle,
                      gender: currentReq.accepter!.gender,
                      radius: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentReq.accepter!.fullName,
                            style: typography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'Accepted your ${type.title}',
                            style: typography.bodySmall.copyWith(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.success.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Locked In',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),

            // 6-digit OTP Box
            Text(
              'YOUR 6-DIGIT VERIFICATION CODE',
              style: typography.bodySmall.copyWith(
                color: colors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    type.accentColor.withValues(alpha: 0.12),
                    type.accentColor.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: type.accentColor.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(6, (i) {
                      final digit = (i < otp.length) ? otp[i] : '•';
                      return Container(
                        width: 44,
                        height: 54,
                        decoration: BoxDecoration(
                          color: colors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: type.accentColor.withValues(alpha: 0.6),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: type.accentColor.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            digit,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              color: type.accentColor,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () {
                      if (otp.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: otp));
                        AppSnackBar.showSuccess(context, 'OTP code copied!');
                      }
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.copy_rounded, size: 16, color: type.accentColor),
                        const SizedBox(width: 6),
                        Text(
                          'Tap to copy code',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: type.accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Clear Instructions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: colors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Share this 6-digit code with your buddy in person. Once they enter it, your private chat and audio/video calls will unlock instantly!',
                      style: typography.bodySmall.copyWith(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  ref.read(buddyControllerProvider.notifier).dismissInitiatorOtpModal();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: type.accentColor,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Got it, I’ll share the code',
                  style: typography.bodyMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
