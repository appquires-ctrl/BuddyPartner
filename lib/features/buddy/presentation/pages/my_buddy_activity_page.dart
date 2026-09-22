import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_colors.dart';
import 'package:buddypartner/app/theme/app_typography.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/accepter_otp_dialog.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/initiator_otp_modal.dart';

/// Clean, modern screen displaying active Buddy connections, city broadcasts, and history.
class MyBuddyActivityPage extends ConsumerStatefulWidget {
  const MyBuddyActivityPage({super.key});

  @override
  ConsumerState<MyBuddyActivityPage> createState() => _MyBuddyActivityPageState();
}

class _MyBuddyActivityPageState extends ConsumerState<MyBuddyActivityPage>
    with SingleTickerProviderStateMixin {
  int _selectedTab = 0; // 0: Active, 1: Broadcasts, 2: Past

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(buddyControllerProvider.notifier).fetchMyRequests();
    });
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _capitalize(String s) {
    if (s.trim().isEmpty) return '';
    return s.trim()[0].toUpperCase() + s.trim().substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final buddyState = ref.watch(buddyControllerProvider);
    final currentUserId = ref.watch(authStateProvider).value?.id ?? '';

    // 1. Handshakes (accepted requests where user is either initiator or accepter)
    final acceptedAsInitiator = buddyState.myRequests
        .where((r) =>
            r.initiatorId == currentUserId &&
            r.status == BuddyRequestStatus.accepted)
        .toList();

    final acceptedAsAccepter = buddyState.myRequests
        .where((r) =>
            r.accepterId == currentUserId &&
            r.status == BuddyRequestStatus.accepted)
        .toList();

    final allHandshakes = [...acceptedAsInitiator, ...acceptedAsAccepter];

    // 2. Open city broadcasts
    final openBroadcasts = buddyState.myRequests
        .where((r) =>
            r.initiatorId == currentUserId &&
            r.status == BuddyRequestStatus.open)
        .toList();

    // 3. Past requests
    final pastRequests = buddyState.myRequests
        .where((r) =>
            r.status == BuddyRequestStatus.completed ||
            r.status == BuddyRequestStatus.otpVerified ||
            r.status == BuddyRequestStatus.cancelled)
        .toList();

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFFFAF9FE)),
        Image.asset('assets/images/app_bg.jpg', fit: BoxFit.cover),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: colors.textPrimary,
              ),
              onPressed: () => context.pop(),
            ),
            centerTitle: true,
            title: Text(
              'My Buddies',
              style: typography.titleCard.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: colors.textPrimary),
                tooltip: 'Refresh',
                onPressed: () =>
                    ref.read(buddyControllerProvider.notifier).fetchMyRequests(),
              ),
            ],
          ),
          body: Column(
            children: [
              // Clean Segmented Filter Pills
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _buildTabPill(
                      index: 0,
                      label: 'Active',
                      count: allHandshakes.length,
                      colors: colors,
                    ),
                    const SizedBox(width: 8),
                    _buildTabPill(
                      index: 1,
                      label: 'Broadcasts',
                      count: openBroadcasts.length,
                      colors: colors,
                    ),
                    const SizedBox(width: 8),
                    _buildTabPill(
                      index: 2,
                      label: 'Past',
                      count: pastRequests.length,
                      colors: colors,
                    ),
                  ],
                ),
              ),

              // Tab Content Area
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () => ref
                      .read(buddyControllerProvider.notifier)
                      .fetchMyRequests(),
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      _buildHandshakesList(
                        context,
                        allHandshakes,
                        currentUserId,
                        colors,
                        typography,
                      ),
                      _buildBroadcastsList(
                        context,
                        openBroadcasts,
                        colors,
                        typography,
                      ),
                      _buildPastList(
                        context,
                        pastRequests,
                        colors,
                        typography,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // floatingActionButton: _selectedTab == 1
          //     ? FloatingActionButton.extended(
          //         onPressed: () =>
          //             CreateBuddyRequestSheet.show(context, BuddyType.movie),
          //         backgroundColor: colors.primary,
          //         icon: const Icon(Icons.add_rounded, color: Colors.white),
          //         label: const Text(
          //           'New Broadcast',
          //           style: TextStyle(
          //             fontWeight: FontWeight.bold,
          //             fontSize: 13,
          //             color: Colors.white,
          //           ),
          //         ),
          //       )
          //     : null,
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FILTER PILL
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTabPill({
    required int index,
    required String label,
    required int count,
    required AppColors colors,
  }) {
    final isSelected = _selectedTab == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedTab = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? colors.primary : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? colors.primary : colors.cardBorder,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Text(
            count > 0 ? '$label ($count)' : label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? Colors.white : colors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: ACTIVE HANDSHAKES
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildHandshakesList(
    BuildContext context,
    List<BuddyRequest> handshakes,
    String currentUserId,
    AppColors colors,
    AppTypography typography,
  ) {
    if (handshakes.isEmpty) {
      return _buildEmptyState(
        icon: Icons.handshake_outlined,
        title: 'No Active Connections',
        subtitle:
            'When someone accepts your buddy broadcast or you accept another user, your connection will appear here.',
        colors: colors,
        typography: typography,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: handshakes.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final req = handshakes[index];
        final isInitiator = req.initiatorId == currentUserId;
        return _buildHandshakeCard(
          context: context,
          request: req,
          isInitiator: isInitiator,
          colors: colors,
          typography: typography,
        );
      },
    );
  }

  Widget _buildHandshakeCard({
    required BuildContext context,
    required BuddyRequest request,
    required bool isInitiator,
    required AppColors colors,
    required AppTypography typography,
  }) {
    final type = request.buddyType;
    final partner = isInitiator ? request.accepter : request.initiator;
    final partnerId = isInitiator
        ? (partner?.id ?? request.accepterId ?? '')
        : (partner?.id ?? request.initiatorId);
    final partnerName = (partner?.fullName != null &&
            partner!.fullName.isNotEmpty &&
            partner.fullName != 'User')
        ? partner.fullName
        : 'Buddy Partner';

    final city = _capitalize(request.city);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // User & Info Row
          Row(
            children: [
              GradientAvatar(
                initials: partnerName.isNotEmpty ? partnerName[0].toUpperCase() : 'B',
                avatarSeed: partner?.avatarSeed,
                avatarStyle: partner?.avatarStyle,
                gender: partner?.gender,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partnerName,
                      style: typography.titleCard.copyWith(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.asset(
                            type.stickerAsset,
                            width: 15,
                            height: 15,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Icon(
                              Icons.local_activity,
                              size: 14,
                              color: colors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${request.displayTitle}${city.isNotEmpty ? " • $city" : ""} • ${_formatRelativeTime(request.acceptedAt ?? request.createdAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isInitiator
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.1)
                      : const Color(0xFF10B981).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isInitiator ? 'OTP Ready' : '+${request.accepterCoinReward} Coins',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isInitiator
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFF047857),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              // Chat
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
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                    label: const Text(
                      'Chat',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // OTP
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (isInitiator) {
                        InitiatorOtpModal.show(context, request: request);
                      } else {
                        AccepterOtpDialog.show(context, request: request);
                      }
                    },
                    icon: Icon(
                      isInitiator ? Icons.key_rounded : Icons.lock_open_rounded,
                      size: 15,
                    ),
                    label: Text(
                      isInitiator ? 'View OTP' : 'Enter OTP',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.textPrimary,
                      side: BorderSide(color: colors.cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: BROADCASTS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBroadcastsList(
    BuildContext context,
    List<BuddyRequest> broadcasts,
    AppColors colors,
    AppTypography typography,
  ) {
    if (broadcasts.isEmpty) {
      return _buildEmptyState(
        icon: Icons.sensors_rounded,
        title: 'No Live Broadcasts',
        subtitle:
            'Broadcast for a buddy in your city. Interested people will accept in real-time!',
        colors: colors,
        typography: typography,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
      itemCount: broadcasts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final req = broadcasts[index];
        final type = req.buddyType;
        final city = _capitalize(req.city);

        return InkWell(
          onTap: () => InitiatorOtpModal.show(context, request: req),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    type.stickerAsset,
                    width: 42,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 42,
                      height: 42,
                      color: colors.surfaceMuted,
                      child: Icon(Icons.local_activity, color: colors.primary),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              req.displayTitle,
                              style: typography.titleCard.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Live',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF047857),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${city.isNotEmpty ? "$city • " : ""}${_formatRelativeTime(req.createdAt)} • ${req.targetGender.label}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.textSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3: PAST
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPastList(
    BuildContext context,
    List<BuddyRequest> pastRequests,
    AppColors colors,
    AppTypography typography,
  ) {
    if (pastRequests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.history_rounded,
        title: 'No Past History',
        subtitle: 'Completed meetups and past connections will be listed here.',
        colors: colors,
        typography: typography,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: pastRequests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final req = pastRequests[index];
        final type = req.buddyType;
        final city = _capitalize(req.city);
        final isCompleted = req.status == BuddyRequestStatus.completed ||
            req.status == BuddyRequestStatus.otpVerified;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  type.stickerAsset,
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 38,
                    height: 38,
                    color: colors.surfaceMuted,
                    child: Icon(Icons.local_activity, color: colors.primary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      req.displayTitle,
                      style: typography.titleCard.copyWith(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${city.isNotEmpty ? "$city • " : ""}${_formatRelativeTime(req.verifiedAt ?? req.createdAt)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? const Color(0xFF10B981).withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCompleted ? 'Completed' : 'Cancelled',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isCompleted
                        ? const Color(0xFF047857)
                        : Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EMPTY STATE
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    required AppColors colors,
    required AppTypography typography,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            title,
            style: typography.titleCard.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
