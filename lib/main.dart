import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:dating_app/core/utils/app_logger.dart';
// ignore_for_file: unused_import
import 'core/services/screen_protection_service.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Attach global error handlers to route unhandled errors into AppLogger
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.error('Flutter Framework Error', details.exception, details.stack);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.error('Unhandled Platform Error', error, stack);
    return true;
  };

  // Temporarily commented out screen protection so clients/testers can take screenshots of bugs
  // await ScreenProtectionService.enableGlobalProtection();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    AppLogger.error('Firebase Initialization', e);
  }

  runApp(const ProviderScope(child: BuddyPartnerApp()));
}
