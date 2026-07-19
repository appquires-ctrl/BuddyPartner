import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// LoopCallApp is the root widget of the application, configuring
/// standard theme modes, Router navigation configurations, and Responsive Breakpoints.
class LoopCallApp extends ConsumerWidget {
  const LoopCallApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Globally listen to call state changes
    ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      if (next.phase == MatchmakingPhase.inCall && prev?.phase != MatchmakingPhase.inCall) {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          context.go(RouteNames.activeCall);
        }
      }

      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        final context = rootNavigatorKey.currentContext;
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.errorMessage!),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    });

    return MaterialApp.router(
      title: 'LoopCall',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      builder: (context, child) {
        final mediaQueryData = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQueryData.copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: ResponsiveBreakpoints.builder(
            child: child!,
            breakpoints: [
              const Breakpoint(start: 0, end: 450, name: MOBILE),
              const Breakpoint(start: 451, end: 800, name: TABLET),
              const Breakpoint(start: 801, end: 1920, name: DESKTOP),
            ],
          ),
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
