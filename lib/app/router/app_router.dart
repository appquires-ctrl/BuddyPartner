import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/features/splash/presentation/pages/splash_page.dart';
import 'package:dating_app/features/auth/presentation/pages/login_page.dart';
import 'package:dating_app/features/auth/presentation/pages/signup_page.dart';
import 'package:dating_app/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:dating_app/features/home/presentation/pages/home_page.dart';
import 'package:dating_app/features/home/presentation/pages/host_details_page.dart';
import 'package:dating_app/features/home/presentation/pages/favorites_page.dart';
import 'package:dating_app/features/call/presentation/pages/calling_page.dart';
import 'package:dating_app/features/call/presentation/pages/active_call_page.dart';
import 'package:dating_app/features/call/presentation/pages/call_summary_page.dart';
import 'package:dating_app/features/chat/presentation/pages/chat_page.dart';
import 'package:dating_app/features/history/presentation/pages/call_history_page.dart';
import 'package:dating_app/features/recharge/presentation/pages/recharge_page.dart';
import 'package:dating_app/features/profile/presentation/pages/profile_page.dart';
import 'package:dating_app/features/profile/presentation/pages/account_page.dart';
import 'package:dating_app/features/profile/presentation/pages/help_page.dart';
import 'package:dating_app/core/widgets/layout/app_bottom_nav.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final bool _isTest = Platform.environment.containsKey('FLUTTER_TEST');

/// ChangeNotifier that forwards Riverpod authState changes to GoRouter's refresh listener
class RouterTransitionNotifier extends ChangeNotifier {
  RouterTransitionNotifier(Ref ref) {
    ref.listen(authStateProvider, (previous, next) {
      notifyListeners();
    });
  }
}

final routerTransitionProvider = Provider((ref) => RouterTransitionNotifier(ref));

/// routerProvider exposes standard GoRouter bindings configured with Riverpod auth listeners
final routerProvider = Provider<GoRouter>((ref) {
  final refreshListenable = ref.watch(routerTransitionProvider);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: RouteNames.splash,
    refreshListenable: _isTest ? null : refreshListenable,
    redirect: (context, state) {
      if (_isTest) return null;

      final currentUser = ref.read(authStateProvider).value;
      final isLoggedIn = currentUser != null;
      final isProfileComplete = currentUser?.isProfileComplete ?? false;

      final isAuthRoute = state.matchedLocation == RouteNames.login ||
          state.matchedLocation == RouteNames.signup ||
          state.matchedLocation == RouteNames.forgotPassword ||
          state.matchedLocation == RouteNames.splash;

      if (!isLoggedIn) {
        // Unauthenticated: only allow splash, login, signup, forgot-password
        if (!isAuthRoute) {
          return RouteNames.login;
        }
      } else {
        // Authenticated but profile is not complete: force onboarding (except splash)
        if (!isProfileComplete) {
          if (state.matchedLocation != RouteNames.signup && state.matchedLocation != RouteNames.splash) {
            return RouteNames.signup;
          }
        } else {
          // Authenticated and profile complete: if on auth pages, go to home
          if (isAuthRoute) {
            return RouteNames.home;
          }
        }
      }
      return null;
    },
    routes: [
      // Onboarding stacked pages
      GoRoute(
        path: RouteNames.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: RouteNames.login,
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: RouteNames.signup,
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: RouteNames.forgotPassword,
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      
      // Calling screens flow
      GoRoute(
        path: RouteNames.calling,
        builder: (context, state) => const CallingPage(),
      ),
      GoRoute(
        path: RouteNames.activeCall,
        builder: (context, state) => const ActiveCallPage(),
      ),
      GoRoute(
        path: RouteNames.callSummary,
        builder: (context, state) => const CallSummaryPage(),
      ),
      GoRoute(
        path: RouteNames.chat,
        builder: (context, state) => const ChatPage(),
      ),
      GoRoute(
        path: '${RouteNames.hostDetails}/:id',
        builder: (context, state) {
          final hostId = state.pathParameters['id'] ?? 'host_1';
          return HostDetailsPage(hostId: hostId);
        },
      ),
      GoRoute(
        path: RouteNames.history,
        builder: (context, state) => const CallHistoryPage(),
      ),
      GoRoute(
        path: RouteNames.account,
        builder: (context, state) => const AccountPage(),
      ),
      GoRoute(
        path: RouteNames.help,
        builder: (context, state) => const HelpPage(),
      ),

      // Stateful Nested Shell for Main Dashboard
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return Scaffold(
            body: navigationShell,
            bottomNavigationBar: AppBottomNav(
              currentIndex: navigationShell.currentIndex,
              onTap: (index) {
                navigationShell.goBranch(
                  index,
                  initialLocation: index == navigationShell.currentIndex,
                );
              },
            ),
          );
        },
        branches: [
          // Tab 1: Discover Home list
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.home,
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),
          
          // Tab 2: Favorites
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.favorites,
                builder: (context, state) => const FavoritesPage(),
              ),
            ],
          ),
          
          // Tab 3: Store Wallet Recharge
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.recharge,
                builder: (context, state) => const RechargePage(),
              ),
            ],
          ),
          
          // Tab 4: User Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.settings,
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
