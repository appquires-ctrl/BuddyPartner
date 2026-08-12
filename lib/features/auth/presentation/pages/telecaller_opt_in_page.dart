import 'package:flutter/material.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';

/// TelecallerOptInPage renders the "Join as Telecaller?" onboarding step for female users.
/// Matches the reference screenshot layout and styling precisely.
class TelecallerOptInPage extends StatefulWidget {
  final bool? selectedIsTelecaller;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final bool isLoading;

  const TelecallerOptInPage({
    super.key,
    required this.selectedIsTelecaller,
    required this.onSelectionChanged,
    required this.onNext,
    required this.onBack,
    this.isLoading = false,
  });

  @override
  State<TelecallerOptInPage> createState() => _TelecallerOptInPageState();
}

class _TelecallerOptInPageState extends State<TelecallerOptInPage> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFEADBFF), // Soft lavender top gradient
            Color(0xFFF6F0FF), // Very soft lavender transition
            Colors.white,      // Pure white main section
          ],
          stops: [0.0, 0.3, 0.6],
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            // Top spacing / Header
            const SizedBox(height: AppSpacing.space24),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: AppSpacing.space32),

                    // Main Title
                    Text(
                      'Join as Partner?',
                      style: typography.headlineGreeting.copyWith(
                        fontSize: 28.0,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space8),

                    // Subtitle
                    Text(
                      'Earn coins by connecting with users through ...',
                      style: typography.bodyMedium.copyWith(
                        color: colors.textSecondary,
                        fontSize: 15.0,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space32),

                    // Option 1: Yes, I'm Interested (isTelecaller = true)
                    _buildOptionCard(
                      context: context,
                      isSelected: widget.selectedIsTelecaller == true,
                      title: "Yes, I'm Interested",
                      subtitle: 'Start earning by talking to users',
                      onTap: () => widget.onSelectionChanged(true),
                    ),

                    const SizedBox(height: AppSpacing.space16),

                    // Option 2: No, Just Chilling (isTelecaller = false)
                    _buildOptionCard(
                      context: context,
                      isSelected: widget.selectedIsTelecaller == false,
                      title: 'No, Just Chilling',
                      subtitle: 'Continue as a regular user',
                      onTap: () => widget.onSelectionChanged(false),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Navigation Buttons (Back & Next)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.space24),
              child: Row(
                children: [
                  // Back Button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.isLoading ? null : widget.onBack,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: BorderSide(
                          color: const Color(0xFFE2D8FA),
                          width: 1.5,
                        ),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        'Back',
                        style: typography.titleCard.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF8B5CF6),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: AppSpacing.space16),

                  // Next Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: widget.isLoading ? null : widget.onNext,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFF8B5CF6), // Vibrant purple
                        disabledBackgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: widget.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Next',
                              style: typography.titleCard.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required bool isSelected,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    final typography = context.typography;

    final primaryPurple = const Color(0xFF8B5CF6);
    final cardBg = isSelected ? const Color(0xFFF6F0FF) : Colors.white;
    final borderColor = isSelected ? primaryPurple : const Color(0xFFEAE5F2);
    final titleColor = isSelected ? primaryPurple : colors.textPrimary;
    final subtitleColor = isSelected ? const Color(0xFF9E86C9) : colors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppSpacing.space20),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2.0 : 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primaryPurple.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Radio Circle Indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? primaryPurple : const Color(0xFFCBD5E1),
                  width: isSelected ? 2.0 : 1.5,
                ),
                color: Colors.white,
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primaryPurple,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.space16),

            // Option Titles
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: typography.titleCard.copyWith(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: typography.bodySmall.copyWith(
                      fontSize: 13.0,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
