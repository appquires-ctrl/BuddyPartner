import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/subscription/domain/subscription_plan.dart';
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
  String _selectedPlanId = '1_month';

  String _getFormattedPrice(SubscriptionPlan plan, GooglePlayState gpState) {
    final p = gpState.products['membership_${plan.id}'] ??
        gpState.products['pass_${plan.id}'] ??
        gpState.products[plan.id];
    return p?.price ?? '₹${plan.totalPriceRupees}';
  }

  Future<void> _handleSubscribe(SubscriptionPlan plan) async {
    final gpState = ref.read(googlePlayPurchaseProvider);
    final membershipId = 'membership_${plan.id}';
    final passId = 'pass_${plan.id}';

    final productId = gpState.products.containsKey(membershipId)
        ? membershipId
        : (gpState.products.containsKey(passId)
            ? passId
            : (gpState.products.containsKey(plan.id) ? plan.id : membershipId));

    final displayPrice = _getFormattedPrice(plan, gpState);
    AppLogger.button(
      'Google Play Membership: ${plan.title} ($productId - $displayPrice)',
      screen: 'SubscribePage',
    );

    await ref.read(googlePlayPurchaseProvider.notifier).buyProduct(productId, isConsumable: false);
  }

  void _showOrderSummaryBottomSheet(BuildContext context, SubscriptionPlan plan) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) => _MembershipOrderSummarySheet(
        plan: plan,
        onPay: () => _handleSubscribe(plan),
      ),
    );
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
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
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
    final subState = ref.watch(subscriptionStatusProvider).value;

    final allPlans = SubscriptionPlan.defaultPlans;

    // Ensure selected plan exists in allPlans
    if (!allPlans.any((p) => p.id == _selectedPlanId)) {
      _selectedPlanId = allPlans.first.id;
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
              'Choose Membership Plan',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Select an access tier',
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
              onPressed: isPurchasing
                  ? null
                  : () => _showOrderSummaryBottomSheet(context, selectedPlan),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: colors.primary.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Continue (₹${selectedPlan.basePriceRupees})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 19, color: Colors.white),
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

              // Membership Key Perks Bar (Highlighting Switch to Video)
              _buildPerksHighlightBar(context),

              const SizedBox(height: 20),

              // Section Heading
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select a Membership Plan',
                    style: typography.titleCard.copyWith(
                      color: colors.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Plan Cards List
              ...allPlans.map((plan) {
                final isSelected = plan.id == _selectedPlanId;
                final isCurrentActivePlan =
                    (subState?.isSubscribed ?? false) &&
                    (subState?.planDurationDays == plan.durationDays);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _buildPlanCard(
                    context,
                    plan,
                    gpState,
                    isSelected: isSelected,
                    isCurrentActivePlan: isCurrentActivePlan,
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

  Widget _buildPerksHighlightBar(BuildContext context) {
    final colors = context.colors;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.primary.withValues(alpha: 0.15),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildPerkItem(
            context,
            icon: Icons.phone_in_talk_rounded,
            title: 'Unlimited Calls',
            subtitle: 'Voice connection',
            color: const Color(0xFF10B981),
          ),
          Container(width: 1, height: 28, color: colors.border.withValues(alpha: 0.5)),
          _buildPerkItem(
            context,
            icon: Icons.videocam_rounded,
            title: 'Switch to Video',
            subtitle: '1-tap in-call',
            color: const Color(0xFF8B5CF6),
          ),
          Container(width: 1, height: 28, color: colors.border.withValues(alpha: 0.5)),
          _buildPerkItem(
            context,
            icon: Icons.verified_user_rounded,
            title: '100% Safe',
            subtitle: 'Mutual consent',
            color: const Color(0xFF0EA5E9),
          ),
        ],
      ),
    );
  }

  Widget _buildPerkItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final colors = context.colors;
    final typography = context.typography;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 15),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: typography.bodySmall.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 11.0,
                color: colors.textPrimary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: typography.bodySmall.copyWith(
                fontSize: 9.0,
                color: colors.textSecondary,
                height: 1.1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlanCard(
    BuildContext context,
    SubscriptionPlan plan,
    GooglePlayState gpState, {
    required bool isSelected,
    required bool isCurrentActivePlan,
    String? activeLabel,
  }) {
    final colors = context.colors;
    final typography = context.typography;

    final border = isCurrentActivePlan
        ? Border.all(color: colors.primary, width: 2.0)
        : (isSelected
            ? Border.all(color: colors.primary, width: 2.0)
            : Border.all(color: Colors.transparent, width: 0.0));

    final backgroundColor = isCurrentActivePlan || isSelected
        ? colors.primary.withValues(alpha: 0.08)
        : colors.surface;

    return GestureDetector(
      onTap: () {
        AppLogger.click('Select Plan: ${plan.title}', screen: 'SubscribePage');
        if (_selectedPlanId == plan.id) {
          _showOrderSummaryBottomSheet(context, plan);
        } else {
          setState(() {
            _selectedPlanId = plan.id;
          });
        }
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
                alpha: isCurrentActivePlan || isSelected ? 0.15 : 0.06,
              ),
              blurRadius: isCurrentActivePlan || isSelected ? 12 : 8,
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
                  '₹${plan.basePriceRupees}',
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
                      : (plan.durationDays >= 365
                          ? '365 days'
                          : (plan.durationDays >= 180 ? '180 days' : '30 days')),
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

class _MembershipOrderSummarySheet extends ConsumerWidget {
  final SubscriptionPlan plan;
  final VoidCallback onPay;

  const _MembershipOrderSummarySheet({
    required this.plan,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final gpState = ref.watch(googlePlayPurchaseProvider);
    final isPurchasing = gpState.status == GooglePlayPurchaseStatus.purchasing ||
        gpState.status == GooglePlayPurchaseStatus.verifying;

    final totalDisplay = '₹${plan.totalPriceRupees}.00';

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sheet Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.receipt_long_rounded,
                        color: colors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Order Summary',
                      style: typography.titleCard.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: colors.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Plan Summary Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.25),
                  width: 1.2,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              plan.title,
                              style: typography.bodyMedium.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: colors.textPrimary,
                              ),
                            ),
                            if (plan.badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  plan.badge!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          plan.description,
                          style: typography.bodySmall.copyWith(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // GST Breakdown Table
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  // Base Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Base Membership Price',
                        style: typography.bodyMedium.copyWith(
                          fontSize: 14,
                          color: colors.textSecondary,
                        ),
                      ),
                      Text(
                        '₹${plan.basePriceRupees}.00',
                        style: typography.bodyMedium.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 18% GST
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Goods & Services Tax (18% GST)',
                            style: typography.bodyMedium.copyWith(
                              fontSize: 14,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '+ ₹${plan.gstRupees}.00',
                        style: typography.bodyMedium.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Divider(height: 1, thickness: 1),
                  ),

                  // Total Amount
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total Payable',
                            style: typography.bodyMedium.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Inclusive of all taxes',
                            style: typography.bodySmall.copyWith(
                              fontSize: 11,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        totalDisplay,
                        style: typography.titleCard.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Indian Tax Note
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '₹${plan.basePriceRupees} + 18% GST (₹${plan.gstRupees}) = ₹${plan.totalPriceRupees}. Billed securely through Google Play.',
                      style: typography.bodySmall.copyWith(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Pay CTA Button
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: isPurchasing ? null : onPay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: colors.primary.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 3,
                ),
                child: isPurchasing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            size: 19,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Pay $totalDisplay with Google Play',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15.5,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),

            // Security reassurance
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 13,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 5),
                Text(
                  '100% Secure Payment • Cancel anytime in Google Play',
                  style: typography.bodySmall.copyWith(
                    fontSize: 11,
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
}
