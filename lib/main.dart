import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:buddypartner/core/services/notification_service.dart';
import 'package:buddypartner/core/utils/app_logger.dart';
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

  // Attach global error handlers to route unhandled errors into AppLogger
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.error('Flutter Framework Error', details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Unhandled Platform Error', error, stack);
    return true;
  };

  runApp(const ProviderScope(child: BuddyPartnerApp()));
}
