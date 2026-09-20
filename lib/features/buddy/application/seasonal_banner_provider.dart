import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/buddy/domain/buddy_models.dart';
import 'package:buddypartner/features/buddy/domain/seasonal_banner_model.dart';

/// Provider that fetches active seasonal banners from the backend API.
/// If the backend endpoint is offline or not yet deployed, it gracefully
/// falls back to default festive presets so the app remains fully functional.
final seasonalBannersProvider = FutureProvider<List<SeasonalBannerModel>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);

  try {
    final response = await apiClient.dio.get(
      '/api/banners/seasonal',
      queryParameters: {'placement': 'home'},
    );

    if (response.statusCode == 200 && response.data != null) {
      final dynamic raw = response.data;
      final List<dynamic> list = raw is Map && raw['banners'] is List
          ? raw['banners'] as List<dynamic>
          : raw is List
              ? raw
              : [];

      if (list.isNotEmpty) {
        final now = DateTime.now();
        final parsed = list
            .map((e) => SeasonalBannerModel.fromJson(e as Map<String, dynamic>))
            .where((b) {
              if (!b.isActive) return false;
              if (b.startDate != null && b.startDate!.isAfter(now)) return false;
              if (b.endDate != null && b.endDate!.isBefore(now)) return false;
              return true;
            })
            .toList();

        if (parsed.isNotEmpty) {
          parsed.sort((a, b) => a.priority.compareTo(b.priority));
          return parsed;
        }
      }
    }
  } catch (_) {
    // Network / backend not yet available — fallback to defaults
  }

  return _defaultSeasonalBanners;
});

final List<SeasonalBannerModel> _defaultSeasonalBanners = [
  const SeasonalBannerModel(
    id: 'garba_festive_2026',
    name: 'Find Your Garba Partner',
    imageUrl: 'assets/images/garba_buddy.png',
    priority: 1,
    sheetConfig: SeasonalSheetConfig(
      title: 'Garba Buddy 🪔',
      subtitle: 'Find someone who matches your Garba vibes',
      broadcastCoinCost: 1,
      buddyType: BuddyType.garba,
      accentColor: Color(0xFF9333EA),
    ),
    otpReward: OtpRewardConfig(
      type: OtpRewardType.staticReward,
      staticCoinAmount: 50,
    ),
  ),
];
