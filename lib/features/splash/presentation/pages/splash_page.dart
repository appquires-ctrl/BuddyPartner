import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/core/widgets/buttons/app_primary_button.dart';

/// SplashPage displays the full-bleed soft gradient launch screen
/// with animated logo wordmark, subtitle tagline, and bottom CTA button.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Scaffold(
      body: Stack(
        children: [
          // Full-bleed soft gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors.primaryGradientStart.withOpacity(0.95),
                  colors.primaryGradientEnd.withOpacity(0.95),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Screen soft layout overlay
          Positioned.fill(
            child: Container(
              color: colors.surfaceMuted.withOpacity(0.1),
            ),
          ),
          // Content layout
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space24,
                vertical: AppSpacing.space32,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(), // Spacer placeholder
                  
                  // Wordmark and tagline
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'LoopCall',
                        style: typography.displayWordmark.copyWith(
                          color: Colors.white,
                          fontSize: 48,
                          letterSpacing: -1.0,
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 600.ms)
                          .scaleXY(begin: 0.95, end: 1.0, curve: Curves.easeOutBack),
                      const SizedBox(height: AppSpacing.space12),
                      Text(
                        'Talk Freely. Connect Instantly.',
                        textAlign: TextAlign.center,
                        style: typography.bodyMedium.copyWith(
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      )
                          .animate()
                          .fadeIn(delay: 300.ms, duration: 600.ms)
                          .slideY(begin: 0.1, end: 0.0),
                    ],
                  ),

                  // Anchored Pill CTA Button
                  AppPrimaryButton(
                    text: 'Get Started',
                    onPressed: () {
                      context.go(RouteNames.login);
                    },
                  )
                      .animate()
                      .fadeIn(delay: 600.ms, duration: 600.ms)
                      .slideY(begin: 0.2, end: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
