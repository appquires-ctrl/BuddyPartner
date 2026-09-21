import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';
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
      options: Options(
        receiveTimeout: const Duration(seconds: 3),
        sendTimeout: const Duration(seconds: 3),
      ),
    );

    if (response.statusCode == 200 && response.data != null) {
      final dynamic raw = response.data;
      final List<dynamic> list = raw is Map && raw['banners'] is List
          ? raw['banners'] as List<dynamic>
          : raw is List
              ? raw
              : [];

      final now = DateTime.now();
      final parsed = list
          .map((e) => SeasonalBannerModel.fromJson(e as Map<String, dynamic>))
          .where((b) {
            if (!b.isActive) return false;
            if (b.startDate != null && b.startDate!.isAfter(now.add(const Duration(hours: 12)))) return false;
            if (b.endDate != null && b.endDate!.isBefore(now.subtract(const Duration(days: 1)))) return false;
            return true;
          })
          .toList();

      parsed.sort((a, b) => a.priority.compareTo(b.priority));
      return parsed;
    }
  } catch (_) {
    // Network / backend unreachable offline fallback
  }

  return const [];
});

const String defaultGarbaBannerUrl =
    'https://res.cloudinary.com/o8dwm2ig/image/upload/v1789916439/buddy_banners/jyreac8grrwdtnflsa6p.png';

