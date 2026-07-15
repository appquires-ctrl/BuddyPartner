import 'package:flutter/material.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// LoopCallApp is the root widget of the application, configuring
/// standard theme modes, Router navigation configurations, and Responsive Breakpoints.
class LoopCallApp extends StatelessWidget {
  const LoopCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'LoopCall',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      builder: (context, child) => ResponsiveBreakpoints.builder(
        child: child!,
        breakpoints: [
          const Breakpoint(start: 0, end: 450, name: MOBILE),
          const Breakpoint(start: 451, end: 800, name: TABLET),
          const Breakpoint(start: 801, end: 1920, name: DESKTOP),
        ],
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
