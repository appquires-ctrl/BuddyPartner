import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/accepter_otp_dialog.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/initiator_otp_modal.dart';

/// Contextual card shown on the Home Screen when the user has an active Buddy handshake.
class ActiveBuddyStatusBanner extends ConsumerWidget {
  const ActiveBuddyStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final buddyState = ref.watch(buddyControllerProvider);
    final currentUserId = ref.watch(authStateProvider).value?.id;

    if (currentUserId == null) return const SizedBox.shrink();

    // Check 1: Is user an initiator with an accepted request?
    final acceptedAsInitiatorList = buddyState.myRequests.where(
      (r) =>
          r.initiatorId == currentUserId &&
          r.status == BuddyRequestStatus.accepted &&
          r.otpCode != null &&
          r.otpCode!.isNotEmpty,
    );

    if (acceptedAsInitiatorList.isNotEmpty) {
      final acceptedAsInitiator = acceptedAsInitiatorList.first;
      final type = acceptedAsInitiator.buddyType;
      final partnerName = acceptedAsInitiator.accepter?.fullName ?? 'Someone';

      return Container(
        margin: const EdgeInsets.only(top: 16),
        child: InkWell(
          onTap: () => InitiatorOtpModal.show(context, request: acceptedAsInitiator),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  type.accentColor.withValues(alpha: 0.15),
                  type.accentColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: type.accentColor.withValues(alpha: 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: type.accentColor.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: type.accentColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.key_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Buddy Accepted! 🎉',
                            style: typography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: type.accentColor,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: type.accentColor.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'OTP Ready',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: type.accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$partnerName accepted your ${type.title}. Tap to view OTP.',
                        style: typography.bodySmall.copyWith(
                          fontSize: 12,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: type.accentColor),
              ],
            ),
          ),
        ),
      );
    }

    // Check 2: Is user an accepter with an accepted request pending OTP?
    final acceptedAsAccepterList = buddyState.myRequests.where(
      (r) => r.accepterId == currentUserId && r.status == BuddyRequestStatus.accepted,
    );

    if (acceptedAsAccepterList.isNotEmpty) {
      final acceptedAsAccepter = acceptedAsAccepterList.first;
      final type = acceptedAsAccepter.buddyType;
      final initiatorName = acceptedAsAccepter.initiator?.fullName ?? 'Buddy Partner';

      return Container(
        margin: const EdgeInsets.only(top: 16),
        child: InkWell(
          onTap: () => AccepterOtpDialog.show(context, request: acceptedAsAccepter),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: 0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Enter OTP Handshake',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF047857),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const AppCoinIcon(size: 14),
                          const SizedBox(width: 2),
                          const Text(
                            '+50',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF047857),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Tap to enter 6-digit OTP from $initiatorName for ${type.title}.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF065F46),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF047857)),
              ],
            ),
          ),
        ),
      );
    }

    // Check 3: Is user an initiator with an active open request?
    final openAsInitiatorList = buddyState.myRequests.where(
      (r) => r.initiatorId == currentUserId && r.status == BuddyRequestStatus.open,
    );

    if (openAsInitiatorList.isNotEmpty) {
      final openAsInitiator = openAsInitiatorList.first;
      final type = openAsInitiator.buddyType;
      return Container(
        margin: const EdgeInsets.only(top: 16),
        child: InkWell(
          onTap: () => InitiatorOtpModal.show(context, request: openAsInitiator),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: type.accentColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your ${type.title} in ${openAsInitiator.city} is live. Tap for details.',
                    style: typography.bodySmall.copyWith(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: colors.textSecondary),
              ],
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
