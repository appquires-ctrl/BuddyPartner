import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/create_buddy_request_sheet.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

/// Festive seasonal banner for "Find Your Garba Partner".
/// Tapping directly opens [CreateBuddyRequestSheet] pre-selected with [BuddyType.garba].
class GarbaBuddyBanner extends ConsumerWidget {
  const GarbaBuddyBanner({super.key});

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();

    // 1. Subscription check
    final isSubscribed = ref.read(subscriptionStatusProvider).value?.isSubscribed ?? false;
    if (!isSubscribed) {
      AppSnackBar.showError(context, 'Active subscription required to broadcast a buddy request.');
      context.push(RouteNames.subscribe);
      return;
    }

    // 2. Coin balance check (1 coin required for special Garba promo)
    const requiredCoins = 1;
    int balance;
    final currentState = ref.read(walletBalanceProvider);
    if (currentState.hasValue) {
      balance = currentState.value!;
    } else {
      try {
        balance = await ref.read(walletBalanceProvider.notifier).fetchBalance();
      } catch (_) {
        balance = 0;
      }
    }

    if (!context.mounted) return;

    if (balance < requiredCoins) {
      AppSnackBar.showError(
        context,
        'You need at least 1 coin to broadcast a Garba buddy request. (Current balance: $balance)',
      );
      context.push(RouteNames.recharge);
      return;
    }

    // 3. Open Creation Sheet pre-selected with Garba Buddy
    CreateBuddyRequestSheet.show(context, BuddyType.garba);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _handleTap(context, ref),
          borderRadius: BorderRadius.circular(20),
          splashColor: const Color(0xFF9333EA).withValues(alpha: 0.2),
          highlightColor: const Color(0xFF6B21A8).withValues(alpha: 0.1),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6B21A8).withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 1918 / 820,
                child: Image.asset(
                  'assets/images/garba_buddy.png',
                  fit: BoxFit.contain,
                  cacheWidth: 800,
                  errorBuilder: (context, error, stackTrace) => Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6B21A8), Color(0xFF9333EA)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Find Your Garba Partner 🪔',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Find someone who matches your Garba vibes',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
