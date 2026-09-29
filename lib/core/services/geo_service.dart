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

  /// Synchronous local lookup for instant UI response (0ms perceived latency).
  /// Especially useful while the user is typing or when offline.
  List<CityResult> getLocalMatches({
    required String countryIso,
    String q = '',
    int limit = 20,
  }) {
    return _getFallbackCities(countryIso, q, limit);
  }

  /// Fetches cities from the backend, scoped to [countryIso] (e.g. 'IN', 'US').
  /// [q] is an optional search query (min 1 char). Returns up to [limit] results.
  ///
  /// On any network error, returns fallback cities gracefully — the UI will show
  /// matching local cities or a "Use typed city" fallback tile.
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
        final cities = (data['cities'] as List)
            .whereType<Map<String, dynamic>>()
            .map(CityResult.fromJson)
            .toList();
        if (cities.isNotEmpty) {
          if (q.trim().isNotEmpty) {
            final fallbackMatches = _getFallbackCities(countryIso, q, limit);
            final seen = cities.map((c) => c.city.toLowerCase()).toSet();
            final merged = [...cities];
            for (final fb in fallbackMatches) {
              if (!seen.contains(fb.city.toLowerCase())) {
                merged.add(fb);
                seen.add(fb.city.toLowerCase());
              }
            }
            return merged.take(limit).toList();
          }
          return cities;
        }
      }
    } on DioException catch (e) {
      // Offline or server error — fail silently so UX degrades gracefully
      debugPrintGeoError('searchCities', e.message ?? e.toString());
    } catch (e) {
      debugPrintGeoError('searchCities', e.toString());
    }
    return _getFallbackCities(countryIso, q, limit);
  }

  List<CityResult> _getFallbackCities(String countryIso, String q, int limit) {
    if (countryIso.toUpperCase() == 'IN') {
      final query = q.trim().toLowerCase();
      if (query.isEmpty) {
        return _fallbackIndianCities.take(limit).toList();
      }
      final startsWith = _fallbackIndianCities
          .where((c) => c.city.toLowerCase().startsWith(query))
          .toList();
      final contains = _fallbackIndianCities
          .where((c) =>
              !c.city.toLowerCase().startsWith(query) &&
              (c.city.toLowerCase().contains(query) ||
                  c.state.toLowerCase().contains(query)))
          .toList();
      return [...startsWith, ...contains].take(limit).toList();
    }
    return [];
  }

  static const List<CityResult> _fallbackIndianCities = [
    CityResult(city: 'Agartala', state: 'Tripura'),
    CityResult(city: 'Agra', state: 'Uttar Pradesh'),
    CityResult(city: 'Ahmedabad', state: 'Gujarat'),
    CityResult(city: 'Ahmednagar', state: 'Maharashtra'),
    CityResult(city: 'Aizawl', state: 'Mizoram'),
    CityResult(city: 'Ajmer', state: 'Rajasthan'),
    CityResult(city: 'Akola', state: 'Maharashtra'),
    CityResult(city: 'Aligarh', state: 'Uttar Pradesh'),
    CityResult(city: 'Allahabad', state: 'Uttar Pradesh'),
    CityResult(city: 'Alwar', state: 'Rajasthan'),
    CityResult(city: 'Ambala', state: 'Haryana'),
    CityResult(city: 'Amravati', state: 'Maharashtra'),
    CityResult(city: 'Amritsar', state: 'Punjab'),
    CityResult(city: 'Anand', state: 'Gujarat'),
    CityResult(city: 'Anantapur', state: 'Andhra Pradesh'),
    CityResult(city: 'Asansol', state: 'West Bengal'),
    CityResult(city: 'Aurangabad', state: 'Bihar'),
    CityResult(city: 'Aurangabad', state: 'Maharashtra'),
    CityResult(city: 'Ayodhya', state: 'Uttar Pradesh'),
    CityResult(city: 'Balasore', state: 'Odisha'),
    CityResult(city: 'Bangalore', state: 'Karnataka'),
    CityResult(city: 'Bareilly', state: 'Uttar Pradesh'),
    CityResult(city: 'Bathinda', state: 'Punjab'),
    CityResult(city: 'Belgaum', state: 'Karnataka'),
    CityResult(city: 'Bengaluru', state: 'Karnataka'),
    CityResult(city: 'Berhampur', state: 'Odisha'),
    CityResult(city: 'Bhagalpur', state: 'Bihar'),
    CityResult(city: 'Bharatpur', state: 'Rajasthan'),
    CityResult(city: 'Bharuch', state: 'Gujarat'),
    CityResult(city: 'Bhavnagar', state: 'Gujarat'),
    CityResult(city: 'Bhilai', state: 'Chhattisgarh'),
    CityResult(city: 'Bhilwara', state: 'Rajasthan'),
    CityResult(city: 'Bhopal', state: 'Madhya Pradesh'),
    CityResult(city: 'Bhubaneswar', state: 'Odisha'),
    CityResult(city: 'Bhuj', state: 'Gujarat'),
    CityResult(city: 'Bikaner', state: 'Rajasthan'),
    CityResult(city: 'Bilaspur', state: 'Chhattisgarh'),
    CityResult(city: 'Bokaro', state: 'Jharkhand'),
    CityResult(city: 'Chandigarh', state: 'Chandigarh'),
    CityResult(city: 'Chandrapur', state: 'Maharashtra'),
    CityResult(city: 'Chennai', state: 'Tamil Nadu'),
    CityResult(city: 'Chhatrapati Sambhajinagar', state: 'Maharashtra'),
    CityResult(city: 'Coimbatore', state: 'Tamil Nadu'),
    CityResult(city: 'Cuttack', state: 'Odisha'),
    CityResult(city: 'Daman', state: 'Dadra and Nagar Haveli and Daman and Diu'),
    CityResult(city: 'Darbhanga', state: 'Bihar'),
    CityResult(city: 'Darjeeling', state: 'West Bengal'),
    CityResult(city: 'Dehradun', state: 'Uttarakhand'),
    CityResult(city: 'Delhi', state: 'Delhi'),
    CityResult(city: 'Deoghar', state: 'Jharkhand'),
    CityResult(city: 'Dhanbad', state: 'Jharkhand'),
    CityResult(city: 'Dharamshala', state: 'Himachal Pradesh'),
    CityResult(city: 'Dibrugarh', state: 'Assam'),
    CityResult(city: 'Dimapur', state: 'Nagaland'),
    CityResult(city: 'Dispur', state: 'Assam'),
    CityResult(city: 'Diu', state: 'Dadra and Nagar Haveli and Daman and Diu'),
    CityResult(city: 'Durgapur', state: 'West Bengal'),
    CityResult(city: 'Faridabad', state: 'Haryana'),
    CityResult(city: 'Firozabad', state: 'Uttar Pradesh'),
    CityResult(city: 'Gandhidham', state: 'Gujarat'),
    CityResult(city: 'Gandhinagar', state: 'Gujarat'),
    CityResult(city: 'Gangtok', state: 'Sikkim'),
    CityResult(city: 'Gaya', state: 'Bihar'),
    CityResult(city: 'Ghaziabad', state: 'Uttar Pradesh'),
    CityResult(city: 'Godhra', state: 'Gujarat'),
    CityResult(city: 'Gorakhpur', state: 'Uttar Pradesh'),
    CityResult(city: 'Greater Noida', state: 'Uttar Pradesh'),
    CityResult(city: 'Gulbarga', state: 'Karnataka'),
    CityResult(city: 'Guntur', state: 'Andhra Pradesh'),
    CityResult(city: 'Gurgaon', state: 'Haryana'),
    CityResult(city: 'Guwahati', state: 'Assam'),
    CityResult(city: 'Gwalior', state: 'Madhya Pradesh'),
    CityResult(city: 'Haldwani', state: 'Uttarakhand'),
    CityResult(city: 'Haridwar', state: 'Uttarakhand'),
    CityResult(city: 'Hazaribagh', state: 'Jharkhand'),
    CityResult(city: 'Hisar', state: 'Haryana'),
    CityResult(city: 'Howrah', state: 'West Bengal'),
    CityResult(city: 'Hubli', state: 'Karnataka'),
    CityResult(city: 'Hyderabad', state: 'Telangana'),
    CityResult(city: 'Imphal', state: 'Manipur'),
    CityResult(city: 'Indore', state: 'Madhya Pradesh'),
    CityResult(city: 'Itanagar', state: 'Arunachal Pradesh'),
    CityResult(city: 'Jabalpur', state: 'Madhya Pradesh'),
    CityResult(city: 'Jaipur', state: 'Rajasthan'),
    CityResult(city: 'Jaisalmer', state: 'Rajasthan'),
    CityResult(city: 'Jalandhar', state: 'Punjab'),
    CityResult(city: 'Jalgaon', state: 'Maharashtra'),
    CityResult(city: 'Jammu', state: 'Jammu and Kashmir'),
    CityResult(city: 'Jamnagar', state: 'Gujarat'),
    CityResult(city: 'Jamshedpur', state: 'Jharkhand'),
    CityResult(city: 'Jhansi', state: 'Uttar Pradesh'),
    CityResult(city: 'Jodhpur', state: 'Rajasthan'),
    CityResult(city: 'Junagadh', state: 'Gujarat'),
    CityResult(city: 'Kakinada', state: 'Andhra Pradesh'),
    CityResult(city: 'Kalyan', state: 'Maharashtra'),
    CityResult(city: 'Kannur', state: 'Kerala'),
    CityResult(city: 'Kanpur', state: 'Uttar Pradesh'),
    CityResult(city: 'Karnal', state: 'Haryana'),
    CityResult(city: 'Kharagpur', state: 'West Bengal'),
    CityResult(city: 'Kochi', state: 'Kerala'),
    CityResult(city: 'Kohima', state: 'Nagaland'),
    CityResult(city: 'Kolhapur', state: 'Maharashtra'),
    CityResult(city: 'Kolkata', state: 'West Bengal'),
    CityResult(city: 'Kollam', state: 'Kerala'),
    CityResult(city: 'Korba', state: 'Chhattisgarh'),
    CityResult(city: 'Kota', state: 'Rajasthan'),
    CityResult(city: 'Kottayam', state: 'Kerala'),
    CityResult(city: 'Kozhikode', state: 'Kerala'),
    CityResult(city: 'Kullu', state: 'Himachal Pradesh'),
    CityResult(city: 'Kurnool', state: 'Andhra Pradesh'),
    CityResult(city: 'Latur', state: 'Maharashtra'),
    CityResult(city: 'Leh', state: 'Ladakh'),
    CityResult(city: 'Lucknow', state: 'Uttar Pradesh'),
    CityResult(city: 'Ludhiana', state: 'Punjab'),
    CityResult(city: 'Madurai', state: 'Tamil Nadu'),
    CityResult(city: 'Malegaon', state: 'Maharashtra'),
    CityResult(city: 'Manali', state: 'Himachal Pradesh'),
    CityResult(city: 'Mangalore', state: 'Karnataka'),
    CityResult(city: 'Mangaluru', state: 'Karnataka'),
    CityResult(city: 'Mathura', state: 'Uttar Pradesh'),
    CityResult(city: 'Meerut', state: 'Uttar Pradesh'),
    CityResult(city: 'Mehsana', state: 'Gujarat'),
    CityResult(city: 'Mira-Bhayandar', state: 'Maharashtra'),
    CityResult(city: 'Mohali', state: 'Punjab'),
    CityResult(city: 'Moradabad', state: 'Uttar Pradesh'),
    CityResult(city: 'Morbi', state: 'Gujarat'),
    CityResult(city: 'Mount Abu', state: 'Rajasthan'),
    CityResult(city: 'Mumbai', state: 'Maharashtra'),
    CityResult(city: 'Muzaffarnagar', state: 'Uttar Pradesh'),
    CityResult(city: 'Muzaffarpur', state: 'Bihar'),
    CityResult(city: 'Mysore', state: 'Karnataka'),
    CityResult(city: 'Mysuru', state: 'Karnataka'),
    CityResult(city: 'Nadiad', state: 'Gujarat'),
    CityResult(city: 'Nagpur', state: 'Maharashtra'),
    CityResult(city: 'Nainital', state: 'Uttarakhand'),
    CityResult(city: 'Nanded', state: 'Maharashtra'),
    CityResult(city: 'Nashik', state: 'Maharashtra'),
    CityResult(city: 'Navi Mumbai', state: 'Maharashtra'),
    CityResult(city: 'Navsari', state: 'Gujarat'),
    CityResult(city: 'Nellore', state: 'Andhra Pradesh'),
    CityResult(city: 'New Delhi', state: 'Delhi'),
    CityResult(city: 'Nizamabad', state: 'Telangana'),
    CityResult(city: 'Noida', state: 'Uttar Pradesh'),
    CityResult(city: 'Panaji', state: 'Goa'),
    CityResult(city: 'Panchkula', state: 'Haryana'),
    CityResult(city: 'Panipat', state: 'Haryana'),
    CityResult(city: 'Panvel', state: 'Maharashtra'),
    CityResult(city: 'Patan', state: 'Gujarat'),
    CityResult(city: 'Pathankot', state: 'Punjab'),
    CityResult(city: 'Patiala', state: 'Punjab'),
    CityResult(city: 'Patna', state: 'Bihar'),
    CityResult(city: 'Porbandar', state: 'Gujarat'),
    CityResult(city: 'Port Blair', state: 'Andaman and Nicobar Islands'),
    CityResult(city: 'Prayagraj', state: 'Uttar Pradesh'),
    CityResult(city: 'Puducherry', state: 'Puducherry'),
    CityResult(city: 'Pune', state: 'Maharashtra'),
    CityResult(city: 'Puri', state: 'Odisha'),
    CityResult(city: 'Purnia', state: 'Bihar'),
    CityResult(city: 'Raipur', state: 'Chhattisgarh'),
    CityResult(city: 'Rajahmundry', state: 'Andhra Pradesh'),
    CityResult(city: 'Rajkot', state: 'Gujarat'),
    CityResult(city: 'Ranchi', state: 'Jharkhand'),
    CityResult(city: 'Rishikesh', state: 'Uttarakhand'),
    CityResult(city: 'Rohtak', state: 'Haryana'),
    CityResult(city: 'Roorkee', state: 'Uttarakhand'),
    CityResult(city: 'Rourkela', state: 'Odisha'),
    CityResult(city: 'Saharanpur', state: 'Uttar Pradesh'),
    CityResult(city: 'Salem', state: 'Tamil Nadu'),
    CityResult(city: 'Sambalpur', state: 'Odisha'),
    CityResult(city: 'Sangli', state: 'Maharashtra'),
    CityResult(city: 'Secunderabad', state: 'Telangana'),
    CityResult(city: 'Shillong', state: 'Meghalaya'),
    CityResult(city: 'Shimla', state: 'Himachal Pradesh'),
    CityResult(city: 'Silchar', state: 'Assam'),
    CityResult(city: 'Siliguri', state: 'West Bengal'),
    CityResult(city: 'Silvassa', state: 'Dadra and Nagar Haveli and Daman and Diu'),
    CityResult(city: 'Solapur', state: 'Maharashtra'),
    CityResult(city: 'Sonipat', state: 'Haryana'),
    CityResult(city: 'Srinagar', state: 'Jammu and Kashmir'),
    CityResult(city: 'Surat', state: 'Gujarat'),
    CityResult(city: 'Surendranagar', state: 'Gujarat'),
    CityResult(city: 'Thane', state: 'Maharashtra'),
    CityResult(city: 'Thanjavur', state: 'Tamil Nadu'),
    CityResult(city: 'Thiruvananthapuram', state: 'Kerala'),
    CityResult(city: 'Thrissur', state: 'Kerala'),
    CityResult(city: 'Tiruchirappalli', state: 'Tamil Nadu'),
    CityResult(city: 'Tirunelveli', state: 'Tamil Nadu'),
    CityResult(city: 'Tirupati', state: 'Andhra Pradesh'),
    CityResult(city: 'Tiruppur', state: 'Tamil Nadu'),
    CityResult(city: 'Udaipur', state: 'Rajasthan'),
    CityResult(city: 'Ujjain', state: 'Madhya Pradesh'),
    CityResult(city: 'Vadodara', state: 'Gujarat'),
    CityResult(city: 'Valsad', state: 'Gujarat'),
    CityResult(city: 'Vapi', state: 'Gujarat'),
    CityResult(city: 'Varanasi', state: 'Uttar Pradesh'),
    CityResult(city: 'Vasai-Virar', state: 'Maharashtra'),
    CityResult(city: 'Vellore', state: 'Tamil Nadu'),
    CityResult(city: 'Vijayawada', state: 'Andhra Pradesh'),
    CityResult(city: 'Visakhapatnam', state: 'Andhra Pradesh'),
    CityResult(city: 'Warangal', state: 'Telangana'),
  ];

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
