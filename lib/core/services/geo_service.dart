import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/api_client.dart';

// ── Provider ─────────────────────────────────────────────────────────────────
final geoServiceProvider = Provider<GeoService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return GeoService(apiClient);
});

// ── Model ─────────────────────────────────────────────────────────────────────
class CityResult {
  final String city;
  final String state;

  const CityResult({required this.city, required this.state});

  /// Display label shown in the picker list: "Mumbai, Maharashtra" or just "Singapore"
  String get displayLabel => state.isNotEmpty ? '$city, $state' : city;

  /// Normalized identifier used for socket rooms & DB storage (lowercase, trimmed)
  String get normalizedCity => city.trim().toLowerCase();
  String get normalizedState => state.trim().toLowerCase();

  factory CityResult.fromJson(Map<String, dynamic> json) {
    return CityResult(
      city: (json['city'] as String? ?? '').trim(),
      state: (json['state'] as String? ?? '').trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CityResult && other.city == city && other.state == state;

  @override
  int get hashCode => Object.hash(city, state);

  @override
  String toString() => displayLabel;
}

// ── GeoService ────────────────────────────────────────────────────────────────
class GeoService {
  final ApiClient _apiClient;

  GeoService(this._apiClient);

  /// Fetches cities from the backend, scoped to [countryIso] (e.g. 'IN', 'US').
  /// [q] is an optional search query (min 1 char). Returns up to [limit] results.
  ///
  /// On any network error, returns an empty list gracefully — the UI will show
  /// a "Use typed city" fallback tile.
  Future<List<CityResult>> searchCities({
    required String countryIso,
    String q = '',
    int limit = 20,
  }) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/geo/cities',
        queryParameters: {
          'country': countryIso.toUpperCase(),
          if (q.isNotEmpty) 'q': q.trim(),
          'limit': limit,
        },
      );

      final data = response.data;
      if (data is Map && data['cities'] is List) {
        return (data['cities'] as List)
            .whereType<Map<String, dynamic>>()
            .map(CityResult.fromJson)
            .toList();
      }
    } on DioException catch (e) {
      // Offline or server error — fail silently so UX degrades gracefully
      debugPrintGeoError('searchCities', e.message ?? e.toString());
    } catch (e) {
      debugPrintGeoError('searchCities', e.toString());
    }
    return [];
  }

  /// Fetches all state/province names for [countryIso].
  /// Used for optional state pre-filter in the city picker.
  Future<List<String>> getStates(String countryIso) async {
    try {
      final response = await _apiClient.dio.get(
        '/api/geo/states',
        queryParameters: {'country': countryIso.toUpperCase()},
      );

      final data = response.data;
      if (data is Map && data['states'] is List) {
        return List<String>.from(data['states'] as List);
      }
    } on DioException catch (e) {
      debugPrintGeoError('getStates', e.message ?? e.toString());
    } catch (e) {
      debugPrintGeoError('getStates', e.toString());
    }
    return [];
  }

  // ignore: prefer_void_to_null
  void debugPrintGeoError(String method, String msg) {
    // ignore: avoid_print
    assert(() {
      // ignore: avoid_print
      print('[GeoService] $method error: $msg');
      return true;
    }());
  }
}
