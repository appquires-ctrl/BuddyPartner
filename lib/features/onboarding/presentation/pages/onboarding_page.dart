import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/core/widgets/buttons/app_primary_button.dart';

class _OnboardingSlide {
  final IconData icon;
  final Color themeColor;
  final String title;
  final String subtitle;
  final String description;
  final List<String> bulletPoints;

  const _OnboardingSlide({
    required this.icon,
    required this.themeColor,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.bulletPoints,
  });
}

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<_OnboardingSlide> _slides = const [
    _OnboardingSlide(
      icon: Icons.shield_outlined,
      themeColor: Color(0xFF0D9488),
      title: '100% Safe & Secure',
      subtitle: 'Zero Fake Profiles',
      description:
          'Every profile is verified with strict moderation so you only connect with real people.',
      bulletPoints: [
        'Verified and authentic profiles',
        'Active spam and fake account protection',
        'Private and secure 1-on-1 interactions',
      ],
    ),
    _OnboardingSlide(
      icon: Icons.videocam_outlined,
      themeColor: Color(0xFF2563EB),
      title: 'Connect in Real-Time',
      subtitle: 'Instant Audio & Video Calls',
      description:
          'Reach verified buddies instantly with crystal-clear audio and smooth video calling.',
      bulletPoints: [
        'High-definition video calls',
        'Low-latency voice calling',
        'Instant connection with online buddies',
      ],
    ),
    _OnboardingSlide(
      icon: Icons.favorite_border_rounded,
      themeColor: Color(0xFFE11D48),
      title: 'Find Your Buddy',
      subtitle: 'Meaningful Friendships',
      description:
          'Start conversations, discover shared interests, and enjoy a warm, welcoming community.',
      bulletPoints: [
        'Connect with like-minded friends',
        'Welcome rewards for new users',
        'Safe and respectful environment',
      ],
    ),
  ];

  Future<void> _completeOnboarding() async {
    final apiClient = ref.read(apiClientProvider);
    await apiClient.setSeenOnboarding();
    if (mounted) {
      context.go(RouteNames.login);
    }
  }

  void _onNextPressed() {
    if (_currentPage < _slides.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typography = context.typography;
    final isLastPage = _currentPage == _slides.length - 1;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // App Branding
                  Row(
                    children: [
                      const SizedBox(width: 0),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Buddy',
                              style: typography.titleCard.copyWith(
                                color: const Color(0xFF1E4FAE),
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                            TextSpan(
                              text: 'Partner',
                              style: typography.titleCard.copyWith(
                                color: const Color(0xFFE91E63),
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Skip Button
                  if (!isLastPage)
                    TextButton(
                      onPressed: _completeOnboarding,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF6B7280),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      child: Text(
                        'Skip',
                        style: typography.bodySmall.copyWith(
                          color: const Color(0xFF6B7280),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),

            // Page Content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return _buildSlide(context, slide);
                },
              ),
            ),

            // Bottom Navigation
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Page Indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (index) {
                      final isActive = index == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 3.5),
                        width: isActive ? 22.0 : 7.0,
                        height: 7.0,
                        decoration: BoxDecoration(
                          color: isActive
                              ? const Color(0xFFE91E63)
                              : const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 20),

                  // CTA Button
                  AppPrimaryButton(
                    text: isLastPage ? 'Get Started' : 'Continue',
                    icon: const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    onPressed: _onNextPressed,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(BuildContext context, _OnboardingSlide slide) {
    final typography = context.typography;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),

          // Clean Minimal Hero Icon
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: slide.themeColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                slide.icon,
                size: 42,
                color: slide.themeColor,
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Subtitle Label
          Text(
            slide.subtitle.toUpperCase(),
            textAlign: TextAlign.center,
            style: typography.bodySmall.copyWith(
              color: slide.themeColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),

          // Title
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: typography.headlineGreeting.copyWith(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF111827),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Description
          Text(
            slide.description,
            textAlign: TextAlign.center,
            style: typography.bodyMedium.copyWith(
              color: const Color(0xFF6B7280),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 32),

          // Bullet Points (Clean minimal list)
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF3F4F6)),
            ),
            child: Column(
              children: slide.bulletPoints.map((point) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 18,
                        color: slide.themeColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          point,
                          style: typography.bodyMedium.copyWith(
                            color: const Color(0xFF374151),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
