import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/features/buddy/application/buddy_controller.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/create_buddy_request_sheet.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/open_buddy_requests_sheet.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

/// Horizontal scrollable row of 10 sticker activity buttons on the Home Screen.
class BuddyStickerCarousel extends ConsumerWidget {
  const BuddyStickerCarousel({super.key});

  Future<void> _onStickerTap(BuildContext context, WidgetRef ref, BuddyType type) async {
    // 1. Subscription Check (required to initiate a buddy request)
    final isSubscribed = ref.read(subscriptionStatusProvider).value?.isSubscribed ?? false;
    if (!isSubscribed) {
      AppSnackBar.showError(context, 'Active subscription required to broadcast a buddy request.');
      context.push(RouteNames.subscribe);
      return;
    }

    // 2. Coin Balance Check (100 coins required).
    // walletBalanceProvider is async — on first load .valueOrNull is null while the
    // network call is in-flight. We must await the real balance before deciding
    // to redirect, otherwise users with enough coins get wrongly sent to recharge.
    int balance;
    final currentState = ref.read(walletBalanceProvider);
    if (currentState.hasValue) {
      balance = currentState.value!;
    } else {
      // Still loading or errored — fetch now and wait for the real result.
      try {
        balance = await ref.read(walletBalanceProvider.notifier).fetchBalance();
      } catch (_) {
        balance = 0;
      }
    }

    if (!context.mounted) return;

    final requiredCoins = type.coinCost;
    if (balance < requiredCoins) {
      AppSnackBar.showError(
        context,
        'You need at least $requiredCoins coin${requiredCoins == 1 ? '' : 's'} to broadcast a buddy request. (Current balance: $balance)',
      );
      context.push(RouteNames.recharge);
      return;
    }

    // 3. Open Creation Sheet
    CreateBuddyRequestSheet.show(context, type);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final typography = context.typography;
    final buddyState = ref.watch(buddyControllerProvider);
    final openCount = buddyState.openRequests.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_activity_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'BUDDY ACTIVITIES',
                    style: typography.bodySmall.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => OpenBuddyRequestsSheet.show(context),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    children: [
                      if (openCount > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            '$openCount Live',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        'Browse',
                        style: typography.bodySmall.copyWith(
                          color: const Color(0xFF7C3AED),
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(width: 3),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: Color(0xFF7C3AED),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 2 Rows x 5 Columns Grid (All 10 roles visible at once)
        LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            const gap = 6.0;
            final itemWidth = ((availableWidth - (4 * gap)) / 5).floorToDouble();

            final row1 = BuddyType.values.take(5).toList();
            final row2 = BuddyType.values.skip(5).take(5).toList();

            return Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: row1
                      .map((type) => _buildStickerCard(context, ref, type, width: itemWidth))
                      .toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: row2
                      .map((type) => _buildStickerCard(context, ref, type, width: itemWidth))
                      .toList(),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildStickerCard(
    BuildContext context,
    WidgetRef ref,
    BuddyType type, {
    required double width,
  }) {
    final colors = context.colors;
    final shortTitle = type.title.replaceAll(' Buddy', '');

    return InkWell(
      onTap: () => _onStickerTap(context, ref, type),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: type.accentColor.withValues(alpha: 0.22),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: type.accentColor.withValues(alpha: 0.10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Sticker Image with Rounded Pastel Backdrop
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: type.accentColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(
                  type.stickerAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => Center(
                    child: Icon(
                      Icons.local_activity_rounded,
                      color: type.accentColor,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Title - Crisp dark text
            Text(
              shortTitle,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                color: colors.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),

            // 100 Coin Badge - Warm light gold pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: const Color(0xFFFDE68A),
                  width: 0.8,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppCoinIcon(size: 9.5, withGlow: false),
                  const SizedBox(width: 2.5),
                  Text(
                    '${type.coinCost}',
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFB45309),
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
