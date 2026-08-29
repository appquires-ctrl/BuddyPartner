import 'package:apptrove_sdk_flutter/apptroveconfig.dart';
import 'package:apptrove_sdk_flutter/apptroveevent.dart';
import 'package:apptrove_sdk_flutter/apptrovefluttersdk.dart';
import 'package:buddypartner/core/config/app_config.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:flutter/foundation.dart';

// Re-export common AppTrove classes for easy access across the app
export 'package:apptrove_sdk_flutter/apptroveconfig.dart';
export 'package:apptrove_sdk_flutter/apptroveevent.dart';
export 'package:apptrove_sdk_flutter/apptrovefluttersdk.dart';

/// Centralized service for Apptrove (formerly Trackier) MMP SDK.
/// Manages SDK initialization, user identification, and event tracking.
class AppTroveService {
  AppTroveService._();

  static bool _isInitialized = false;

  /// Whether the Apptrove SDK has been successfully initialized.
  static bool get isInitialized => _isInitialized;

  /// Initializes the Apptrove SDK.
  ///
  /// [sdkKey] can be passed directly or read from [AppConfig.apptroveSdkKey].
  /// [environment] defaults to 'production' in release mode and 'development' in debug mode.
  static Future<void> initialize({
    String? sdkKey,
    String? environment,
  }) async {
    final key = sdkKey ?? AppConfig.apptroveSdkKey;

    if (key.trim().isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[AppTrove] SDK Key is empty. Set APPTROVE_SDK_KEY via --dart-define or AppConfig. SDK initialization skipped.',
        );
      }
      return;
    }

    try {
      final env = environment ??
          (AppConfig.apptroveEnv.isNotEmpty
              ? AppConfig.apptroveEnv
              : (kReleaseMode ? 'production' : 'development'));

      final config = AppTroveSDKConfig(key, env);

      AppTroveFlutterSdk.initializeSDK(config);
      _isInitialized = true;

      if (kDebugMode) {
        debugPrint('[AppTrove] SDK initialized successfully in "$env" mode.');
      }
    } catch (e, stack) {
      AppLogger.error('Failed to initialize AppTrove SDK', e, stack);
    }
  }

  /// Associates user identity with Apptrove for user-level attribution.
  static void setUser({
    String? userId,
    String? userEmail,
    String? userName,
    String? userPhone,
    String? dob,
    String? gender,
    Map<dynamic, dynamic>? additionalDetails,
  }) {
    if (!_isInitialized) return;

    try {
      if (userId != null && userId.isNotEmpty) {
        AppTroveFlutterSdk.setUserId(userId);
      }
      if (userEmail != null && userEmail.isNotEmpty) {
        AppTroveFlutterSdk.setUserEmail(userEmail);
      }
      if (userName != null && userName.isNotEmpty) {
        AppTroveFlutterSdk.setUserName(userName);
      }
      if (userPhone != null && userPhone.isNotEmpty) {
        AppTroveFlutterSdk.setUserPhone(userPhone);
      }
      if (dob != null && dob.isNotEmpty) {
        AppTroveFlutterSdk.setDOB(dob);
      }
      if (gender != null && gender.isNotEmpty) {
        final g = gender.toLowerCase();
        if (g.contains('female')) {
          AppTroveFlutterSdk.setGender(Gender.Female);
        } else if (g.contains('male')) {
          AppTroveFlutterSdk.setGender(Gender.Male);
        } else {
          AppTroveFlutterSdk.setGender(Gender.Others);
        }
      }
      if (additionalDetails != null && additionalDetails.isNotEmpty) {
        AppTroveFlutterSdk.setUserAdditionalDetails(additionalDetails);
      }
    } catch (e, stack) {
      AppLogger.error('Failed to set AppTrove user details', e, stack);
    }
  }

  /// Sends FCM Device Token to Apptrove for uninstall and push tracking.
  static void sendFcmToken(String fcmToken) {
    if (!_isInitialized || fcmToken.isEmpty) return;

    try {
      AppTroveFlutterSdk.sendFcmToken(fcmToken);
      if (kDebugMode) {
        debugPrint('[AppTrove] FCM token registered successfully for uninstall tracking.');
      }
    } catch (e, stack) {
      AppLogger.error('Failed to send FCM token to AppTrove', e, stack);
    }
  }

  /// Tracks a built-in or custom Apptrove event.
  static void trackEvent(AppTroveEvent event) {
    if (!_isInitialized) {
      if (kDebugMode) {
        debugPrint(
          '[AppTrove] SDK not initialized. Event skipped: ${event.eventId}',
        );
      }
      return;
    }

    try {
      AppTroveFlutterSdk.trackEvent(event);
      if (kDebugMode) {
        debugPrint('[AppTrove] Event tracked successfully: ${event.eventId}');
      }
    } catch (e, stack) {
      AppLogger.error(
        'Failed to track AppTrove event: ${event.eventId}',
        e,
        stack,
      );
    }
  }

  /// Tracks a user Sign-Up / Profile Completion event in Apptrove.
  static void trackSignUp({
    String? userId,
    String? phoneNumber,
    required String gender,
    required String language,
    String? fullName,
    DateTime? dob,
    int? age,
  }) {
    final event = AppTroveEvent(AppTroveEvent.COMPLETE_REGISTRATION)
      ..param1 = phoneNumber ?? ''
      ..param2 = gender
      ..param3 = language
      ..param4 = fullName ?? ''
      ..param5 = userId ?? '';

    if (age != null) {
      event.param6 = '$age';
      event.setEventValue('age', age);
    }

    if (dob != null) {
      final dobStr =
          '${dob.year}-${dob.month.toString().padLeft(2, '0')}-${dob.day.toString().padLeft(2, '0')}';
      event.setEventValue('dob', dobStr);
      try {
        AppTroveFlutterSdk.setDOB(dobStr);
      } catch (_) {}
    }

    if (gender.isNotEmpty) {
      try {
        final g = gender.toLowerCase();
        if (g.contains('female')) {
          AppTroveFlutterSdk.setGender(Gender.Female);
        } else if (g.contains('male')) {
          AppTroveFlutterSdk.setGender(Gender.Male);
        } else {
          AppTroveFlutterSdk.setGender(Gender.Others);
        }
      } catch (_) {}
    }

    trackEvent(event);

    // Also dispatch dashboard Signup event (8ASKXJ1vWO) for full reporting coverage
    final signupEvent = AppTroveEvent('8ASKXJ1vWO')
      ..param1 = phoneNumber ?? ''
      ..param2 = gender
      ..param3 = language
      ..param4 = fullName ?? ''
      ..param5 = userId ?? '';
    if (age != null) signupEvent.setEventValue('age', age);
    trackEvent(signupEvent);
  }

  /// Tracks a user Login event in Apptrove.
  static void trackLogin({
    String? phoneNumber,
    String? userId,
  }) {
    final event = AppTroveEvent(AppTroveEvent.LOGIN)
      ..param1 = phoneNumber ?? ''
      ..param2 = userId ?? '';

    trackEvent(event);
  }

  /// Tracks a Subscription / In-App Purchase event in Apptrove.
  static void trackSubscriptionPurchase({
    required String planId,
    required String planTitle,
    required double priceRupees,
    required int durationDays,
    String? orderId,
  }) {
    // 1. Track PURCHASE event (with revenue & monetization metrics)
    final purchaseEvent = AppTroveEvent(AppTroveEvent.PURCHASE)
      ..productId = planId
      ..revenue = priceRupees
      ..currency = 'INR'
      ..orderId = orderId ?? 'SUB_${DateTime.now().millisecondsSinceEpoch}'
      ..param1 = planTitle
      ..param2 = '$durationDays days';

    purchaseEvent.setEventValue('planDurationDays', durationDays);
    purchaseEvent.setEventValue('priceRupees', priceRupees);
    trackEvent(purchaseEvent);

    // 2. Track SUBSCRIBE event
    final subscribeEvent = AppTroveEvent(AppTroveEvent.SUBSCRIBE)
      ..productId = planId
      ..revenue = priceRupees
      ..currency = 'INR'
      ..param1 = planTitle;

    trackEvent(subscribeEvent);
  }
}
