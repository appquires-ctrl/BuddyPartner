import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';


class LocationService {
  static const _storage = FlutterSecureStorage();
  static const _lastLocationSyncKey = 'last_location_sync_timestamp';

  /// Checks whether location permission is granted on the device.
  static Future<bool> isLocationPermissionGranted() async {
    try {
      final status = await Permission.locationWhenInUse.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Requests location permission. Returns true if granted.
  static Future<bool> requestLocationPermission() async {
    try {
      final status = await Permission.locationWhenInUse.request();
      return status.isGranted;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Exception requesting location permission: $e');
      }
      return false;
    }
  }

  /// Checks if location has already been fetched once in the last 24 hours.
  static Future<bool> hasFetchedLocationToday() async {
    try {
      final lastSyncStr = await _storage.read(key: _lastLocationSyncKey);
      if (lastSyncStr == null) return false;
      final lastSync = DateTime.tryParse(lastSyncStr);
      if (lastSync == null) return false;

      final difference = DateTime.now().difference(lastSync);
      // Fetch at most 1 time in a 24-hour cycle
      return difference.inHours < 24;
    } catch (_) {
      return false;
    }
  }

  /// Marks location as synced for today.
  static Future<void> _markLocationSynced() async {
    try {
      await _storage.write(
        key: _lastLocationSyncKey,
        value: DateTime.now().toIso8601String(),
      );
    } catch (_) {}
  }

  static bool _isCurrentlyFetching = false;

  /// Captures current GPS coordinates, reverse geocodes to Country, State, City,
  /// and saves the result to the user's profile database silently in the background.
  ///
  /// Rate-limited to at most 1 time per day unless [force] is set to true or user has no location set yet.
  static Future<String?> fetchAndSaveUserLocation(WidgetRef ref, {bool force = false}) async {
    ApiClient? apiClient;
    UserProfile? profile;
    try {
      apiClient = ref.read(apiClientProvider);
      profile = ref.read(userProfileProvider).value;
    } catch (_) {}

    final hasExistingLocation = profile?.city != null && profile!.city!.trim().isNotEmpty;

    if (!force && hasExistingLocation) {
      final alreadyFetchedToday = await hasFetchedLocationToday();
      if (alreadyFetchedToday) {
        if (kDebugMode) {
          debugPrint('📍 [LocationService] Location already fetched within the last 24 hours. Skipping.');
        }
        return profile.city;
      }
    }

    if (_isCurrentlyFetching) return profile?.city;
    _isCurrentlyFetching = true;

    try {
      // 1. Check if location services are enabled on device
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          _isCurrentlyFetching = false;
          return profile?.city;
        }
      } catch (_) {}

      // 2. Fetch last known position first for instant response, or accurate current position
      Position? position;
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {}

      if (position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 5),
            ),
          );
        } catch (_) {}
      }

      if (position == null) {
        _isCurrentlyFetching = false;
        return profile?.city;
      }

      String? country;
      String? state;
      String? city;

      // 3. Reverse geocode with 5-second timeout so it has ample time on mobile networks
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 5));

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          country = place.country;
          state = place.administrativeArea;
          city = place.locality ?? place.subAdministrativeArea ?? place.name;
        }
      } catch (e) {
        debugPrint('Geocoding error: $e');
      }

      // 4. Save to User Profile on Backend silently if location info was resolved
      if (city != null || state != null || country != null) {
        try {
          if (apiClient != null) {
            final payload = {
              'country': country,
              'state': state,
              'city': city,
              'latitude': position.latitude,
              'longitude': position.longitude,
            };
            await apiClient.dio.post('/api/auth/location', data: payload);
            await _markLocationSynced();
            try {
              ref.invalidate(userProfileProvider);
              ref.invalidate(authStateProvider);
            } catch (_) {}
          }
        } catch (_) {}
      }

      return city ?? profile?.city;
    } catch (_) {
      return profile?.city;
    } finally {
      _isCurrentlyFetching = false;
    }
  }

  /// Automatically checks if location permission is granted.
  /// If granted, automatically fetches current position and updates user location on backend once per day.
  static Future<String?> checkAndUpdateLocationIfGranted(WidgetRef ref, {bool force = false}) async {
    final granted = await isLocationPermissionGranted();
    if (!granted) return null;
    return await fetchAndSaveUserLocation(ref, force: force);
  }
}
