import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/services/api_client.dart';
import '../../domain/advertisement.dart';
import '../providers/advertisements_provider.dart';

class AdBannerWidget extends ConsumerStatefulWidget {
  const AdBannerWidget({super.key});

  @override
  ConsumerState<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends ConsumerState<AdBannerWidget> {
  PageController? _pageController;
  Timer? _timer;
  int _currentPage = 0;

  void _startAutoRotation(int count) {
    _timer?.cancel();
    if (count <= 1) return;

    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_pageController != null && _pageController!.hasClients) {
        _currentPage = (_currentPage + 1) % count;
        _pageController!.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _handleAdTap(Advertisement ad) async {
    debugPrint('Ad banner tapped! ID: ${ad.id}, URL: ${ad.clickUrl}');
    // 1. Fire-and-forget click tracking API call
    try {
      final client = ref.read(apiClientProvider);
      client.dio.post('/api/advertisements/${ad.id}/click');
    } catch (e) {
      debugPrint('Error recording ad click: $e');
    }

    // 2. Open click-through URL in browser
    try {
      String rawUrl = ad.clickUrl.trim();
      if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
        rawUrl = 'https://$rawUrl';
      }
      final uri = Uri.parse(rawUrl);
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!success) {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('Error launching ad URL: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final adsAsync = ref.watch(activeAdvertisementsProvider);

    return adsAsync.when(
      data: (ads) {
        if (ads.isEmpty) return const SizedBox.shrink();

        if (_pageController == null && ads.length > 1) {
          _pageController = PageController(initialPage: 0);
          _startAutoRotation(ads.length);
        }

        return Container(
          width: double.infinity,
          height: 190,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // boxShadow: [
            //   BoxShadow(
            //     color: AppColors.light.cardShadow.withValues(alpha: 0.1),
            //     blurRadius: 10,
            //     offset: const Offset(0, 4),
            //   ),
            // ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ads.length == 1
                ? _buildAdCard(ads.first)
                : PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                      });
                    },
                    itemCount: ads.length,
                    itemBuilder: (context, index) {
                      return _buildAdCard(ads[index]);
                    },
                  ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Widget _buildAdCard(Advertisement ad) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleAdTap(ad),
      child: Image.network(
        ad.imageUrl,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
