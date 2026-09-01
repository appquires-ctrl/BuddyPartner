import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/core/services/notification_service.dart';
import 'package:buddypartner/core/services/app_lifecycle_service.dart';
import 'package:buddypartner/core/widgets/feedback/in_app_notification_banner.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/call/presentation/widgets/incoming_paid_call_dialog.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/features/call/presentation/widgets/floating_minimized_call_overlay.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// BuddyPartnerApp is the root widget of the application, configuring
/// standard theme modes, Router navigation configurations, and Responsive Breakpoints.
class BuddyPartnerApp extends ConsumerStatefulWidget {
  const BuddyPartnerApp({super.key});

  @override
  ConsumerState<BuddyPartnerApp> createState() => _BuddyPartnerAppState();
}

class _BuddyPartnerAppState extends ConsumerState<BuddyPartnerApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final notifService = NotificationService.instance;
      notifService.initialize(ref);
      notifService.onOpenChat = ({
        required String conversationId,
        required String userId,
        required String userName,
        String? userAvatar,
        String? avatarSeed,
        String? avatarStyle,
        String? gender,
      }) {
        final navContext = rootNavigatorKey.currentContext;
        if (navContext != null && navContext.mounted) {
          navContext.push(
            RouteNames.chat,
            extra: {
              'conversationId': conversationId,
              'userId': userId,
              'userName': userName,
              'userAvatar': userAvatar,
              'avatarSeed': avatarSeed,
              'avatarStyle': avatarStyle,
              'gender': gender,
            },
          );
        }
      };

      notifService.onInstantCallNotification = ({
        required String sessionId,
        required int bidAmount,
      }) {
        final mmInCall = ref.read(matchmakingControllerProvider).phase == MatchmakingPhase.inCall;
        final instantInCall = ref.read(instantConnectControllerProvider).phase == InstantPhase.inCall;
        if (mmInCall || instantInCall) {
          debugPrint('🔔 [FCM Click] User is currently in active call. Ignoring instant call notification.');
          return;
        }
        ref.read(instantConnectControllerProvider.notifier).handleNotificationLaunch(
          sessionId: sessionId,
          bidAmount: bidAmount,
        );
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    // Keep global app lifecycle presence service alive
    ref.watch(appLifecycleServiceProvider);

    // Listen to Auth State to keep FCM Token registered upon login
    ref.listen<AsyncValue<CustomUser?>>(authStateProvider, (prev, next) {
      if (next.value != null && next.value?.id.isNotEmpty == true) {
        NotificationService.instance.syncTokenWithBackend(ref);
      }
    });

    // Globally listen to normal call state changes
    ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;

      final wasInCall = prev?.phase == MatchmakingPhase.inCall || prev?.phase == MatchmakingPhase.matched;
      final isNowInCall = next.phase == MatchmakingPhase.inCall || next.phase == MatchmakingPhase.matched;

      if (isNowInCall && !wasInCall) {
        Navigator.of(navContext, rootNavigator: true).popUntil((route) => route is! PopupRoute);
        navContext.go(RouteNames.activeCall);
      } else if (next.phase == MatchmakingPhase.incomingRequest && prev?.phase != MatchmakingPhase.incomingRequest) {
        Navigator.of(navContext, rootNavigator: true).popUntil((route) => route is! PopupRoute);
        navContext.go(RouteNames.incomingCall);
      } else if (next.phase == MatchmakingPhase.outgoingRequest && prev?.phase != MatchmakingPhase.outgoingRequest) {
        Navigator.of(navContext, rootNavigator: true).popUntil((route) => route is! PopupRoute);
        navContext.go(RouteNames.calling);
      } else if (wasInCall &&
          (next.phase == MatchmakingPhase.idle || next.phase == MatchmakingPhase.ended)) {
        if (next.isCallMinimized) {
          ref.read(matchmakingControllerProvider.notifier).restoreCall();
        }
        Navigator.of(navContext, rootNavigator: true).popUntil((route) => route is! PopupRoute);
        navContext.go(RouteNames.home);
      }

      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        AppSnackBar.showError(navContext, next.errorMessage!);
      }
    });

    // Globally listen to VIP Instant Connect call state changes
    ref.listen<InstantConnectState>(instantConnectControllerProvider, (prev, next) {
      final navContext = rootNavigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;

      if (next.phase == InstantPhase.inCall && prev?.phase != InstantPhase.inCall) {
        Navigator.of(navContext, rootNavigator: true).popUntil((route) => route is! PopupRoute);
        navContext.go(RouteNames.activeCall);
      } else if (next.phase == InstantPhase.incomingRequest && prev?.phase != InstantPhase.incomingRequest) {
        final mmPhase = ref.read(matchmakingControllerProvider).phase;
        if (mmPhase == MatchmakingPhase.idle) {
          showDialog(
            context: navContext,
            barrierDismissible: false,
            builder: (ctx) => const IncomingPaidCallDialog(),
          );
        }
      } else if (prev?.phase == InstantPhase.inCall && (next.phase == InstantPhase.idle || next.phase == InstantPhase.ended)) {
        Navigator.of(navContext, rootNavigator: true).popUntil((route) => route is! PopupRoute);
        navContext.go(RouteNames.home);
      }

      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        AppSnackBar.showError(navContext, next.errorMessage!);
      }
    });

    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'BuddyPartner',
      theme: AppTheme.light,
      darkTheme: AppTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: router,
      builder: (context, child) {
        final mediaQueryData = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQueryData.copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: InAppNotificationOverlay(
            onNotificationTap: (notif) {
              final navContext = rootNavigatorKey.currentContext;
              if (navContext != null && navContext.mounted) {
                navContext.push(
                  RouteNames.chat,
                  extra: {
                    'conversationId': notif.conversationId,
                    'userId': notif.senderId,
                    'userName': notif.senderName,
                    'userAvatar': notif.senderAvatar,
                    'avatarSeed': notif.avatarSeed,
                    'avatarStyle': notif.avatarStyle,
                    'gender': notif.gender,
                  },
                );
              }
            },
            child: FloatingMinimizedCallOverlay(
              child: ResponsiveBreakpoints.builder(
                child: child!,
                breakpoints: [
                  const Breakpoint(start: 0, end: 450, name: MOBILE),
                  const Breakpoint(start: 451, end: 800, name: TABLET),
                  const Breakpoint(start: 801, end: 1920, name: DESKTOP),
                ],
              ),
            ),
          ),
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
