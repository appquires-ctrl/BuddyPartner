import 'dart:async';
import 'package:buddypartner/core/services/api_client.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
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
        print('Exception requesting location permission: $e');
      }
      return false;
    }
  }

  /// Captures current GPS coordinates, reverse geocodes to Country, State, City,
  /// and saves the result to the user's profile database ONCE.
  static Future<String?> fetchAndSaveUserLocation(WidgetRef ref) async {
    try {
      // 1. Check if location services are enabled on device
      try {
        final serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled && kDebugMode) {
          print('Location services are disabled on device.');
        }
      } catch (_) {}

      // 2. Fetch current GPS position with fallback to last known position
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } catch (posErr) {
        if (kDebugMode) {
          print('getCurrentPosition failed, trying getLastKnownPosition: $posErr');
        }
        try {
          position = await Geolocator.getLastKnownPosition();
        } catch (_) {}
      }

      if (position == null) {
        if (kDebugMode) {
          print('Could not obtain GPS position.');
        }
        return null;
      }

      String? country;
      String? state;
      String? city;

      // 3. Reverse geocode position into Country, State, City
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          country = place.country;
          state = place.administrativeArea;
          city = place.locality;

          if (city == null || city.trim().isEmpty) {
            city = place.subAdministrativeArea;
          }
          if (city == null || city.trim().isEmpty) {
            city = place.subLocality;
          }
          if (city == null || city.trim().isEmpty) {
            city = place.administrativeArea;
          }
          if (city == null || city.trim().isEmpty) {
            city = place.name;
          }
        }
      } catch (geocodeErr) {
        if (kDebugMode) {
          print('Error reverse geocoding coordinates: $geocodeErr');
        }
      }

      // 4. Save to User Profile on Backend
      try {
        final apiClient = ref.read(apiClientProvider);
        final payload = {
          'country': country,
          'state': state,
          'city': city,
          'latitude': position.latitude,
          'longitude': position.longitude,
        };

        try {
          await apiClient.dio.post('/api/auth/location', data: payload);
        } catch (postErr) {
          // Fallback to /api/auth/profile if /api/auth/location route returned 404 (e.g. backend server auto-reload pending)
          await apiClient.dio.post('/api/auth/profile', data: payload);
        }
      } catch (apiErr) {
        if (kDebugMode) {
          print('Error saving location to backend: $apiErr');
        }
      }

      // 5. Invalidate profile provider so app reflects updated location immediately
      try {
        ref.invalidate(userProfileProvider);
      } catch (_) {}

      return city;
    } catch (e) {
      if (kDebugMode) {
        print('Error in fetchAndSaveUserLocation: $e');
      }
      return null;
    }
  }

  /// Automatically checks if location permission is granted.
  /// If granted, automatically fetches current position and updates user location on backend.
  static Future<String?> checkAndUpdateLocationIfGranted(WidgetRef ref) async {
    final granted = await isLocationPermissionGranted();
    if (!granted) return null;
    return await fetchAndSaveUserLocation(ref);
  }
}
