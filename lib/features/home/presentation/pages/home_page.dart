import 'package:dating_app/core/widgets/feedback/app_loading_indicator.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dating_app/features/home/presentation/widgets/matching_illustration.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';
import 'package:dating_app/features/home/presentation/providers/matched_users_provider.dart';
import 'package:dating_app/features/home/presentation/widgets/matched_user_card.dart';
import 'package:dating_app/features/home/presentation/widgets/home_skeleton.dart';
import 'package:dating_app/features/subscription/application/subscription_providers.dart';
import 'package:dating_app/core/widgets/gradient_avatar.dart';

/// HomePage renders the primary "stranger search" radar screen.
/// Matches screenshots/home.jpeg exactly.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _isRefreshing = false;

  Future<void> _startMatchmaking() async {
    final statuses = await [
      Permission.microphone,
      Permission.camera,
    ].request();

    final micGranted = statuses[Permission.microphone]?.isGranted ?? false;
    final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;

    if (!micGranted || !cameraGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone and Camera permissions are required to start matchmaking.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final isSub = ref.read(subscriptionStatusProvider).value?.isSubscribed ?? false;
    if (!isSub) {
      if (mounted) {
        context.push(RouteNames.subscribe);
      }
      return;
    }

    ref.read(matchmakingControllerProvider.notifier).joinQueue();
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
        if (next.errorMessage!.contains('SUBSCRIPTION_REQUIRED') ||
            next.errorMessage!.toLowerCase().contains('subscribe')) {
          context.push(RouteNames.subscribe);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.errorMessage!),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });

    final profileAsync = ref.watch(userProfileProvider);
    final matchmakingState = ref.watch(matchmakingControllerProvider);
    final matchedUsersAsync = ref.watch(matchedUsersProvider);
    
    final profile = profileAsync.value;
    final matchedUsers = matchedUsersAsync.value ?? const [];
    
    final String fullName = profile?.fullName ?? 'User';
    final String initials = getInitials(fullName);
    final bool isMatching = matchmakingState.phase == MatchmakingPhase.queued;
    
    // Only show skeleton on initial load (when it's loading and there's no data yet)
    final bool showSkeleton = (profileAsync.isLoading || matchedUsersAsync.isLoading) && !matchedUsersAsync.hasValue;

    Widget content;
    if (showSkeleton) {
      content = const HomeSkeleton();
    } else {
      content = Scaffold(
        key: const ValueKey('home_content'),
        appBar: isMatching
          ? AppBar(
              backgroundColor: colors.surface,
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
              backgroundColor: colors.surface,
              elevation: 0.5,
              shadowColor: colors.border,
              automaticallyImplyLeading: false,
              titleSpacing: 16.0,
              title: Row(
                children: [
                  // User Avatar ST block
                  GestureDetector(
                    onTap: () {
                      context.push(RouteNames.account);
                    },
                    child: GradientAvatar(
                      initials: initials,
                      avatarSeed: profile?.avatarSeed,
                      avatarStyle: profile?.avatarStyle,
                      gender: profile?.gender,
                      radius: 20,
                      showStatus: true,
                      isOnline: true,
                      statusIndicatorSize: 12,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // User Greeting Info
                  GestureDetector(
                    onTap: () {
                      context.push(RouteNames.account);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hey,',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          fullName,
                          style: typography.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
              actions: [
                // Balance Chip Button (Coins for Male, Roses for Female)
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
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(16.0),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
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
                                const SizedBox(width: 8),
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
