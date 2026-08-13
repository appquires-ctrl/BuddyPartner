import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:buddypartner/core/services/location_service.dart';
import 'package:buddypartner/features/home/presentation/widgets/matching_illustration.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/home/presentation/providers/matched_users_provider.dart';
import 'package:buddypartner/features/home/presentation/widgets/matched_user_card.dart';
import 'package:buddypartner/features/home/presentation/widgets/home_skeleton.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/core/utils/app_logger.dart';

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

  Future<void> _startMatchmaking() async {
    AppLogger.click('Start Matchmaking', screen: 'HomeScreen');
    if (_isProcessingPermissions) return;

    // Step 1 — Subscription Check (Unlimited free access mode: bypassed)
    /*
    final isSub = ref.read(subscriptionStatusProvider).value?.isSubscribed ?? false;
    if (!isSub) {
      if (mounted) {
        context.push(RouteNames.subscribe);
      }
      return;
    }
    */

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
          // Step 4 — Save Location ONCE upon first location permission grant
          await LocationService.fetchAndSaveUserLocation(ref);
        }
        // If user denies location permission: do not block matchmaking. Continue requesting remaining required permissions.
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
    await ref.read(matchedUsersProvider.future).catchError((_) => <MatchedUser>[]);
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
        AppSnackBar.showError(context, next.errorMessage!);
      }
    });

    final authUser = ref.watch(authStateProvider).value;
    final profileAsync = ref.watch(userProfileProvider);
    final matchmakingState = ref.watch(matchmakingControllerProvider);
    final matchedUsersAsync = ref.watch(matchedUsersProvider);
    
    // Ensure profile matches currently authenticated user ID to prevent stale name flash
    final profile = (profileAsync.value?.id == authUser?.id) ? profileAsync.value : null;
    final matchedUsers = (profile != null) ? (matchedUsersAsync.value ?? const []) : const [];
    
    final String rawProfileName = profile?.fullName ?? '';
    final String fullName = (rawProfileName.isNotEmpty && rawProfileName != 'User')
        ? rawProfileName
        : (authUser?.fullName != null && authUser!.fullName!.trim().isNotEmpty
            ? authUser.fullName!.trim()
            : 'User');
    final String initials = getInitials(fullName);
    final bool isMatching = matchmakingState.phase == MatchmakingPhase.queued;
    
    // Show skeleton if current user profile is still loading
    final bool showSkeleton = profile == null || ((profileAsync.isLoading || matchedUsersAsync.isLoading) && !matchedUsersAsync.hasValue);

    Widget content;
    if (showSkeleton) {
      content = const HomeSkeleton();
    } else {
      content = Scaffold(
        backgroundColor: Colors.transparent,
        key: const ValueKey('home_content'),
        appBar: isMatching
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0.5,
              shadowColor: colors.border,
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
                      avatarSeed: profile.avatarSeed,
                      avatarStyle: profile.avatarStyle,
                      gender: profile.gender,
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
                // Subscription status pill (e.g. '365 days left') commented out for early access
                /*
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
                */
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
                            SizedBox(
                              width: double.infinity,
                              height: 56,
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
                                          'MEET SOMEONE NEW',
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
                                      'Start matchmaking',
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
                                      'A random voice connection awaits',
                                      style: typography.bodySmall.copyWith(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w400,
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
                  const SizedBox(height: 40),
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
                  // const SizedBox(height: 32),

                  // Lavender pull down action button
                  // GestureDetector(
                  //   onTap: _handleRefresh,
                  //   child: Container(
                  //     padding: const EdgeInsets.symmetric(
                  //       horizontal: 20,
                  //       vertical: 10,
                  //     ),
                  //     decoration: BoxDecoration(
                  //       color: const Color(0xFFF3EFFF), // light lavender fill
                  //       borderRadius: AppRadius.pill,
                  //     ),
                  //     child: Row(
                  //       mainAxisSize: MainAxisSize.min,
                  //       children: const [
                  //         Icon(
                  //           Icons.refresh,
                  //           color: Color(0xFF6B4EFF), // purple icon
                  //           size: 16,
                  //         ),
                  //         SizedBox(width: 8),
                  //         Text(
                  //           'Pull down to refresh',
                  //           style: TextStyle(
                  //             color: Color(0xFF6B4EFF), // purple text
                  //             fontSize: 12,
                  //             fontWeight: FontWeight.bold,
                  //           ),
                  //         ),
                  //       ],
                  //     ),
                  //   ),
                  // ),
                  // const SizedBox(height: 80),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
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

class _HomeLocationIndicatorState extends ConsumerState<_HomeLocationIndicator> {
  bool _isPermissionGranted = false;
  bool _isChecking = true;
  bool _isFetchingLocation = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
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
      // If granted but profile city is empty, trigger location save once
      final profile = ref.read(userProfileProvider).value;
      if (profile == null || profile.city == null || profile.city!.trim().isEmpty) {
        _fetchAndSave();
      }
    }
  }

  Future<void> _fetchAndSave() async {
    if (_isFetchingLocation) return;
    setState(() => _isFetchingLocation = true);
    await LocationService.fetchAndSaveUserLocation(ref);
    if (mounted) {
      final isGranted = await LocationService.isLocationPermissionGranted();
      setState(() {
        _isPermissionGranted = isGranted;
        _isFetchingLocation = false;
      });
    }
  }

  Future<void> _handleEnableLocationTap() async {
    final granted = await LocationService.requestLocationPermission();
    if (granted) {
      setState(() => _isPermissionGranted = true);
      await _fetchAndSave();
    } else {
      setState(() => _isPermissionGranted = false);
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
        onTap: _handleEnableLocationTap,
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

    // Granted state: display city name (e.g. Lucknow)
    final String? city = profile?.city;
    final String? state = profile?.state;
    final String? country = profile?.country;

    String displayCity;
    if (city != null && city.trim().isNotEmpty) {
      displayCity = city;
    } else if (state != null && state.trim().isNotEmpty) {
      displayCity = state;
    } else if (country != null && country.trim().isNotEmpty) {
      displayCity = country;
    } else if (_isFetchingLocation) {
      displayCity = 'Fetching...';
    } else {
      displayCity = 'Detecting...';
    }

    return GestureDetector(
      onTap: _fetchAndSave,
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
          // const SizedBox(width: 2),
          // Icon(
          //   Icons.keyboard_arrow_down_rounded,
          //   size: 13,
          //   color: colors.textSecondary,
          // ),
        ],
      ),
    );
  }
}
