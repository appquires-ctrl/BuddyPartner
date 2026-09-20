import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/features/buddy/application/seasonal_banner_provider.dart';
import 'package:buddypartner/features/buddy/domain/seasonal_banner_model.dart';
import 'package:buddypartner/features/buddy/presentation/widgets/create_buddy_request_sheet.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/features/wallet/application/wallet_balance_provider.dart';

/// Dynamic 16:9 widescreen seasonal banner carousel.
/// Slides horizontally every 2 seconds based on active seasonal items created by admin.
/// Tapping any banner opens [CreateBuddyRequestSheet] dynamically configured with
/// title, subtitle, sticker icon, and coin cost.
class SeasonalBannerCarousel extends ConsumerStatefulWidget {
  final List<SeasonalBannerModel>? explicitBanners;

  const SeasonalBannerCarousel({
    super.key,
    this.explicitBanners,
  });

  @override
  ConsumerState<SeasonalBannerCarousel> createState() => _SeasonalBannerCarouselState();
}

class _SeasonalBannerCarouselState extends ConsumerState<SeasonalBannerCarousel> {
  late final PageController _pageController;
  Timer? _autoSlideTimer;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  void _startTimer(int itemCount) {
    _autoSlideTimer?.cancel();
    if (itemCount <= 1) return;

    _autoSlideTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_pageController.hasClients) return;
      final nextPage = (_currentPage + 1) % itemCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _stopTimer() {
    _autoSlideTimer?.cancel();
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleBannerTap(SeasonalBannerModel banner) async {
    HapticFeedback.lightImpact();

    // 1. Subscription check
    final isSubscribed = ref.read(subscriptionStatusProvider).value?.isSubscribed ?? false;
    if (!isSubscribed) {
      AppSnackBar.showError(context, 'Active subscription required to broadcast a buddy request.');
      context.push(RouteNames.subscribe);
      return;
    }

    // 2. Coin balance check against admin-configured coin cost
    final requiredCoins = banner.sheetConfig.broadcastCoinCost;
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

    if (!mounted) return;

    if (balance < requiredCoins) {
      AppSnackBar.showError(
        context,
        'You need at least $requiredCoins coin${requiredCoins == 1 ? '' : 's'} to broadcast this request. (Current balance: $balance)',
      );
      context.push(RouteNames.recharge);
      return;
    }

    // 3. Open Creation Sheet with dynamic admin details
    CreateBuddyRequestSheet.show(
      context,
      banner.sheetConfig.buddyType,
      campaignId: banner.id,
      customTitle: banner.sheetConfig.title,
      customSubtitle: banner.sheetConfig.subtitle,
      customIconUrl: banner.sheetConfig.iconUrl,
      customCoinCost: banner.sheetConfig.broadcastCoinCost,
      customAccentColor: banner.sheetConfig.accentColor,
    );
  }

  Widget _buildBannerImage(String imageUrl) {
    if (imageUrl.startsWith('http://') || imageUrl.startsWith('https://')) {
      return Image.network(
        imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: const Color(0xFF6B21A8).withValues(alpha: 0.08),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF9333EA)),
              ),
            ),
          );
        },
        errorBuilder: (_, _, _) => Image.asset(
          'assets/images/garba_buddy.png',
          fit: BoxFit.cover,
        ),
      );
    }

    return Image.asset(
      imageUrl.isNotEmpty ? imageUrl : 'assets/images/garba_buddy.png',
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Image.asset(
        'assets/images/garba_buddy.png',
        fit: BoxFit.cover,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bannersAsync = ref.watch(seasonalBannersProvider);
    final banners = widget.explicitBanners ?? bannersAsync.valueOrNull ?? [];

    if (banners.isEmpty) {
      if (bannersAsync.isLoading) {
        return AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.purple.withValues(alpha: 0.06),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    // Start timer only when multiple banners exist
    if (banners.length > 1 && (_autoSlideTimer == null || !_autoSlideTimer!.isActive)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (_autoSlideTimer == null || !_autoSlideTimer!.isActive)) {
          _startTimer(banners.length);
        }
      });
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 16:9 Aspect Ratio Widescreen Banner Container
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Listener(
            onPointerDown: (_) => _stopTimer(), // Pause auto-slide while touching
            onPointerUp: (_) => _startTimer(banners.length), // Resume on release
            onPointerCancel: (_) => _startTimer(banners.length),
            child: PageView.builder(
              controller: _pageController,
              itemCount: banners.length,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
              },
              itemBuilder: (context, index) {
                final banner = banners[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.0),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _handleBannerTap(banner),
                      borderRadius: BorderRadius.circular(20),
                      splashColor: banner.sheetConfig.accentColor.withValues(alpha: 0.2),
                      highlightColor: banner.sheetConfig.accentColor.withValues(alpha: 0.1),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: banner.sheetConfig.accentColor.withValues(alpha: 0.18),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: _buildBannerImage(banner.imageUrl),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Indicator Bar / Dots (auto-hidden if only 1 item, dynamic width if multiple)
        if (banners.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              banners.length,
              (index) {
                final isSelected = _currentPage == index;
                final activeColor = banners[_currentPage.clamp(0, banners.length - 1)].sheetConfig.accentColor;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 4,
                  width: isSelected ? 22 : 6,
                  decoration: BoxDecoration(
                    color: isSelected ? activeColor : Colors.grey.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
