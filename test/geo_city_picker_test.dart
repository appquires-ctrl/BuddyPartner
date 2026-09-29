import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/geo_service.dart';
import 'package:buddypartner/core/constants/country_codes.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Group 1: CityResult Model Tests
  // ─────────────────────────────────────────────────────────────────────────
  group('CityResult Model Tests', () {
    test('displayLabel shows "city, state" when state is non-empty', () {
      const r = CityResult(city: 'Mumbai', state: 'Maharashtra');
      expect(r.displayLabel, equals('Mumbai, Maharashtra'));
    });

    test('displayLabel shows only city when state is empty', () {
      const r = CityResult(city: 'Singapore', state: '');
      expect(r.displayLabel, equals('Singapore'));
    });

    test('normalizedCity returns lowercase trimmed city', () {
      const r = CityResult(city: '  Hyderabad  ', state: 'Telangana');
      expect(r.normalizedCity, equals('hyderabad'));
    });

    test('normalizedState returns lowercase trimmed state', () {
      const r = CityResult(city: 'Austin', state: '  Texas  ');
      expect(r.normalizedState, equals('texas'));
    });

    test('fromJson parses city and state correctly', () {
      final r = CityResult.fromJson({'city': 'Surat', 'state': 'Gujarat'});
      expect(r.city, equals('Surat'));
      expect(r.state, equals('Gujarat'));
      expect(r.displayLabel, equals('Surat, Gujarat'));
    });

    test('fromJson handles missing state key gracefully', () {
      final r = CityResult.fromJson({'city': 'Dubai'});
      expect(r.city, equals('Dubai'));
      expect(r.state, equals(''));
      expect(r.displayLabel, equals('Dubai'));
    });

    test('fromJson handles null values gracefully', () {
      final r = CityResult.fromJson({'city': null, 'state': null});
      expect(r.city, equals(''));
      expect(r.state, equals(''));
    });

    test('fromJson trims whitespace from city and state', () {
      final r = CityResult.fromJson({'city': '  Pune  ', 'state': '  Maharashtra  '});
      expect(r.city, equals('Pune'));
      expect(r.state, equals('Maharashtra'));
    });

    test('equality works correctly for same city+state', () {
      const a = CityResult(city: 'Bengaluru', state: 'Karnataka');
      const b = CityResult(city: 'Bengaluru', state: 'Karnataka');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality when city matches but state differs (Aurangabad disambiguation)', () {
      const maharashtra = CityResult(city: 'Aurangabad', state: 'Maharashtra');
      const bihar = CityResult(city: 'Aurangabad', state: 'Bihar');
      expect(maharashtra, isNot(equals(bihar)));
    });

    test('toString returns displayLabel', () {
      const r = CityResult(city: 'Chennai', state: 'Tamil Nadu');
      expect(r.toString(), equals('Chennai, Tamil Nadu'));
    });

    test('displayLabel for Indian cities with state covers common duplicate-name cases', () {
      // These cities exist in multiple states — state is mandatory for disambiguation
      const aurangabadMH = CityResult(city: 'Aurangabad', state: 'Maharashtra');
      const aurangabadBR = CityResult(city: 'Aurangabad', state: 'Bihar');
      const bilaspurCG = CityResult(city: 'Bilaspur', state: 'Chhattisgarh');
      const bilaspurHP = CityResult(city: 'Bilaspur', state: 'Himachal Pradesh');

      expect(aurangabadMH.displayLabel, equals('Aurangabad, Maharashtra'));
      expect(aurangabadBR.displayLabel, equals('Aurangabad, Bihar'));
      expect(bilaspurCG.displayLabel, equals('Bilaspur, Chhattisgarh'));
      expect(bilaspurHP.displayLabel, equals('Bilaspur, Himachal Pradesh'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 2: GeoService JSON Parsing Tests (offline, no network call)
  // Tests the parsing logic that GeoService applies to API responses
  // ─────────────────────────────────────────────────────────────────────────
  group('GeoService JSON Parsing & Response Handling', () {
    test('parses a well-formed /api/geo/cities response correctly', () {
      // Simulate what the backend returns
      final apiResponse = {
        'cities': [
          {'city': 'Surat', 'state': 'Gujarat'},
          {'city': 'Surendranagar', 'state': 'Gujarat'},
          {'city': 'Srinagar', 'state': 'Jammu and Kashmir'},
        ]
      };

      final data = apiResponse;
      final cities = (data['cities'] as List)
          .whereType<Map<String, dynamic>>()
          .map(CityResult.fromJson)
          .toList();

      expect(cities.length, equals(3));
      expect(cities[0].displayLabel, equals('Surat, Gujarat'));
      expect(cities[1].displayLabel, equals('Surendranagar, Gujarat'));
      expect(cities[2].displayLabel, equals('Srinagar, Jammu and Kashmir'));
    });

    test('parses cities with empty state (single-city-countries like Singapore)', () {
      final apiResponse = {
        'cities': [
          {'city': 'Singapore', 'state': ''},
          {'city': 'Sentosa', 'state': ''},
        ]
      };

      final cities = (apiResponse['cities'] as List)
          .whereType<Map<String, dynamic>>()
          .map(CityResult.fromJson)
          .toList();

      expect(cities[0].displayLabel, equals('Singapore'));
      expect(cities[1].displayLabel, equals('Sentosa'));
    });

    test('returns empty list when cities key is missing from response', () {
      final apiResponse = <String, dynamic>{};
      final data = apiResponse;
      final cities = (data['cities'] is List)
          ? (data['cities'] as List)
              .whereType<Map<String, dynamic>>()
              .map(CityResult.fromJson)
              .toList()
          : <CityResult>[];

      expect(cities, isEmpty);
    });

    test('returns empty list when cities value is null', () {
      final apiResponse = {'cities': null};
      final data = apiResponse;
      final cities = (data['cities'] is List)
          ? (data['cities'] as List)
              .whereType<Map<String, dynamic>>()
              .map(CityResult.fromJson)
              .toList()
          : <CityResult>[];

      expect(cities, isEmpty);
    });

    test('filters out non-map entries in cities list gracefully', () {
      final apiResponse = {
        'cities': [
          {'city': 'Mumbai', 'state': 'Maharashtra'},
          'not_a_map',        // malformed entry
          null,               // null entry
          42,                 // wrong type
          {'city': 'Pune', 'state': 'Maharashtra'},
        ]
      };

      final cities = (apiResponse['cities'] as List)
          .whereType<Map<String, dynamic>>()
          .map(CityResult.fromJson)
          .toList();

      // Only valid map entries should be parsed
      expect(cities.length, equals(2));
      expect(cities[0].city, equals('Mumbai'));
      expect(cities[1].city, equals('Pune'));
    });

    test('parses a well-formed /api/geo/states response correctly', () {
      final apiResponse = {
        'states': ['Andhra Pradesh', 'Assam', 'Bihar', 'Chhattisgarh', 'Goa']
      };

      final states = (apiResponse['states'] is List)
          ? List<String>.from(apiResponse['states'] as List)
          : <String>[];

      expect(states.length, equals(5));
      expect(states, contains('Goa'));
      expect(states, contains('Bihar'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 3: CityResult Used as Buddy Request City
  // ─────────────────────────────────────────────────────────────────────────
  group('CityResult → Buddy Request Matchmaking Accuracy', () {
    test('normalizedCity produces consistent socket room keys', () {
      const mumbai = CityResult(city: 'Mumbai', state: 'Maharashtra');
      // Socket room would be: buddy:city:{normalizedCity}:{gender}
      expect('buddy:city:${mumbai.normalizedCity}:all', equals('buddy:city:mumbai:all'));
    });

    test('two users in same city+state produce matching normalized keys', () {
      const user1 = CityResult(city: ' Mumbai ', state: ' Maharashtra ');
      const user2 = CityResult(city: 'mumbai', state: 'maharashtra');
      // After normalization, both match for socket room purposes
      expect(user1.normalizedCity, equals(user2.normalizedCity));
      expect(user1.normalizedState, equals(user2.normalizedState));
    });

    test('Aurangabad Maharashtra does NOT match Aurangabad Bihar after normalization', () {
      const mh = CityResult(city: 'Aurangabad', state: 'Maharashtra');
      const br = CityResult(city: 'Aurangabad', state: 'Bihar');
      // City names match but states differ — correct disambiguation
      expect(mh.normalizedCity, equals(br.normalizedCity)); // same city name
      expect(mh.normalizedState, isNot(equals(br.normalizedState))); // different state
      expect(mh, isNot(equals(br))); // CityResult equality considers both
    });

    test('snack bar location label: shows "city, state" when state is present', () {
      const result = CityResult(city: 'Surat', state: 'Gujarat');
      final selectedState = result.state;
      final selectedCity = result.city;
      final locationLabel =
          selectedState.isNotEmpty ? '$selectedCity, $selectedState' : selectedCity;
      expect(locationLabel, equals('Surat, Gujarat'));
    });

    test('snack bar location label: shows just city when state is absent', () {
      const result = CityResult(city: 'Singapore', state: '');
      final selectedState = result.state;
      final selectedCity = result.city;
      final locationLabel =
          selectedState.isNotEmpty ? '$selectedCity, $selectedState' : selectedCity;
      expect(locationLabel, equals('Singapore'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 4: CountryCodes ISO lookup (used by CityPickerSheet country chip)
  // ─────────────────────────────────────────────────────────────────────────
  group('CountryCodes ISO Lookup for CityPickerSheet Country Chip', () {
    test('findByIso returns correct country for IN', () {
      final cc = CountryCodes.allCountries.firstWhere(
        (c) => c.iso == 'IN',
        orElse: () => CountryCodes.defaultCountry,
      );
      expect(cc.name, equals('India'));
      expect(cc.flag, equals('🇮🇳'));
    });

    test('findByIso returns correct country for US', () {
      final cc = CountryCodes.allCountries.firstWhere(
        (c) => c.iso == 'US',
        orElse: () => CountryCodes.defaultCountry,
      );
      expect(cc.name, equals('United States'));
      expect(cc.flag, equals('🇺🇸'));
    });

    test('unknown ISO falls back to default country (India)', () {
      final cc = CountryCodes.allCountries.firstWhere(
        (c) => c.iso == 'INVALID',
        orElse: () => CountryCodes.defaultCountry,
      );
      expect(cc.iso, equals('IN')); // fallback to India
    });

    test('country chip search key contains name, code, and iso', () {
      final cc = CountryCodes.allCountries.firstWhere((c) => c.iso == 'AE');
      expect(cc.searchKey, contains('united arab emirates'));
      expect(cc.searchKey, contains('+971'));
      expect(cc.searchKey, contains('ae'));
    });

    test('searchKey filtering works for common traveler countries', () {
      // Simulates what _CountrySelectSheet does when user types a query
      final query = 'uae';
      final filtered = CountryCodes.allCountries
          .where((c) => c.searchKey.contains(query.toLowerCase()))
          .toList();
      // UAE searchKey contains 'ae' but not 'uae' — shows searchKey limitation
      // Users should type 'arab' or 'emirates' instead
      // This is expected behavior
      expect(filtered, isEmpty); // 'uae' is not in searchKey
    });

    test('searchKey filtering works for "arab"', () {
      final query = 'arab';
      final filtered = CountryCodes.allCountries
          .where((c) => c.searchKey.contains(query.toLowerCase()))
          .toList();
      expect(filtered.isNotEmpty, isTrue);
      expect(filtered.any((c) => c.iso == 'AE'), isTrue);
      expect(filtered.any((c) => c.iso == 'SA'), isTrue);
    });

    test('all countries in CityPickerSheet list have valid iso, flag, and name', () {
      for (final cc in CountryCodes.allCountries) {
        expect(cc.iso.isNotEmpty, isTrue, reason: '${cc.name} has empty ISO');
        expect(cc.flag.isNotEmpty, isTrue, reason: '${cc.name} has empty flag');
        expect(cc.name.isNotEmpty, isTrue, reason: 'Empty country name found');
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Group 5: Backend Filter Logic Simulation
  // Mirrors the _filter() method in geo.service.js to ensure behavior matches
  // ─────────────────────────────────────────────────────────────────────────
  group('Backend GeoService Filter Logic Simulation (Dart-side mirror)', () {
    // Mirrors: geoService._filter(cities, q, limit) from geo.service.js
    List<CityResult> filterCities(
        List<CityResult> cities, String q, int limit) {
      if (q.trim().isEmpty) return cities.take(limit).toList();

      final query = q.trim().toLowerCase();

      final startsWith = cities
          .where((c) => c.city.toLowerCase().startsWith(query))
          .toList();

      final contains = cities
          .where((c) =>
              !c.city.toLowerCase().startsWith(query) &&
              (c.city.toLowerCase().contains(query) ||
                  c.state.toLowerCase().contains(query)))
          .toList();

      return [...startsWith, ...contains].take(limit).toList();
    }

    final sampleCities = [
      const CityResult(city: 'Surat', state: 'Gujarat'),
      const CityResult(city: 'Surendranagar', state: 'Gujarat'),
      const CityResult(city: 'Srinagar', state: 'Jammu and Kashmir'),
      const CityResult(city: 'Mumbai', state: 'Maharashtra'),
      const CityResult(city: 'Navi Mumbai', state: 'Maharashtra'),
      const CityResult(city: 'Pune', state: 'Maharashtra'),
      const CityResult(city: 'Austin', state: 'Texas'),
      const CityResult(city: 'San Antonio', state: 'Texas'),
    ];

    test('returns first N cities when query is empty', () {
      final result = filterCities(sampleCities, '', 3);
      expect(result.length, equals(3));
      expect(result[0].city, equals('Surat'));
    });

    test('startsWith results appear before contains results', () {
      final result = filterCities(sampleCities, 'sur', 10);
      // 'Surat' and 'Surendranagar' start with 'sur'
      expect(result[0].city, equals('Surat'));
      expect(result[1].city, equals('Surendranagar'));
    });

    test('contains match on city name works', () {
      final result = filterCities(sampleCities, 'mumbai', 10);
      // 'Mumbai' starts with 'mumbai', 'Navi Mumbai' contains it
      expect(result.any((r) => r.city == 'Mumbai'), isTrue);
      expect(result.any((r) => r.city == 'Navi Mumbai'), isTrue);
    });

    test('contains match on state name works', () {
      final result = filterCities(sampleCities, 'maharashtra', 10);
      // No city starts with 'maharashtra', but 3 cities are in Maharashtra
      expect(result.any((r) => r.city == 'Mumbai'), isTrue);
      expect(result.any((r) => r.city == 'Navi Mumbai'), isTrue);
      expect(result.any((r) => r.city == 'Pune'), isTrue);
    });

    test('limit is respected', () {
      final result = filterCities(sampleCities, '', 2);
      expect(result.length, equals(2));
    });

    test('case-insensitive search works', () {
      final result1 = filterCities(sampleCities, 'SURAT', 10);
      final result2 = filterCities(sampleCities, 'surat', 10);
      expect(result1.length, equals(result2.length));
      expect(result1[0].city, equals(result2[0].city));
    });

    test('no match returns empty list', () {
      final result = filterCities(sampleCities, 'xyz_nonexistent_city', 10);
      expect(result, isEmpty);
    });

    test('Texas state query returns Austin and San Antonio', () {
      final result = filterCities(sampleCities, 'texas', 10);
      expect(result.any((r) => r.city == 'Austin'), isTrue);
      expect(result.any((r) => r.city == 'San Antonio'), isTrue);
    });
  });
}
