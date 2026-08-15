import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

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

  Future<void> _navigateToNext() async {
    if (_hasNavigated) return;

    try {
      CustomUser? user = ref.read(authStateProvider).value;
      user ??= await ref.read(authStateProvider.future);
      if (!mounted) return;

      _hasNavigated = true;

      if (user != null && user.isProfileComplete) {
        context.go(RouteNames.home);
      } else if (user != null && !user.isProfileComplete) {
        context.go(RouteNames.signup);
      } else {
        context.go(RouteNames.login);
      }
    } catch (_) {
      if (mounted) {
        _hasNavigated = true;
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
