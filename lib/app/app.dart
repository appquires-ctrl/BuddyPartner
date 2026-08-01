import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// BuddyPartnerApp is the root widget of the application, configuring
/// standard theme modes, Router navigation configurations, and Responsive Breakpoints.
class BuddyPartnerApp extends ConsumerWidget {
  const BuddyPartnerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Globally listen to call state changes
    ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;

      if (next.phase == MatchmakingPhase.inCall && prev?.phase != MatchmakingPhase.inCall) {
        navContext.go(RouteNames.activeCall);
      } else if (next.phase == MatchmakingPhase.incomingRequest && prev?.phase != MatchmakingPhase.incomingRequest) {
        navContext.go(RouteNames.incomingCall);
      } else if (next.phase == MatchmakingPhase.outgoingRequest && prev?.phase != MatchmakingPhase.outgoingRequest) {
        navContext.go(RouteNames.calling);
      }

      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(navContext).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'BuddyPartner',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
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
