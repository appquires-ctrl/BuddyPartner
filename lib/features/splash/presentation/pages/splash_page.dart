import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';

/// SplashPage displays the application launch screen
/// with animated logo wordmark and subtitle tagline.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _navigateToNext();
  }

  void _navigateToNext() {
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        context.go(RouteNames.login);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Scaffold(
      backgroundColor: colors.surface,
      body: Stack(
        children: [
          // Top-Left blurry purple blob
          Positioned(
            top: -150,
            left: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                width: 400,
                height: 400,
                decoration: BoxDecoration(
                  color: colors.primaryGradientStart.withOpacity(1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          
          // Top-Right blurry pink blob
          Positioned(
            top: -150,
            right: -100,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
              child: Container(
                width: 350,
                height: 350,
                decoration: BoxDecoration(
                  color: colors.primaryGradientEnd.withOpacity(0.55),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),

          // Center Content
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space24,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Wordmark
                    Text(
                      'LoopCall',
                      style: typography.displayWordmark.copyWith(
                        color: colors.primary,
                        fontSize: 52,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -1.2,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 600.ms)
                        .scaleXY(begin: 0.95, end: 1.0, curve: Curves.easeOutBack),
                    
                    const SizedBox(height: AppSpacing.space16),
                    
                    // Tagline
                    Text(
                      'Talk Freely. Connect Instantly.',
                      textAlign: TextAlign.center,
                      style: typography.bodyMedium.copyWith(
                        color: colors.textSecondary,
                        fontSize: 18,
                        fontWeight: FontWeight.normal,
                        letterSpacing: 0.2,
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 300.ms, duration: 600.ms)
                        .slideY(begin: 0.1, end: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


