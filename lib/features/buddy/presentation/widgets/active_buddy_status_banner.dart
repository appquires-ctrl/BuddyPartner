import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_colors.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';

/// Clean, human-designed Home Screen card indicating active Buddy connections.
/// Tapping navigates to MyBuddyActivityPage.
class ActiveBuddyStatusBanner extends ConsumerWidget {
  const ActiveBuddyStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final buddyState = ref.watch(buddyControllerProvider);
    final currentUserId = ref.watch(authStateProvider).value?.id;

    if (currentUserId == null) return const SizedBox.shrink();

    // 1. Accepted as initiator
    final acceptedAsInitiatorList = buddyState.myRequests.where(
      (r) =>
          r.initiatorId == currentUserId &&
          r.status == BuddyRequestStatus.accepted,
    ).toList();

    // 2. Accepted as accepter
    final acceptedAsAccepterList = buddyState.myRequests.where(
      (r) =>
          r.accepterId == currentUserId &&
          r.status == BuddyRequestStatus.accepted,
    ).toList();

    // 3. Open broadcasts
    final openAsInitiatorList = buddyState.myRequests.where(
      (r) =>
          r.initiatorId == currentUserId && r.status == BuddyRequestStatus.open,
    ).toList();

    final handshakesCount =
        acceptedAsInitiatorList.length + acceptedAsAccepterList.length;
    final broadcastsCount = openAsInitiatorList.length;
    final totalActive = handshakesCount + broadcastsCount;

    if (totalActive == 0) return const SizedBox.shrink();

    // Collect partners for avatars and natural names
    final partners = <BuddyUserSummary>[];
    for (final r in acceptedAsInitiatorList) {
      if (r.accepter != null) partners.add(r.accepter!);
    }
    for (final r in acceptedAsAccepterList) {
      if (r.initiator != null) partners.add(r.initiator!);
    }

    // Title and Subtitle construction in natural, human language
    String titleText;
    String subtitleText;

    if (partners.isNotEmpty) {
      final names = partners
          .map((p) => p.fullName.trim().split(' ').first)
          .where((n) => n.isNotEmpty && n.toLowerCase() != 'user')
          .toList();

      if (names.isNotEmpty) {
        if (names.length == 1) {
          titleText = 'Meetup with ${names.first}';
        } else if (names.length == 2) {
          titleText = '${names[0]} & ${names[1]}';
        } else {
          titleText = '${names[0]}, ${names[1]} +${names.length - 2}';
        }
      } else {
        titleText = handshakesCount == 1
            ? '1 Active Meetup'
            : '$handshakesCount Active Meetups';
      }

      if (broadcastsCount > 0) {
        subtitleText = 'Chat & OTP ready • +$broadcastsCount broadcast live';
      } else {
        subtitleText = 'Chat open • Meetup OTP ready';
      }
    } else {
      // Broadcasts only
      final city = openAsInitiatorList.first.city;
      final displayCity = city.isNotEmpty
          ? (city[0].toUpperCase() + city.substring(1).toLowerCase())
          : 'your city';
      if (broadcastsCount == 1) {
        titleText = 'Broadcast Live';
        subtitleText = 'Looking for buddies in $displayCity';
      } else {
        titleText = '$broadcastsCount Broadcasts Live';
        subtitleText = 'Active in $displayCity';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push(RouteNames.buddyActivity),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF6366F1).withValues(alpha: 0.16),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                // Partner Avatar(s) or Broadcast Indicator
                _buildLeadingGraphic(partners, colors),
                const SizedBox(width: 12),

                // Title, Status Chip & Subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              titleText,
                              style: typography.titleCard.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFDF5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.6),
                                        blurRadius: 3,
                                        spreadRadius: 0.5,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$totalActive Active',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF047857),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitleText,
                        style: typography.bodySmall.copyWith(
                          fontSize: 12,
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),

                // Trailing High-Contrast Deep Royal Purple "View" Action Button
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Text(
                        ' View',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingGraphic(
    List<BuddyUserSummary> partners,
    AppColors colors,
  ) {
    if (partners.length >= 2) {
      // 2 Overlapping Avatars
      return SizedBox(
        width: 48,
        height: 36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: GradientAvatar(
                initials: partners[0].fullName.isNotEmpty
                    ? partners[0].fullName[0].toUpperCase()
                    : 'B',
                avatarSeed: partners[0].avatarSeed,
                avatarStyle: partners[0].avatarStyle,
                gender: partners[0].gender,
                radius: 17,
              ),
            ),
            Positioned(
              left: 16,
              top: 0,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: GradientAvatar(
                  initials: partners[1].fullName.isNotEmpty
                    ? partners[1].fullName[0].toUpperCase()
                    : 'B',
                  avatarSeed: partners[1].avatarSeed,
                  avatarStyle: partners[1].avatarStyle,
                  gender: partners[1].gender,
                  radius: 16,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (partners.length == 1) {
      // 1 Avatar with green online dot
      return GradientAvatar(
        initials: partners[0].fullName.isNotEmpty
            ? partners[0].fullName[0].toUpperCase()
            : 'B',
        avatarSeed: partners[0].avatarSeed,
        avatarStyle: partners[0].avatarStyle,
        gender: partners[0].gender,
        radius: 19,
        showStatus: true,
        isOnline: true,
        statusIndicatorSize: 10,
      );
    } else {
      // Broadcasts only: Clean rounded icon
      return Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.sensors_rounded,
          color: colors.primary,
          size: 20,
        ),
      );
    }
  }
}
