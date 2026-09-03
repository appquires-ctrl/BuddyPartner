import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:buddypartner/core/services/apptrove_service.dart';
import 'package:buddypartner/core/services/notification_service.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/core/services/screen_protection_service.dart';
import 'app/app.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase and background messaging handler
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('Firebase initialization warning in main: $e');
    }
  }

  // Initialize Apptrove MMP SDK
  await AppTroveService.initialize();

  // Attach global error handlers to route unhandled errors into AppLogger
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.error('Flutter Framework Error', details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Unhandled Platform Error', error, stack);
    return true;
  };

  // Custom Error Widget for Release and Debug mode:
  // Instead of a silent blank grey box in release builds, show a clean error screen with full diagnostic details.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF1E1B38),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 48),
              const SizedBox(height: 12),
              const Text(
                'Something went wrong',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'A UI component failed to render:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      '${details.exception}\n\n${details.stack}',
                      style: const TextStyle(
                        color: Color(0xFFFFB4AB),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: () {
                  final navContext = rootNavigatorKey.currentContext;
                  if (navContext != null && navContext.mounted) {
                    Navigator.of(navContext, rootNavigator: true).popUntil((r) => r is! PopupRoute);
                    navContext.go(RouteNames.home);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C6AEF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: const Icon(Icons.home_rounded),
                label: const Text('Return to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Enable global anti-screenshot and screen recording protection
  await ScreenProtectionService.enableGlobalProtection();

  runApp(const ProviderScope(child: BuddyPartnerApp()));
}
