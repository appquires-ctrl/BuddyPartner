import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dating_app/app/router/app_router.dart';
import 'package:dating_app/features/auth/presentation/widgets/reset_password_dialog.dart';
import 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: const String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'https://rafjaybshixumviaatqn.supabase.co',
    ),
    anonKey: const String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJhZmpheWJzaGl4dW12aWFhdHFuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQwNDgyMzcsImV4cCI6MjA5OTYyNDIzN30.C0BV7qJT6Rl5DnnLbX9YlhCTd61L6hiny-U9LztdYCs',
    ),
  );

  // Set up a global listener for password recovery deep links
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.passwordRecovery) {
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        ResetPasswordDialog.show(context);
      }
    }
  });

  runApp(const ProviderScope(child: LoopCallApp()));
}
