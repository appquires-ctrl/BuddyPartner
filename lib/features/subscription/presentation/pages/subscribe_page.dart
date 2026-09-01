import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/subscription/domain/subscription_plan.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/core/services/google_play_purchase_service.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/utils/app_logger.dart';

class SubscribePage extends ConsumerStatefulWidget {
  const SubscribePage({super.key});

  @override
  ConsumerState<SubscribePage> createState() => _SubscribePageState();
}

class _SubscribePageState extends ConsumerState<SubscribePage> {
  String _selectedPlanId = '1_day';

  Future<void> _handleSubscribe(SubscriptionPlan plan) async {
    final passId = 'pass_${plan.id}';
    AppLogger.button('Google Play Subscribe: ${plan.title} ($passId - ₹${plan.priceRupees})', screen: 'SubscribePage');

    await ref.read(googlePlayPurchaseProvider.notifier).buyProduct(passId, isConsumable: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/subscription_banner.jpg'), context);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<GooglePlayState>(googlePlayPurchaseProvider, (prev, next) {
      if (next.status == GooglePlayPurchaseStatus.success && next.successMessage != null) {
        AppSnackBar.showSuccess(context, next.successMessage!);
        ref.read(googlePlayPurchaseProvider.notifier).resetStatus();
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(RouteNames.home);
        }
      } else if (next.status == GooglePlayPurchaseStatus.error && next.errorMessage != null) {
        AppSnackBar.showError(context, next.errorMessage!);
        ref.read(googlePlayPurchaseProvider.notifier).resetStatus();
      }
    });

    final gpState = ref.watch(googlePlayPurchaseProvider);
    final isPurchasing = gpState.status == GooglePlayPurchaseStatus.purchasing ||
        gpState.status == GooglePlayPurchaseStatus.verifying;

    final colors = context.colors;
    final typography = context.typography;
    final authUser = ref.watch(authStateProvider).value;
    final subState = ref.watch(subscriptionStatusProvider).value;

    final hasClaimedIntroOffer =
        (authUser?.hasClaimedIntroOffer ?? false) ||
        (subState?.hasClaimedIntroOffer ?? false);

    final allPlans = SubscriptionPlan.defaultPlans;

    // Ensure selected plan exists and is available for purchase
    if (!allPlans.any((p) => p.id == _selectedPlanId) ||
        (_selectedPlanId == '1_day' && hasClaimedIntroOffer)) {
      _selectedPlanId = allPlans
          .firstWhere((p) => p.id != '1_day', orElse: () => allPlans.first)
          .id;
    }

    final selectedPlan = allPlans.firstWhere(
      (p) => p.id == _selectedPlanId,
      orElse: () => allPlans.first,
    );

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: context.canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: colors.textPrimary),
                onPressed: () => context.pop(),
              )
            : null,
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'Choose Subscription',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Select an access plan',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: isPurchasing ? null : () => _handleSubscribe(selectedPlan),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: colors.primary.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              child: isPurchasing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.lock_open_rounded, size: 20, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Subscribe with Google Play (₹${selectedPlan.priceRupees})',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Unlimited Access Banner
              _buildTopBanner(context),

              const SizedBox(height: 20),

              // Section Heading + Current Active Plan pill
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select a Plan',
                    style: typography.titleCard.copyWith(
                      color: colors.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // if (subState?.isSubscribed ?? false)
                  //   Container(
                  //     padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  //     decoration: BoxDecoration(
                  //       color: colors.primary.withValues(alpha: 0.12),
                  //       borderRadius: BorderRadius.circular(12),
                  //       border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
                  //     ),
                  //     child: Row(
                  //       mainAxisSize: MainAxisSize.min,
                  //       children: [
                  //         Icon(Icons.stars_rounded, color: colors.primary, size: 14),
                  //         const SizedBox(width: 4),
                  //         Text(
                  //           'Active: ${subState!.formattedLabel}',
                  //           style: TextStyle(
                  //             color: colors.primary,
                  //             fontSize: 11.5,
                  //             fontWeight: FontWeight.bold,
                  //           ),
                  //         ),
                  //       ],
                  //     ),
                  //   ),
                ],
              ),

              const SizedBox(height: 14),

              // Plan Cards List (Includes ₹9 1-Day Pass)
              ...allPlans.map((plan) {
                final isSelected = plan.id == _selectedPlanId;
                final isCurrentActivePlan =
                    (subState?.isSubscribed ?? false) &&
                    (subState?.planDurationDays == plan.durationDays);
                final isClaimed = (plan.id == '1_day') && hasClaimedIntroOffer;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _buildPlanCard(
                    context,
                    plan,
                    isSelected: isSelected,
                    isCurrentActivePlan: isCurrentActivePlan,
                    isClaimed: isClaimed,
                    activeLabel: isCurrentActivePlan
                        ? subState?.formattedLabel
                        : null,
                  ),
                );
              }),

              const SizedBox(height: 20),

              // Trust Badges
              _buildTrustBadges(context),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBanner(BuildContext context) {
    return AspectRatio(
      aspectRatio: 3076 / 1376,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              colors: [Color(0xFF4A34A6), Color(0xFFC74384)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Image.asset(
            'assets/images/subscription_banner.jpg',
            width: double.infinity,
            fit: BoxFit.cover,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded) return child;
              return AnimatedOpacity(
                opacity: frame == null ? 0 : 1,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    SubscriptionPlan plan, {
    required bool isSelected,
    required bool isCurrentActivePlan,
    required bool isClaimed,
    String? activeLabel,
  }) {
    final colors = context.colors;
    final typography = context.typography;

    if (isClaimed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
        decoration: BoxDecoration(
          color: colors.surfaceMuted.withValues(alpha: 1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colors.textSecondary.withValues(alpha: 0.1),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plan.title,
                        style: typography.bodyMedium.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.textSecondary.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.textSecondary.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'CLAIMED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'One-time intro offer already claimed',
                    style: typography.bodySmall.copyWith(
                      fontSize: 12.0,
                      color: colors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${plan.priceRupees}',
                  style: typography.titleCard.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colors.textSecondary.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Claimed',
                  style: typography.bodySmall.copyWith(
                    fontSize: 11.5,
                    color: colors.textSecondary.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final border = isCurrentActivePlan
        ? Border.all(color: colors.primary, width: 2.0)
        : Border.all(color: Colors.transparent, width: 0.0);

    final backgroundColor = isCurrentActivePlan
        ? colors.primary.withValues(alpha: 0.08)
        : colors.surface;

    return GestureDetector(
      onTap: () {
        AppLogger.click('Select Plan: ${plan.title}', screen: 'SubscribePage');
        setState(() {
          _selectedPlanId = plan.id;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(18),
          border: border,
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(
                alpha: isCurrentActivePlan ? 0.15 : 0.06,
              ),
              blurRadius: isCurrentActivePlan ? 12 : 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        plan.title,
                        style: typography.bodyMedium.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isCurrentActivePlan) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'CURRENT PLAN',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ] else if (plan.badge != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            plan.badge!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    plan.description,
                    style: typography.bodySmall.copyWith(
                      fontSize: 12.5,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${plan.priceRupees}',
                  style: typography.titleCard.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isCurrentActivePlan
                      ? (activeLabel ?? 'Active')
                      : '${plan.durationDays} ${plan.durationDays == 1 ? 'day' : 'days'}',
                  style: typography.bodySmall.copyWith(
                    fontSize: 11.5,
                    fontWeight: isCurrentActivePlan
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isCurrentActivePlan
                        ? colors.primary
                        : colors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrustBadges(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Secure Payment
        Expanded(
          child: _buildInlineTrustItem(
            context,
            icon: Icons.shield_outlined,
            title: 'Secure Payment',
            subtitle: '100% secure & safe',
          ),
        ),

        const SizedBox(width: 10),

        // 2. 30-Day Guarantee
        Expanded(
          child: _buildInlineTrustItem(
            context,
            icon: Icons.history_rounded,
            title: '30-Day Guarantee',
            subtitle: 'Match guaranteed',
          ),
        ),
      ],
    );
  }

  Widget _buildInlineTrustItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final colors = context.colors;
    final typography = context.typography;

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colors.primary, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: typography.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.0,
                    color: colors.textPrimary,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  softWrap: true,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: typography.bodySmall.copyWith(
                    fontSize: 11.0,
                    color: colors.textSecondary,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
