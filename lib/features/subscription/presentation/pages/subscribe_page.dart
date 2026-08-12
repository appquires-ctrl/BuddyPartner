import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/subscription/domain/subscription_plan.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/core/utils/app_logger.dart';

class SubscribePage extends ConsumerStatefulWidget {
  const SubscribePage({super.key});

  @override
  ConsumerState<SubscribePage> createState() => _SubscribePageState();
}

class _SubscribePageState extends ConsumerState<SubscribePage> {
  String _selectedPlanId = '1_day';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final authUser = ref.watch(authStateProvider).value;
    final subState = ref.watch(subscriptionStatusProvider).value;

    final hasClaimedIntroOffer = (authUser?.hasClaimedIntroOffer ?? false) ||
        (subState?.hasClaimedIntroOffer ?? false);

    final availablePlans = hasClaimedIntroOffer
        ? SubscriptionPlan.defaultPlans.where((plan) => plan.id != '1_day').toList()
        : SubscriptionPlan.defaultPlans;

    // Ensure selected plan exists in available plans
    if (!availablePlans.any((p) => p.id == _selectedPlanId)) {
      _selectedPlanId = availablePlans.first.id;
    }

    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Active Subscription indicator for Early Access
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.space16),
                margin: const EdgeInsets.only(bottom: AppSpacing.space16),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.space12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🎉 Unlimited Early Access Active',
                            style: typography.bodyMedium.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'All calling, matchmaking & messaging features are 100% free!',
                            style: typography.bodySmall.copyWith(
                              color: colors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Top Unlimited Access Banner
              _buildTopBanner(context),

              const SizedBox(height: 24),

              Text(
                'Select a Plan',
                style: typography.titleCard.copyWith(
                  color: colors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              // Plan Cards List
              ...SubscriptionPlan.defaultPlans.map((plan) {
                final isSelected = plan.id == _selectedPlanId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _buildPlanCard(context, plan, isSelected),
                );
              }),

              const SizedBox(height: 20),

              // Trust Badges
              _buildTrustBadges(context),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBanner(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Image.asset(
        'assets/images/subscription_banner.png',
        width: double.infinity,
        fit: BoxFit.fitWidth,
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    SubscriptionPlan plan,
    bool isSelected,
  ) {
    final colors = context.colors;
    final typography = context.typography;

    return GestureDetector(
      onTap: () {
        AppLogger.click('Select Plan: ${plan.title}', screen: 'SubscribePage');
        setState(() {
          _selectedPlanId = plan.id;
        });
        // Proceed to dev checkout on tap
        context.push(
          RouteNames.devSubscription,
          extra: plan,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 16.0),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colors.primary,
            width: 0.0,
          ),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Plan Title, Badge, Description
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
                      if (plan.badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

            // Price & Duration
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
                  '${plan.durationDays} ${plan.durationDays == 1 ? 'day' : 'days'}',
                  style: typography.bodySmall.copyWith(
                    fontSize: 11.5,
                    color: colors.textSecondary,
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: colors.primary,
            size: 18,
          ),
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
    );
  }
}

