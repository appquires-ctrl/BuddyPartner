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
import 'package:dating_app/features/call/presentation/pages/incoming_call_page.dart';
import 'package:dating_app/features/call/presentation/pages/call_summary_page.dart';
import 'package:dating_app/features/chat/presentation/pages/conversations_list_page.dart';
import 'package:dating_app/features/chat/presentation/pages/chat_page.dart';
import 'package:dating_app/features/history/presentation/pages/call_history_page.dart';
import 'package:dating_app/features/profile/presentation/pages/profile_page.dart';
import 'package:dating_app/features/profile/presentation/pages/account_page.dart';
import 'package:dating_app/features/profile/presentation/pages/help_page.dart';
import 'package:dating_app/features/subscription/presentation/pages/subscribe_page.dart';
import 'package:dating_app/features/subscription/presentation/pages/dev_subscription_page.dart';
import 'package:dating_app/features/subscription/domain/subscription_plan.dart';
import 'package:dating_app/features/legal/presentation/pages/legal_document_page.dart';
import 'package:dating_app/features/legal/data/legal_document_content.dart';
import 'package:dating_app/features/wallet/presentation/pages/transaction_history_page.dart';
import 'package:dating_app/features/auth/presentation/pages/banned_screen.dart';
import 'package:dating_app/core/widgets/layout/app_bottom_nav.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'package:dating_app/core/utils/app_navigation_observer.dart';

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
    observers: [AppNavigationObserver()],
    refreshListenable: _isTest ? null : refreshListenable,
    redirect: (context, state) {
      if (_isTest) return null;

      final currentUser = ref.read(authStateProvider).value;
      final isLoggedIn = currentUser != null;
      final isProfileComplete = currentUser?.isProfileComplete ?? false;

      final isLegalRoute = state.matchedLocation.startsWith('/legal');
      final isBannedRoute = state.matchedLocation == RouteNames.banned ||
          state.matchedLocation == RouteNames.suspended;
      final isAuthRoute = state.matchedLocation == RouteNames.login ||
          state.matchedLocation == RouteNames.signup ||
          state.matchedLocation == RouteNames.forgotPassword ||
          state.matchedLocation == RouteNames.splash;

      if (isLegalRoute || isBannedRoute) {
        // Legal pages and Banned/Suspended screens can be viewed anytime!
        return null;
      }

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
        name: 'SplashPage',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: RouteNames.login,
        name: 'LoginPage',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: RouteNames.signup,
        name: 'SignUpPage',
        builder: (context, state) => const SignupPage(),
      ),
      GoRoute(
        path: RouteNames.forgotPassword,
        name: 'ForgotPasswordPage',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      
      // Legal document screens
      GoRoute(
        path: RouteNames.termsOfService,
        name: 'TermsOfService',
        builder: (context, state) => LegalDocumentPage(document: LegalDocumentContent.termsOfService),
      ),
      GoRoute(
        path: RouteNames.privacyPolicy,
        name: 'PrivacyPolicy',
        builder: (context, state) => LegalDocumentPage(document: LegalDocumentContent.privacyPolicy),
      ),
      GoRoute(
        path: RouteNames.communityGuidelines,
        name: 'CommunityGuidelines',
        builder: (context, state) => LegalDocumentPage(document: LegalDocumentContent.communityGuidelines),
      ),
      GoRoute(
        path: RouteNames.refundPolicy,
        name: 'RefundPolicy',
        builder: (context, state) => LegalDocumentPage(document: LegalDocumentContent.refundPolicy),
      ),
      GoRoute(
        path: RouteNames.withdrawalTerms,
        name: 'WithdrawalTerms',
        builder: (context, state) => LegalDocumentPage(document: LegalDocumentContent.withdrawalTerms),
      ),

      
      // Calling screens flow
      GoRoute(
        path: RouteNames.calling,
        name: 'CallingPage',
        builder: (context, state) => const CallingPage(),
      ),
      GoRoute(
        path: RouteNames.activeCall,
        name: 'ActiveCallPage',
        builder: (context, state) => const ActiveCallPage(),
      ),
      GoRoute(
        path: RouteNames.incomingCall,
        name: 'IncomingCallPage',
        builder: (context, state) => const IncomingCallPage(),
      ),
      GoRoute(
        path: RouteNames.callSummary,
        name: 'CallSummaryPage',
        builder: (context, state) => const CallSummaryPage(),
      ),
      GoRoute(
        path: RouteNames.chat,
        name: 'ChatPage',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final conversationId = extra['conversationId'] as String? ?? '';
          final userId = extra['userId'] as String? ?? 'priya_1';
          final userName = extra['userName'] as String? ?? 'Priya';
          final userAvatar = extra['userAvatar'] as String?;
          final avatarSeed = extra['avatarSeed'] as String?;
          final avatarStyle = extra['avatarStyle'] as String?;
          return ChatPage(
            conversationId: conversationId,
            userId: userId,
            userName: userName,
            userAvatar: userAvatar,
            avatarSeed: avatarSeed,
            avatarStyle: avatarStyle,
          );
        },
      ),
      GoRoute(
        path: '${RouteNames.hostDetails}/:id',
        name: 'HostDetailsPage',
        builder: (context, state) {
          final hostId = state.pathParameters['id'] ?? 'host_1';
          return HostDetailsPage(hostId: hostId);
        },
      ),
      GoRoute(
        path: RouteNames.history,
        name: 'CallHistoryPage',
        builder: (context, state) => const CallHistoryPage(),
      ),
      GoRoute(
        path: RouteNames.account,
        name: 'AccountPage',
        builder: (context, state) => const AccountPage(),
      ),
      GoRoute(
        path: RouteNames.help,
        name: 'HelpPage',
        builder: (context, state) => const HelpPage(),
      ),
      GoRoute(
        path: RouteNames.transactionHistory,
        name: 'TransactionHistoryPage',
        builder: (context, state) => const TransactionHistoryPage(),
      ),
      GoRoute(
        path: RouteNames.suspended,
        name: 'BannedScreen',
        builder: (context, state) => const BannedScreen(),
      ),
      GoRoute(
        path: RouteNames.banned,
        name: 'BannedScreen',
        builder: (context, state) => const BannedScreen(),
      ),
      GoRoute(
        path: RouteNames.subscribe,
        name: 'SubscribePage',
        builder: (context, state) => const SubscribePage(),
      ),
      GoRoute(
        path: RouteNames.devSubscription,
        name: 'DevSubscriptionPage',
        builder: (context, state) {
          final plan = state.extra as SubscriptionPlan? ?? SubscriptionPlan.defaultPlans.first;
          return DevSubscriptionPage(plan: plan);
        },
      ),

      // Stateful Nested Shell for Main Dashboard (4 core tabs)
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
                name: 'HomePage',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),

          // Tab 2: Chat/Messages
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.conversations,
                name: 'ConversationsListPage',
                builder: (context, state) => const ConversationsListPage(),
              ),
            ],
          ),

          // Tab 3: Favorites
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.favorites,
                name: 'FavoritesPage',
                builder: (context, state) => const FavoritesPage(),
              ),
            ],
          ),

          // Tab 4: User Profile Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.settings,
                name: 'ProfilePage',
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
