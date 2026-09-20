import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:buddypartner/core/services/location_service.dart';
import 'package:buddypartner/features/home/presentation/widgets/matching_illustration.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/home/domain/advertisement.dart';
import 'package:buddypartner/features/home/presentation/providers/advertisements_provider.dart';
import 'package:buddypartner/features/home/presentation/providers/matched_users_provider.dart';
import 'package:buddypartner/features/home/presentation/widgets/matched_user_card.dart';
import 'package:buddypartner/features/home/presentation/widgets/ad_banner_widget.dart';
import 'package:buddypartner/features/home/presentation/widgets/home_skeleton.dart';
import 'package:buddypartner/core/widgets/shimmer/app_shimmer.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/home/presentation/widgets/instant_connect_sheet.dart';
import 'package:buddypartner/features/home/presentation/widgets/incoming_paid_calls_banner.dart';
import 'package:buddypartner/features/chat/application/presence_provider.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/buddy_sticker_carousel.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/seasonal_banner_carousel.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/active_buddy_status_banner.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/initiator_otp_modal.dart';
import 'package:buddypartner/features/home/presentation/widgets/connected_duo_illustration.dart';

/// HomePage renders the primary "stranger search" radar screen.
/// Matches screenshots/home.jpeg exactly.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _isRefreshing = false;
  bool _isProcessingPermissions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authStateProvider).value;
      if (user != null && user.isFemale) {
        ref.read(instantConnectControllerProvider.notifier).fetchFemaleStatus();
        ref.read(instantConnectControllerProvider.notifier).fetchScratchCards();
      }
      final matched = ref.read(matchedUsersProvider).valueOrNull ?? [];
      if (matched.isNotEmpty) {
        final userIds = matched.map((u) => u.id).toList();
        ref.read(presenceProvider.notifier).subscribeToUsers(userIds);
      }
    });
  }

  Future<void> _startMatchmaking() async {
    AppLogger.click('Start Matchmaking', screen: 'HomeScreen');
    if (_isProcessingPermissions) return;

    // Step 1 — Subscription Check
    final isSub = ref.read(subscriptionStatusProvider).value?.isSubscribed ?? false;
    if (!isSub) {
      if (mounted) {
        context.push(RouteNames.subscribe);
      }
      return;
    }

    _isProcessingPermissions = true;
    try {
      // Step 2 & Step 3 — Permission Check and Sequential Request Order:
      // 1. Microphone Permission
      // 2. Location Permission (only if not already granted)
      // 3. Camera Permission

      // 1. Microphone Permission
      PermissionStatus micStatus;
      try {
        micStatus = await Permission.microphone.request();
      } catch (_) {
        micStatus = await Permission.microphone.status;
      }

      if (!micStatus.isGranted) {
        if (mounted) {
          AppSnackBar.showError(context, 'Microphone permission is required to start matchmaking.');
        }
        return;
      }

      // 2. Location Permission Check (Device permission status only)
      final isLocationAlreadyGranted = await LocationService.isLocationPermissionGranted();
      if (!isLocationAlreadyGranted) {
        final locGrantedNow = await LocationService.requestLocationPermission();
        if (locGrantedNow) {
          // Trigger background location update without blocking matchmaking
          LocationService.fetchAndSaveUserLocation(ref);
        }
      } else {
        // Trigger background location refresh without blocking
        LocationService.fetchAndSaveUserLocation(ref);
      }

      // 3. Camera Permission
      PermissionStatus cameraStatus;
      try {
        cameraStatus = await Permission.camera.request();
      } catch (_) {
        cameraStatus = await Permission.camera.status;
      }

      if (!cameraStatus.isGranted) {
        if (mounted) {
          AppSnackBar.showError(context, 'Camera permission is required to start matchmaking.');
        }
        return;
      }

      // All requirements satisfied, join matchmaking queue
      ref.read(matchmakingControllerProvider.notifier).joinQueue();
    } finally {
      _isProcessingPermissions = false;
    }
  }

  void _cancelMatchmaking() {
    ref.read(matchmakingControllerProvider.notifier).leaveQueue();
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    ref.invalidate(matchedUsersProvider);
    ref.invalidate(activeAdvertisementsProvider);
    await Future.wait<dynamic>([
      ref.read(matchedUsersProvider.future).catchError((_) => <MatchedUser>[]),
      ref.read(activeAdvertisementsProvider.future).catchError((_) => <Advertisement>[]),
    ]);
    if (mounted) {
      setState(() {
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      if (next.errorMessage != null &&
          next.errorMessage!.isNotEmpty &&
          (prev == null || prev.errorMessage != next.errorMessage)) {
        if (next.errorMessage!.contains('SUBSCRIPTION_REQUIRED') ||
            next.errorMessage!.toLowerCase().contains('subscribe')) {
          context.push(RouteNames.subscribe);
        } else {
          AppSnackBar.showError(context, next.errorMessage!);
        }
      }
    });

    ref.listen<AsyncValue<List<MatchedUser>>>(matchedUsersProvider, (prev, next) {
      final list = next.valueOrNull ?? [];
      if (list.isNotEmpty) {
        final userIds = list.map((u) => u.id).toList();
        ref.read(presenceProvider.notifier).subscribeToUsers(userIds);
      }
    });

    ref.listen<BuddyState>(buddyControllerProvider, (prev, next) {
      if (next.activeInitiatorRequest != null &&
          (prev == null ||
              prev.activeInitiatorRequest?.id != next.activeInitiatorRequest?.id ||
              prev.activeInitiatorRequest?.status != next.activeInitiatorRequest?.status)) {
        if (next.activeInitiatorRequest!.status == BuddyRequestStatus.accepted) {
          InitiatorOtpModal.show(context, request: next.activeInitiatorRequest!);
        }
      }
    });

    final authUser = ref.watch(authStateProvider).value;
    final profile = ref.watch(userProfileProvider);
    final matchmakingState = ref.watch(matchmakingControllerProvider);
    final instantConnectState = ref.watch(instantConnectControllerProvider);
    final matchedUsersAsync = ref.watch(matchedUsersProvider);
    
    // Matched users depend only on authenticated session, not on profile waterfall
    final matchedUsers = matchedUsersAsync.valueOrNull ?? const [];
    
    final String rawProfileName = profile?.fullName ?? '';
    final String fullName = (rawProfileName.isNotEmpty && rawProfileName != 'User')
        ? rawProfileName
        : (authUser?.fullName != null && authUser!.fullName!.trim().isNotEmpty
            ? authUser.fullName!.trim()
            : 'User');
    final String initials = getInitials(fullName);
    final bool isMatching = matchmakingState.phase == MatchmakingPhase.queued;

    // Show full skeleton only if authentication session is completely unresolved
    final bool showSkeleton = (authUser == null && profile == null);

    Widget content;
    if (showSkeleton) {
      content = HomeSkeleton(
        key: const ValueKey('home_skeleton'),
        isFemale: authUser?.isFemale,
      );
    } else {
      content = Scaffold(
        backgroundColor: Colors.transparent,
        key: const ValueKey('home_content'),
        appBar: isMatching
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              shadowColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                onPressed: _cancelMatchmaking,
              ),
              centerTitle: true,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Finding your match',
                    style: typography.titleCard.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Please stay on this screen',
                    style: typography.bodySmall.copyWith(
                      color: colors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            )
          : AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 68.0,
              shadowColor: Colors.transparent,
              automaticallyImplyLeading: false,
              titleSpacing: 16.0,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1.0),
                child: Container(
                  color: colors.border.withValues(alpha: 0.4),
                  height: 1.0,
                ),
              ),
              title: Row(
                children: [
                  // User Avatar
                  GestureDetector(
                    onTap: () {
                      context.push(RouteNames.account);
                    },
                    child: GradientAvatar(
                      initials: initials,
                      avatarSeed: profile?.avatarSeed ?? authUser?.avatarSeed,
                      avatarStyle: profile?.avatarStyle ?? authUser?.avatarStyle,
                      gender: profile?.gender ?? authUser?.gender ?? 'Male',
                      radius: 21,
                      showStatus: true,
                      isOnline: true,
                      statusIndicatorSize: 11,
                      showGlowRing: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // User Greeting Info & Location Indicator in AppBar
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            context.push(RouteNames.account);
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  fullName,
                                  style: typography.bodyMedium.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15.5,
                                    color: colors.textPrimary,
                                    height: 1.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 3),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: colors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        const _HomeLocationIndicator(),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                Consumer(
                  builder: (context, ref, child) {
                    final subAsync = ref.watch(subscriptionStatusProvider);
                    if (subAsync.isLoading && !subAsync.hasValue) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 16.0),
                        child: Center(
                          child: AppShimmer(
                            child: Container(
                              width: 96,
                              height: 32,
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(16.0),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    final subState = subAsync.value;
                    final isSubscribed = subState?.isSubscribed ?? false;
                    final label = isSubscribed ? subState!.formattedLabel : 'Subscribe';

                    return Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            context.push(RouteNames.subscribe);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 11,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16.0),
                              border: Border.all(
                                color: isSubscribed
                                    ? const Color(0xFF10B981).withValues(alpha: 0.45)
                                    : colors.danger.withValues(alpha: 0.4),
                                width: 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (isSubscribed
                                          ? const Color(0xFF10B981)
                                          : colors.danger)
                                      .withValues(alpha: 0.12),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: isSubscribed
                                        ? const Color(0xFF10B981)
                                        : colors.danger,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: (isSubscribed
                                                ? const Color(0xFF10B981)
                                                : colors.danger)
                                            .withValues(alpha: 0.7),
                                        blurRadius: 4,
                                        spreadRadius: 0.5,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                    color: isSubscribed
                                        ? const Color(0xFF047857)
                                        : colors.danger,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
      body: isMatching
          ? LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 48),

                            // Radar illustration with progress spinner in the center
                            Center(
                              child: MatchingIllustration(
                                centerWidget: const AppLoadingIndicator(
                                  size: 28,
                                  color: Color(0xFF6B4EFF),
                                ),
                              ),
                            ),

                            const SizedBox(height: 40),

                            // Looking for someone text
                            Text(
                              'Looking for someone...',
                              style: typography.titleCard.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                                color: colors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 12),

                            // Description
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0),
                              child: Text(
                                "We're checking who's available for a friendly conversation. This usually takes a few seconds.",
                                style: typography.bodySmall.copyWith(
                                  color: colors.textSecondary,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),

                            const SizedBox(height: 32),

                            // Pill badge matching mockup
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3EFFF),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const _DynamicDots(),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Matching in progress',
                                    style: TextStyle(
                                      color: const Color(0xFF6B4EFF),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Spacer(),

                            // Cancel button at bottom
                            Container(
                              width: double.infinity,
                              height: 56,
                               decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.55),
                                borderRadius: AppRadius.pill,
                                border: Border.all(
                                  color: colors.primary.withValues(alpha: 0.25),
                                  width: 1.0,
                                ),
                              ),
                              child: OutlinedButton(
                                onPressed: _cancelMatchmaking,
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: colors.border,
                                    width: 1.5,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  'Cancel search',
                                  style: typography.bodyMedium.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          : RefreshIndicator(
              onRefresh: _handleRefresh,
              color: const Color(0xFF6B4EFF),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 10),

                      // Female User: Incoming Paid Calls Toggle Card
                      // Matchmaking Banner Card — wrapped in an unclipped Stack so
                      // the couple illustration can overflow above the card boundary.
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            onTap: _startMatchmaking,
                            child: Container(
                              height: 140,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF7A58FF),
                                    Color(0xFFC69CFF),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF7A58FF).withValues(alpha: 0.35),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    // Background semi-transparent concentric circle patterns
                                    Positioned(
                                      right: -30,
                                      top: -20,
                                      child: Container(
                                        width: 140,
                                        height: 140,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white.withValues(alpha: 0.06),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.08),
                                            width: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 20,
                                      bottom: -45,
                                      child: Container(
                                        width: 110,
                                        height: 110,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.white.withValues(alpha: 0.04),
                                          border: Border.all(
                                            color: Colors.white.withValues(alpha: 0.06),
                                            width: 8,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Card Content
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 11,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                // Row with Sparkle icon and MEET SOMEONE SPECIAL
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.auto_awesome,
                                                      color: Colors.white70,
                                                      size: 13,
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Flexible(
                                                      child: Text(
                                                        'MEET SOMEONE SPECIAL',
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: typography.bodySmall.copyWith(
                                                          color: Colors.white.withValues(alpha: 0.85),
                                                          fontSize: 9.5,
                                                          fontWeight: FontWeight.w700,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 5),
                                                // Start matchmaking heading text
                                                Text(
                                                  'Let\'s Connect',
                                                  style: typography.titleCard.copyWith(
                                                    color: Colors.white,
                                                    fontSize: 22,
                                                    fontWeight: FontWeight.bold,
                                                    height: 1.15,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                // Punchier Subtitle details text
                                                Text(
                                                  'Let fate choose your next connection',
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: typography.bodySmall.copyWith(
                                                    color: Colors.white.withValues(alpha: 0.9),
                                                    fontSize: 12.0,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                // Explicit CTA button
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius: BorderRadius.circular(18),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.16),
                                                        blurRadius: 8,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: const [
                                                      Text(
                                                        'Explore Now',
                                                        style: TextStyle(
                                                          color: Color(0xFF6D28D9),
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      SizedBox(width: 4),
                                                      Icon(
                                                        Icons.arrow_forward_rounded,
                                                        size: 13,
                                                        color: Color(0xFF6D28D9),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Spacer(flex: 9),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // 3D Couple Illustration — lives OUTSIDE the ClipRRect so it
                          // overflows above the card top edge for a premium pop-out effect.
                          Positioned(
                            right: -10,
                            bottom: -10,
                            top: 2,
                            child: const ConnectedDuoIllustration(),
                          ),
                        ],
                      ),
                 if (authUser?.isFemale == true)
                        const IncomingPaidCallsBanner(),
 // Male User: VIP Instant Connect Queue or Entry Card
                      if (authUser?.isMale == true) ...[
                        if (instantConnectState.phase == InstantPhase.queued)
                          Container(
                            margin: const EdgeInsets.only(top: 16),
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(22),
                              gradient: const LinearGradient(
                                colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.bolt_rounded, color: Colors.white, size: 28),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'VIP Instant Matching...',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                          Text(
                                            'Position #${instantConnectState.queuePosition} • Coins: ${instantConnectState.bidAmount}',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  height: 40,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      ref.read(instantConnectControllerProvider.notifier).leaveQueue();
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.white, width: 1.5),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: const Text(
                                      'Cancel Search (Refund 100%)',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () {
                              InstantConnectSheet.show(context);
                            },
                            child: Container(
                              margin: const EdgeInsets.only(top: 14),
                              height: 80,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: const LinearGradient(
                                  colors: [Color.fromARGB(255, 227, 134, 27), Color.fromARGB(255, 230, 80, 0)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFEA580C).withValues(alpha: 0.35),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 0.0),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.35),
                                          width: 1,
                                        ),
                                      ),
                                      child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 28),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: const [
                                          Text(
                                            'VIP INSTANT CONNECT ⚡',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 0.3,
                                            ),
                                          ),
                                          SizedBox(height: 3),
                                          Text(
                                            'Skip the line & match with online buddies',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                const ActiveBuddyStatusBanner(),
                const SizedBox(height: 0),
                const SeasonalBannerCarousel(),
                const SizedBox(height: 0),
                const BuddyStickerCarousel(),
                const SizedBox(height: 17),

                // DISCOVER and History Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'DISCOVER',
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                        fontSize: 13,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        context.push(RouteNames.history);
                      },
                      child: Text(
                        'History',
                        style: typography.bodySmall.copyWith(
                          color: const Color(0xFF6B4EFF),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),

                if (matchedUsersAsync.isLoading && !matchedUsersAsync.hasValue) ...[
                  const SizedBox(height: 20),
                  const DiscoverRowSkeleton(),
                  const SizedBox(height: 24),
                ] else if (matchedUsers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: matchedUsers.length,
                      itemBuilder: (context, index) {
                        final user = matchedUsers[index];
                        return MatchedUserCard(user: user);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  const SizedBox(height: 18),

                  // Centered rotating orbits radar illustration (compact responsive size)
                  const Center(
                    child: MatchingIllustration(size: 180),
                  ),
                  const SizedBox(height: 18),

                  // Heading Status text
                  Text(
                    'Ready to Make Your First Connection?',
                    style: typography.titleCard.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Helper Subtitle information
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Press Start Matchmaking to connect with someone new. After your call finishes, your recent matches will appear below.',
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const AdBannerWidget(),
                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ),
    );
  }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: content,
    );
  }
}

class _DynamicDots extends StatefulWidget {
  const _DynamicDots();

  @override
  State<_DynamicDots> createState() => _DynamicDotsState();
}

class _DynamicDotsState extends State<_DynamicDots> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final double delay = index * 0.20;
            double progress = _controller.value - delay;
            if (progress < 0) progress += 1.0;
            if (progress > 1.0) progress -= 1.0;

            final double opacity = 0.2 + 0.8 * (1.0 - (progress - 0.5).abs() * 2).clamp(0.0, 1.0);

            return Opacity(
              opacity: opacity,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 1.0),
                child: Text(
                  '•',
                  style: TextStyle(
                    color: Color(0xFF6B4EFF),
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _HomeLocationIndicator extends ConsumerStatefulWidget {
  const _HomeLocationIndicator();

  @override
  ConsumerState<_HomeLocationIndicator> createState() => _HomeLocationIndicatorState();
}

class _HomeLocationIndicatorState extends ConsumerState<_HomeLocationIndicator> with WidgetsBindingObserver {
  bool _isPermissionGranted = false;
  bool _isChecking = true;
  bool _isFetchingLocation = false;
  String? _localCity;

  DateTime? _lastResumeLocationSync;
  static const Duration _resumeLocationCooldown = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastResumeLocationSync = DateTime.now();
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      if (_lastResumeLocationSync == null || now.difference(_lastResumeLocationSync!) > _resumeLocationCooldown) {
        _lastResumeLocationSync = now;
        _checkPermission();
      }
    }
  }

  Future<void> _checkPermission() async {
    final isGranted = await LocationService.isLocationPermissionGranted();
    if (mounted) {
      setState(() {
        _isPermissionGranted = isGranted;
        _isChecking = false;
      });
    }

    if (isGranted) {
      _handleLocationTap(userInitiated: false);
    }
  }

  Future<void> _handleLocationTap({bool userInitiated = true}) async {
    if (_isFetchingLocation) return;

    // 1. Check permission status & request if not granted
    bool granted = await LocationService.isLocationPermissionGranted();
    if (!granted) {
      granted = await LocationService.requestLocationPermission();
      if (!granted) {
        if (mounted) {
          setState(() {
            _isPermissionGranted = false;
          });
          if (userInitiated) {
            AppSnackBar.showError(context, 'Location permission is required to detect your location.');
          }
        }
        return;
      }
    }

    // 2. Check if Location Services / GPS are enabled on device
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          if (userInitiated) {
            AppSnackBar.showError(context, 'Please turn on Location / GPS services on your device.');
            try {
              await Geolocator.openLocationSettings();
            } catch (_) {}
          }
        }
        return;
      }
    } catch (_) {}

    // 3. Permission & GPS enabled -> Fetch exact location & update profile
    if (mounted) {
      setState(() {
        _isPermissionGranted = true;
        _isFetchingLocation = true;
      });
    }

    final updatedCity = await LocationService.fetchAndSaveUserLocation(ref, force: userInitiated);

    if (mounted) {
      setState(() {
        _isFetchingLocation = false;
        if (updatedCity != null && updatedCity.trim().isNotEmpty) {
          _localCity = updatedCity.trim();
        }
      });

      if (userInitiated) {
        if (updatedCity != null && updatedCity.trim().isNotEmpty) {
          AppSnackBar.showSuccess(context, 'Location updated: $updatedCity');
        } else {
          AppSnackBar.showError(context, 'Could not fetch exact location. Please try again.');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final authUser = ref.watch(authStateProvider).value;

    if (_isChecking) {
      return const SizedBox.shrink();
    }

    // Dynamic resolved city
    final String? city = _localCity ?? profile?.city ?? authUser?.city;
    final String? state = profile?.state;
    final String? country = profile?.country;

    String displayCity;
    if (_isFetchingLocation) {
      displayCity = 'Detecting...';
    } else if (city != null && city.trim().isNotEmpty) {
      displayCity = city.trim();
    } else if (state != null && state.trim().isNotEmpty) {
      displayCity = state.trim();
    } else if (country != null && country.trim().isNotEmpty) {
      displayCity = country.trim();
    } else if (!_isPermissionGranted) {
      displayCity = 'Enable Location';
    } else {
      displayCity = 'Set Location';
    }

    return GestureDetector(
      onTap: () => _handleLocationTap(userInitiated: true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F0FF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFFDDD6FE),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 11.5,
              color: Color(0xFF7C3AED),
            ),
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                displayCity,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11.0,
                  color: Color(0xFF6D28D9),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right_rounded,
              size: 13,
              color: Color(0xFF7C3AED),
            ),
          ],
        ),
      ),
    );
  }
}
