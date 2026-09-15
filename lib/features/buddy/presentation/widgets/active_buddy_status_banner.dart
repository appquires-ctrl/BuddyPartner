import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_colors.dart';
import 'package:buddypartner/app/theme/app_typography.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
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

    // Check 1: Requests where current user is initiator and request is accepted
    final acceptedAsInitiatorList = buddyState.myRequests.where(
      (r) =>
          r.initiatorId == currentUserId &&
          r.status == BuddyRequestStatus.accepted,
    );

    // Check 2: Requests where current user is accepter and request is accepted pending OTP
    final acceptedAsAccepterList = buddyState.myRequests.where(
      (r) =>
          r.accepterId == currentUserId &&
          r.status == BuddyRequestStatus.accepted,
    );

    // Check 3: Requests where current user is initiator and request is open/broadcasting
    final openAsInitiatorList = buddyState.myRequests.where(
      (r) =>
          r.initiatorId == currentUserId && r.status == BuddyRequestStatus.open,
    );

    final cards = <Widget>[];

    // 1. All accepted initiator requests
    for (final req in acceptedAsInitiatorList) {
      cards.add(_buildInitiatorAcceptedCard(context, req, colors, typography));
    }

    // 2. All accepted accepter requests
    for (final req in acceptedAsAccepterList) {
      cards.add(_buildAccepterPendingCard(context, req, colors, typography));
    }

    // 3. All open initiator requests
    for (final req in openAsInitiatorList) {
      cards.add(_buildInitiatorOpenCard(context, req, colors, typography));
    }

    if (cards.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            cards[i],
          ],
        ],
      ),
    );
  }

  Widget _buildInitiatorAcceptedCard(
    BuildContext context,
    BuddyRequest request,
    AppColors colors,
    AppTypography typography,
  ) {
    final type = request.buddyType;
    final partner = request.accepter;
    final partnerId = partner?.id ?? request.accepterId ?? '';
    final partnerName = (partner?.fullName != null && partner!.fullName.isNotEmpty && partner.fullName != 'User')
        ? partner.fullName
        : 'Buddy Partner';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            type.accentColor.withValues(alpha: 0.14),
            type.accentColor.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: type.accentColor.withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: type.accentColor.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: type.accentColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.handshake_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Buddy Accepted!',
                          style: typography.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.0,
                            color: type.accentColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: type.accentColor.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'OTP Ready',
                            style: TextStyle(
                              fontSize: 10.0,
                              fontWeight: FontWeight.bold,
                              color: type.accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$partnerName accepted your ${type.title}. Chat is unlocked!',
                      style: typography.bodySmall.copyWith(
                        fontSize: 12.0,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      context.push(
                        RouteNames.chat,
                        extra: {
                          'conversationId': request.conversationId ?? '',
                          'userId': partnerId,
                          'userName': partnerName,
                          'avatarSeed': partner?.avatarSeed,
                          'avatarStyle': partner?.avatarStyle,
                          'gender': partner?.gender,
                        },
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_rounded, size: 15, color: Colors.white),
                    label: Text(
                      'Chat with $partnerName',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: type.accentColor,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: () => InitiatorOtpModal.show(context, request: request),
                  icon: Icon(Icons.key_rounded, size: 15, color: type.accentColor),
                  label: Text(
                    'View OTP',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: type.accentColor,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: type.accentColor.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAccepterPendingCard(
    BuildContext context,
    BuddyRequest request,
    AppColors colors,
    AppTypography typography,
  ) {
    final type = request.buddyType;
    final partner = request.initiator;
    final partnerId = partner?.id ?? request.initiatorId;
    final initiatorName = (partner?.fullName != null && partner!.fullName.isNotEmpty && partner.fullName != 'User')
        ? partner.fullName
        : 'Buddy Partner';

    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Handshake Active',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14.0,
                            color: Color(0xFF047857),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const AppCoinIcon(size: 13),
                        const SizedBox(width: 2),
                        const Text(
                          '+50',
                          style: TextStyle(
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'You are connected with $initiatorName for ${type.title}!',
                      style: const TextStyle(
                        fontSize: 12.0,
                        color: Color(0xFF065F46),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      context.push(
                        RouteNames.chat,
                        extra: {
                          'conversationId': request.conversationId ?? '',
                          'userId': partnerId,
                          'userName': initiatorName,
                          'avatarSeed': partner?.avatarSeed,
                          'avatarStyle': partner?.avatarStyle,
                          'gender': partner?.gender,
                        },
                      );
                    },
                    icon: const Icon(Icons.chat_bubble_rounded, size: 15, color: Colors.white),
                    label: Text(
                      'Chat with $initiatorName',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 38,
                child: OutlinedButton.icon(
                  onPressed: () => AccepterOtpDialog.show(context, request: request),
                  icon: const Icon(Icons.lock_open_rounded, size: 15, color: Color(0xFF047857)),
                  label: const Text(
                    'Enter OTP',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF047857),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF10B981)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInitiatorOpenCard(
    BuildContext context,
    BuddyRequest request,
    AppColors colors,
    AppTypography typography,
  ) {
    final type = request.buddyType;

    return InkWell(
      onTap: () => InitiatorOtpModal.show(context, request: request),
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
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: type.accentColor,
                boxShadow: [
                  BoxShadow(
                    color: type.accentColor.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Your ${type.title} in ${request.city} is live. Tap for details.',
                style: typography.bodySmall.copyWith(
                  fontSize: 12.0,
                  color: colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 12,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
