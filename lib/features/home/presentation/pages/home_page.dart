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
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/home/presentation/widgets/instant_connect_sheet.dart';
import 'package:buddypartner/features/home/presentation/widgets/incoming_paid_calls_banner.dart';
import 'package:buddypartner/features/chat/application/presence_provider.dart';

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

    final authUser = ref.watch(authStateProvider).value;
    final profileAsync = ref.watch(userProfileProvider);
    final matchmakingState = ref.watch(matchmakingControllerProvider);
    final instantConnectState = ref.watch(instantConnectControllerProvider);
    final matchedUsersAsync = ref.watch(matchedUsersProvider);
    
    // Ensure profile matches currently authenticated user ID to prevent stale name flash
    final profile = (profileAsync.valueOrNull?.id == authUser?.id) ? profileAsync.valueOrNull : null;
    final matchedUsers = (profile != null) ? (matchedUsersAsync.valueOrNull ?? const []) : const [];
    
    final String rawProfileName = profile?.fullName ?? '';
    final String fullName = (rawProfileName.isNotEmpty && rawProfileName != 'User')
        ? rawProfileName
        : (authUser?.fullName != null && authUser!.fullName!.trim().isNotEmpty
            ? authUser.fullName!.trim()
            : 'User');
    final String initials = getInitials(fullName);
    final bool isMatching = matchmakingState.phase == MatchmakingPhase.queued;

    // Option B: Show smooth skeleton placeholder on cold start while initial profile is loading
    final bool showSkeleton = (profileAsync.isLoading && profile == null) || (authUser == null && profile == null);

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
                    final subState = subAsync.value;
                    final isSubscribed = subState?.isSubscribed ?? false;
                    final label = isSubscribed ? subState!.formattedLabel : 'Subscribe';

                    final statusColor = isSubscribed ? colors.success : colors.danger;

                    return Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            context.push(RouteNames.subscribe);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(16.0),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.4),
                                width: 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: statusColor.withValues(alpha: 0.08),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: statusColor.withValues(alpha: 0.5),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  label,
                                  style: typography.bodySmall.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: colors.textPrimary,
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
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),

                      // Female User: Incoming Paid Calls Toggle Card
                      // Matchmaking Banner Card
                      GestureDetector(
                        onTap: _startMatchmaking,
                  child: Container(
                    height: 132,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF7A58FF),
                          Color(0xFFC69CFF),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7A58FF).withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
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
                          padding: const EdgeInsets.all(20.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // Row with Sparkle icon and MEET SOMEONE NEW
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.auto_awesome,
                                          color: Colors.white70,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'MEET SOMEONE SPECIAL',
                                          style: typography.bodySmall.copyWith(
                                            color: Colors.white.withValues(alpha: 0.85),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    // Start matchmaking heading text
                                    Text(
                                      'Let’s Connect',
                                      style: typography.titleCard.copyWith(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        height: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    // Subtitle details text
                                    Text(
                                      'Let fate choose your next connection',
                                      style: typography.bodySmall.copyWith(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontSize: 13.0,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Glassmorphic outlines icon container
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.people_outline_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                              margin: const EdgeInsets.only(top: 16),
                              height: 100,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(22),
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 14.0),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(14),
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
                                            'VIP Instant Connect ⚡',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          SizedBox(height: 2),
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
                                    const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                const SizedBox(height: 24),

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

                if (matchedUsers.isNotEmpty) ...[
                  const SizedBox(height: 24),
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
                  const SizedBox(height: 40),

                  // Centered rotating orbits radar illustration
                  const Center(
                    child: MatchingIllustration(),
                  ),
                  const SizedBox(height: 40),

                  // Heading Status text
                  Text(
                    'Ready to Make Your First Connection?',
                    style: typography.titleCard.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Helper Subtitle information
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Press Start Matchmaking to connect with someone new. After your call finishes, your recent matches will appear below.',
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const AdBannerWidget(),
                const SizedBox(height: 80),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _checkPermission();
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
    final colors = context.colors;
    final typography = context.typography;
    final profile = ref.watch(userProfileProvider).value;

    if (_isChecking) {

      return const SizedBox.shrink();
    }

    if (!_isPermissionGranted) {
      return GestureDetector(
        onTap: () => _handleLocationTap(userInitiated: true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 12,
                color: colors.primary,
              ),
              const SizedBox(width: 3),
              Text(
                'Enable Location',
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.chevron_right_rounded,
                size: 13,
                color: colors.primary,
              ),
            ],
          ),
        ),
      );
    }

    // Granted state: display city name (e.g. Jhansi)
    final String? city = _localCity ?? profile?.city;
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
    } else {
      displayCity = 'Set Location';
    }


    return GestureDetector(
      onTap: () => _handleLocationTap(userInitiated: true),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_on_rounded,
            size: 12,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              displayCity,
              style: typography.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
                color: colors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
