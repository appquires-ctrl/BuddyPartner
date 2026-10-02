import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';
import 'package:buddypartner/core/utils/app_logger.dart';

/// Centralized service for Meta / Facebook App Events tracking.
/// Handles install tracking, user location (city), membership, and coin purchase events.
class MetaEventsService {
  MetaEventsService._();

  static final FacebookAppEvents _fb = FacebookAppEvents();
  static bool _isInitialized = false;

  static FacebookAppEvents get instance => _fb;
  static bool get isInitialized => _isInitialized;

  /// 1. Initialize Meta SDK and enable auto event logging & advertiser tracking
  static Future<void> initialize() async {
    try {
      await _fb.setAutoLogAppEventsEnabled(true);
      await _fb.setAdvertiserIdCollectionEnabled(true);
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('✅ [MetaEventsService] Meta App Events SDK initialized successfully.');
      }
    } catch (e, stack) {
      AppLogger.error('Failed to initialize MetaEventsService', e, stack);
    }
  }

  /// 1. Explicit App Install / Launch Event
  static Future<void> trackAppLaunch({Map<String, dynamic>? parameters}) async {
    try {
      await _fb.logEvent(
        name: 'fb_mobile_activate_app',
        parameters: parameters,
      );
      if (kDebugMode) {
        debugPrint('🎯 [MetaEvent] App Launch / Install tracked');
      }
    } catch (e) {
      debugPrint('❌ [MetaEvent Error] trackAppLaunch: $e');
    }
  }

  /// 2. City of User Event & Advanced Matching
  /// Updates user data in Meta for advanced matching and logs custom 'user_city' event.
  static Future<void> trackUserCity(
    String city, {
    String? state,
    String? country,
  }) async {
    final cleanCity = city.trim();
    if (cleanCity.isEmpty) return;

    try {
      // Set User Data in Meta for Advanced Matching
      await _fb.setUserData(
        city: cleanCity.toLowerCase(),
        state: state?.trim().toLowerCase(),
        country: country?.trim().toLowerCase(),
      );

      // Log event in Meta Events Manager
      await _fb.logEvent(
        name: 'user_city',
        parameters: {
          'city': cleanCity,
          if (state != null && state.trim().isNotEmpty) 'state': state.trim(),
          if (country != null && country.trim().isNotEmpty) 'country': country.trim(),
        },
      );

      if (kDebugMode) {
        debugPrint('🎯 [MetaEvent] User City tracked: $cleanCity');
      }
    } catch (e) {
      debugPrint('❌ [MetaEvent Error] trackUserCity: $e');
    }
  }

  /// 3. Membership Purchase Event
  /// Logs standard Meta 'Purchase' event and custom 'membership_purchase' event for Ads Manager optimization.
  static Future<void> trackMembershipPurchase({
    required double amount,
    required String planId,
    required String planName,
    String currency = 'INR',
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      final params = <String, dynamic>{
        'content_type': 'membership',
        'content_id': planId,
        'content_name': planName,
        'currency': currency,
        ...?additionalParams,
      };

      // Standard Purchase event (Required for Meta Ad ROAS & conversion campaigns)
      await _fb.logPurchase(
        amount: amount,
        currency: currency,
        parameters: params,
      );

      // Custom event for granular reporting in Events Manager
      await _fb.logEvent(
        name: 'membership_purchase',
        valueToSum: amount,
        parameters: params,
      );

      if (kDebugMode) {
        debugPrint('🎯 [MetaEvent] Membership Purchase tracked: $planName (₹$amount)');
      }
    } catch (e) {
      debugPrint('❌ [MetaEvent Error] trackMembershipPurchase: $e');
    }
  }

  /// 4. Coin Purchase Event
  /// Logs standard Meta 'Purchase' event and custom 'coin_purchase' event for Ads Manager optimization.
  static Future<void> trackCoinPurchase({
    required double amount,
    required int coins,
    required String planId,
    String currency = 'INR',
    Map<String, dynamic>? additionalParams,
  }) async {
    try {
      final params = <String, dynamic>{
        'content_type': 'coin_pack',
        'content_id': planId,
        'coins_amount': coins,
        'currency': currency,
        ...?additionalParams,
      };

      // Standard Purchase event (Required for Meta Ad ROAS & conversion campaigns)
      await _fb.logPurchase(
        amount: amount,
        currency: currency,
        parameters: params,
      );

      // Custom event for granular reporting in Events Manager
      await _fb.logEvent(
        name: 'coin_purchase',
        valueToSum: amount,
        parameters: params,
      );

      if (kDebugMode) {
        debugPrint('🎯 [MetaEvent] Coin Purchase tracked: $coins coins (₹$amount)');
      }
    } catch (e) {
      debugPrint('❌ [MetaEvent Error] trackCoinPurchase: $e');
    }
  }
}
