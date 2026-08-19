import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/core/widgets/buttons/app_primary_button.dart';
import 'package:buddypartner/features/subscription/domain/subscription_plan.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';

class DevSubscriptionPage extends ConsumerStatefulWidget {
  final SubscriptionPlan plan;

  const DevSubscriptionPage({
    super.key,
    required this.plan,
  });

  @override
  ConsumerState<DevSubscriptionPage> createState() => _DevSubscriptionPageState();
}

class _DevSubscriptionPageState extends ConsumerState<DevSubscriptionPage> {
  bool _isProcessing = false;

  Future<void> _handleStartSubscription() async {
    AppLogger.button('Activate Dev Plan: ${widget.plan.title}', screen: 'DevSubscriptionPage');
    setState(() => _isProcessing = true);
    final success = await ref
        .read(subscriptionStatusProvider.notifier)
        .devStartSubscription(widget.plan);

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      AppSnackBar.showSuccess(context, 'DEV MODE: ${widget.plan.title} activated successfully!');
      context.go(RouteNames.home);
    } else {
      final subState = ref.read(subscriptionStatusProvider);
      final rawErr = subState.error?.toString();
      final cleanMsg = rawErr != null
          ? rawErr.replaceAll('Exception: ', '').replaceAll('DioException: ', '')
          : 'Failed to activate subscription.';
      AppSnackBar.showError(context, cleanMsg);
    }
  }

  Future<void> _handleExpireSubscription() async {
    AppLogger.button('Expire Dev Subscription', screen: 'DevSubscriptionPage');
    setState(() => _isProcessing = true);
    final success = await ref
        .read(subscriptionStatusProvider.notifier)
        .devExpireSubscription();

    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      AppSnackBar.showInfo(context, 'DEV MODE: Subscription expired immediately!');
      context.go(RouteNames.home);
    } else {
      AppSnackBar.showError(context, 'Failed to expire dev subscription.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

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
              'Dev Checkout',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Test payment gateway simulator',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.space16),
        child: Column(
          children: [
            // Prominent DEV MODE Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.space16),
              decoration: BoxDecoration(
                color: Colors.amber.shade900.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.shade700, width: 2),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.amber.shade400, size: 28),
                      const SizedBox(width: AppSpacing.space8),
                      Text(
                        'DEV TESTING MODE',
                        style: typography.bodyMedium.copyWith(
                          color: Colors.amber.shade400,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space8),
                  Text(
                    'Real payment gateway is not wired up yet. Use the actions below to simulate subscription purchase or instant expiration.',
                    textAlign: TextAlign.center,
                    style: typography.bodySmall.copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space20),

            // Plan Summary Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.space20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected Plan',
                    style: typography.bodySmall.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  Text(
                    widget.plan.title,
                    style: typography.titleCard.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.space4),
                  Text(
                    widget.plan.description,
                    style: typography.bodySmall.copyWith(color: colors.textSecondary),
                  ),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Duration',
                        style: typography.bodyMedium.copyWith(color: colors.textSecondary),
                      ),
                      Text(
                        '${widget.plan.durationDays} ${widget.plan.durationDays == 1 ? 'day' : 'days'}',
                        style: typography.bodyMedium.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.space8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Amount',
                        style: typography.bodyMedium.copyWith(color: colors.textSecondary),
                      ),
                      Text(
                        '₹${widget.plan.priceRupees}',
                        style: typography.titleCard.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.space32),

            // Action Buttons
            AppPrimaryButton(
              text: 'Start Subscription (Dev)',
              isLoading: _isProcessing,
              onPressed: _handleStartSubscription,
            ),
            const SizedBox(height: AppSpacing.space16),
            OutlinedButton(
              onPressed: _isProcessing ? null : _handleExpireSubscription,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                side: BorderSide(color: colors.danger),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'Expire Subscription Now (Dev)',
                style: typography.bodyMedium.copyWith(color: colors.danger, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
