import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
// ignore_for_file: unused_import
import 'core/services/screen_protection_service.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Temporarily commented out screen protection so clients/testers can take screenshots of bugs
  // await ScreenProtectionService.enableGlobalProtection();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase initialization failed (using placeholder configs): $e");
  }

  runApp(const ProviderScope(child: BuddyPartnerApp()));
}
