import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/admin_theme.dart';
import 'router/admin_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: LoopCallAdminApp(),
    ),
  );
}

class LoopCallAdminApp extends ConsumerWidget {
  const LoopCallAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'LoopCall Control Room',
      debugShowCheckedModeBanner: false,
      theme: AdminTheme.lightTheme,
      routerConfig: router,
    );
  }
}
