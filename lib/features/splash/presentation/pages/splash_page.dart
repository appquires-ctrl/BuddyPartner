import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/core/services/api_client.dart';

import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/core/services/notification_service.dart';
import 'package:buddypartner/app/router/app_router.dart';

/// AnimatedSplashScreen renders a 3-step continuous animation sequence:
/// 1. Logo Scale-in (0.3 -> 1.0)
/// 2. Wordmark Fade-in ("BuddyPartner")
/// 3. Tagline Fade & Slide-in ("MEET · CONNECT · BE FRIENDS")
///
/// Upon completion, auto-navigates to Home, Signup, or Login based on AuthState.
class AnimatedSplashScreen extends ConsumerStatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  ConsumerState<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends ConsumerState<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  late Animation<double> _logoScaleAnimation;
  late Animation<double> _wordmarkFadeAnimation;
  late Animation<double> _taglineFadeAnimation;
  late Animation<Offset> _taglineSlideAnimation;

  bool _hasNavigated = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/app_bg.jpg'), context);
  }

  @override
  void initState() {
    super.initState();

    // Pre-fetch auth state in background so decision is ready when animation ends
    ref.read(authStateProvider.future);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    // Step 1 — Logo scale-in (0.0 to 0.40)
    _logoScaleAnimation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.40, curve: Curves.easeOutBack),
      ),
    );

    // Step 2 — Wordmark fade-in (0.35 to 0.70)
    _wordmarkFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.35, 0.70, curve: Curves.easeOut),
      ),
    );

    // Step 3 — Tagline fade & slide-up (0.65 to 0.95)
    _taglineFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.65, 0.95, curve: Curves.easeOut),
      ),
    );

    _taglineSlideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.65, 0.95, curve: Curves.easeOutCubic),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _navigateToNext();
          }
        });
      }
    });

    _controller.forward();
  }

  Future<void> _navigateToNext({bool force = false}) async {
    if (_hasNavigated) return;

    final instantPhase = ref.read(instantConnectControllerProvider).phase;
    final mmPhase = ref.read(matchmakingControllerProvider).phase;
    final isClaiming = ref.read(instantConnectControllerProvider.notifier).isClaimingOrPending;

    if (instantPhase == InstantPhase.inCall || mmPhase == MatchmakingPhase.inCall) {
      _hasNavigated = true;
      return;
    }

    // If still in the middle of claiming a surge call, wait for the socket claim to resolve
    if (isClaiming && !force) {
      debugPrint('ℹ️ [Splash] Claim in flight. Waiting for claim resolution before navigating to home.');
      return;
    }

    try {
      final hasSeenOnboarding = await ref.read(apiClientProvider).hasSeenOnboarding();
      if (!mounted) return;

      final currentInstantPhase = ref.read(instantConnectControllerProvider).phase;
      final currentMmPhase = ref.read(matchmakingControllerProvider).phase;
      if (currentInstantPhase == InstantPhase.inCall || currentMmPhase == MatchmakingPhase.inCall) {
        _hasNavigated = true;
        return;
      }

      if (!hasSeenOnboarding) {
        _hasNavigated = true;
        context.go(RouteNames.onboarding);
        return;
      }

      // Await provider initialization & revalidation before routing
      CustomUser? user = await ref.read(authStateProvider.future).catchError((_) => null);
      user ??= ref.read(authStateProvider).valueOrNull;
      if (!mounted) return;

      _hasNavigated = true;

      final bool isProfileComplete = user != null &&
          (user.isProfileComplete || (user.fullName != null && user.fullName!.trim().isNotEmpty));

      if (user != null && isProfileComplete) {
        final pendingChat = NotificationService.instance.consumePendingChat();
        if (pendingChat != null) {
          context.go(RouteNames.home);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final navContext = rootNavigatorKey.currentContext;
            if (navContext != null && navContext.mounted) {
              navContext.push(
                RouteNames.chat,
                extra: {
                  'conversationId': pendingChat.conversationId,
                  'userId': pendingChat.userId,
                  'userName': pendingChat.userName,
                  'userAvatar': pendingChat.userAvatar,
                  'avatarSeed': pendingChat.avatarSeed,
                  'avatarStyle': pendingChat.avatarStyle,
                  'gender': pendingChat.gender,
                },
              );
            }
          });
        } else {
          context.go(RouteNames.home);
        }
      } else if (user != null && !isProfileComplete) {
        NotificationService.instance.consumePendingChat(); // Clear if incomplete
        context.go(RouteNames.signup);
      } else {
        NotificationService.instance.consumePendingChat(); // Clear if unauthenticated
        context.go(RouteNames.login);
      }
    } catch (_) {
      if (mounted) {
        _hasNavigated = true;
        NotificationService.instance.consumePendingChat();
        context.go(RouteNames.login);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<InstantConnectState>(instantConnectControllerProvider, (prev, next) {
      if (next.phase == InstantPhase.inCall) {
        _hasNavigated = true;
        _controller.stop();
        if (mounted) {
          context.go(RouteNames.activeCall);
        }
      } else if (next.phase == InstantPhase.idle && _controller.isCompleted) {
        // If claim failed (e.g. already claimed by another female) and splash finished, navigate to home
        if (!_hasNavigated && mounted) {
          _navigateToNext(force: true);
        }
      }
    });

    ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      if (next.phase == MatchmakingPhase.inCall) {
        _hasNavigated = true;
        _controller.stop();
        if (mounted) {
          context.go(RouteNames.activeCall);
        }
      }
    });

    final colors = context.colors;
    final typography = context.typography;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Step 1: Logo Scale-in
              ScaleTransition(
                scale: _logoScaleAnimation,
                child: Image.asset(
                  
                  'assets/images/app_logo.png',
                  width: 160,
                  height: 160,
                ),
              ),
              const SizedBox(height: 20),

              // Step 2: Wordmark Fade-in
              FadeTransition(
                opacity: _wordmarkFadeAnimation,
                child: RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'Buddy',
                        style: typography.displayWordmark.copyWith(
                          color: const Color(0xFF1E4FAE), // Blue
                          fontSize: 32.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.0,
                          height: 1.0,
                        ),
                      ),
                      TextSpan(
                        text: 'Partner',
                        style: typography.displayWordmark.copyWith(
                          color: const Color(0xFFE91E63), // Pink
                          fontSize: 32.0,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.0,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Step 3: Tagline Fade & Slide-in
              FadeTransition(
                opacity: _taglineFadeAnimation,
                child: SlideTransition(
                  position: _taglineSlideAnimation,
                  child: Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: [
    // Left line
    Container(
      width: 30,
      height: 1.6,
      decoration: BoxDecoration(
        color: const Color(0xFF1E88E5),
        borderRadius: BorderRadius.circular(10),
      ),
    ),

    const SizedBox(width: 4),

    // Left blue dot
    Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFF1E88E5),
        shape: BoxShape.circle,
      ),
    ),

    const SizedBox(width: 5),

    Text(
      'MEET. CONNECT. BE FRIENDS.',
      style: typography.bodySmall.copyWith(
        color: const Color(0xFF4B5563),
        fontSize: 13.0,
        fontWeight: FontWeight.w700,
        letterSpacing: 2.2,
        height: 1.0,
      ),
    ),

    const SizedBox(width: 5),

    // Right pink dot
    Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: Color(0xFFE91E63),
        shape: BoxShape.circle,
      ),
    ),

    const SizedBox(width: 4),

    // Right line
    Container(
      width: 30,
      height: 1.6,
      decoration: BoxDecoration(
        color: const Color(0xFFE91E63),
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  ],
)
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Alias for backwards compatibility with existing references
typedef SplashPage = AnimatedSplashScreen;
