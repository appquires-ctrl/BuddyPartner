import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/features/splash/presentation/pages/splash_page.dart';
import 'package:buddypartner/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:buddypartner/features/auth/presentation/pages/login_page.dart';
import 'package:buddypartner/features/auth/presentation/pages/signup_page.dart';
import 'package:buddypartner/features/auth/presentation/pages/forgot_password_page.dart';
import 'package:buddypartner/features/home/presentation/pages/home_page.dart';
import 'package:buddypartner/features/home/presentation/pages/host_details_page.dart';
import 'package:buddypartner/features/home/presentation/pages/favorites_page.dart';
import 'package:buddypartner/features/call/presentation/pages/calling_page.dart';
import 'package:buddypartner/features/call/presentation/pages/active_call_page.dart';
import 'package:buddypartner/features/call/presentation/pages/incoming_call_page.dart';
import 'package:buddypartner/features/call/presentation/pages/call_summary_page.dart';
import 'package:buddypartner/features/chat/presentation/pages/conversations_list_page.dart';
import 'package:buddypartner/features/chat/presentation/pages/chat_page.dart';
import 'package:buddypartner/features/history/presentation/pages/call_history_page.dart';
import 'package:buddypartner/features/profile/presentation/pages/profile_page.dart';
import 'package:buddypartner/features/profile/presentation/pages/account_page.dart';
import 'package:buddypartner/features/profile/presentation/pages/help_page.dart';
import 'package:buddypartner/features/subscription/presentation/pages/subscribe_page.dart';
import 'package:buddypartner/features/subscription/presentation/pages/dev_subscription_page.dart';
import 'package:buddypartner/features/subscription/application/subscription_providers.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/subscription/domain/subscription_plan.dart';
import 'package:buddypartner/features/legal/presentation/pages/legal_document_page.dart';
import 'package:buddypartner/features/legal/data/legal_document_content.dart';
import 'package:buddypartner/features/wallet/presentation/pages/transaction_history_page.dart';
import 'package:buddypartner/features/wallet/presentation/pages/wallet_history_page.dart';
import 'package:buddypartner/features/recharge/presentation/pages/dev_recharge_page.dart';
import 'package:buddypartner/features/wallet/presentation/pages/wallet_hub_page.dart';
import 'package:buddypartner/features/auth/presentation/pages/banned_screen.dart';
import 'package:buddypartner/core/widgets/layout/app_bottom_nav.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/core/utils/app_navigation_observer.dart';

import 'package:buddypartner/features/version/application/version_check_provider.dart';
import 'package:buddypartner/features/version/presentation/pages/update_required_page.dart';
import 'package:buddypartner/features/buddy/presentation/pages/my_buddy_activity_page.dart';
import 'package:buddypartner/features/chat/application/conversations_provider.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final bool _isTest = Platform.environment.containsKey('FLUTTER_TEST');

/// ChangeNotifier that forwards Riverpod auth & version changes to GoRouter's refresh listener
class RouterTransitionNotifier extends ChangeNotifier {
  RouterTransitionNotifier(Ref ref) {
    ref.listen(authStateProvider, (previous, next) {
      notifyListeners();
    });
    ref.listen(versionCheckProvider, (previous, next) {
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

      final versionState = ref.read(versionCheckProvider);
      if (versionState.updateRequired) {
        if (state.matchedLocation != RouteNames.updateRequired) {
          return RouteNames.updateRequired;
        }
        return null;
      }

      final authAsync = ref.read(authStateProvider);
      final currentUser = authAsync.valueOrNull;
      final isAuthLoading = authAsync.isLoading;
      final isLoggedIn = currentUser != null;
      final isProfileComplete = currentUser?.isProfileComplete ?? false;

      final isLegalRoute = state.matchedLocation.startsWith('/legal');
      final isBannedRoute = state.matchedLocation == RouteNames.banned ||
          state.matchedLocation == RouteNames.suspended;
      final isSplashRoute = state.matchedLocation == RouteNames.splash;
      final isOnboardingRoute = state.matchedLocation == RouteNames.onboarding;
      final isUpdateRequiredRoute = state.matchedLocation == RouteNames.updateRequired;
      final isAuthRoute = state.matchedLocation == RouteNames.login ||
          state.matchedLocation == RouteNames.signup ||
          state.matchedLocation == RouteNames.forgotPassword;

      if (isLegalRoute || isBannedRoute || isSplashRoute || isUpdateRequiredRoute || isOnboardingRoute) {
        // Exempt routes can be viewed without auto-redirect
        return null;
      }

      if (isAuthLoading) {
        // While auth state is initializing asynchronously from disk/network, don't prematurely kick to login
        return null;
      }

      if (!isLoggedIn) {
        // Unauthenticated: only allow splash, login, signup, forgot-password
        if (!isAuthRoute) {
          return RouteNames.login;
        }
      } else {
        // Authenticated but profile is not complete: force onboarding
        if (!isProfileComplete) {
          if (state.matchedLocation != RouteNames.signup) {
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
      GoRoute(
        path: RouteNames.updateRequired,
        name: 'UpdateRequiredPage',
        builder: (context, state) => const UpdateRequiredPage(),
      ),
      // Onboarding stacked pages
      GoRoute(
        path: RouteNames.splash,
        name: 'SplashPage',
        builder: (context, state) => const AnimatedSplashScreen(),
      ),
      GoRoute(
        path: RouteNames.onboarding,
        name: 'OnboardingPage',
        builder: (context, state) => const OnboardingPage(),
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
        path: RouteNames.subscriptionTerms,
        name: 'SubscriptionTerms',
        builder: (context, state) => LegalDocumentPage(document: LegalDocumentContent.subscriptionTerms),
      ),
      GoRoute(
        path: RouteNames.safetyGuidelines,
        name: 'SafetyGuidelines',
        builder: (context, state) => LegalDocumentPage(document: LegalDocumentContent.safetyGuidelines),
      ),
      GoRoute(
        path: RouteNames.grievanceRedressal,
        name: 'GrievanceRedressal',
        builder: (context, state) => LegalDocumentPage(document: LegalDocumentContent.grievancePolicy),
      ),
      GoRoute(
        path: RouteNames.withdrawalTerms,
        name: 'WithdrawalTerms',
        builder: (context, state) => LegalDocumentPage(document: LegalDocumentContent.subscriptionTerms),
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
          final qParams = state.uri.queryParameters;
          final conversationId = (extra['conversationId'] ?? qParams['conversationId'] ?? '').toString();
          final userId = (extra['userId'] ?? qParams['userId'] ?? '').toString();
          final userName = (extra['userName'] ?? qParams['userName'] ?? '').toString();
          final userAvatar = extra['userAvatar'] as String? ?? qParams['userAvatar'];
          final avatarSeed = extra['avatarSeed'] as String? ?? qParams['avatarSeed'];
          final avatarStyle = extra['avatarStyle'] as String? ?? qParams['avatarStyle'];
          final gender = extra['gender'] as String? ?? qParams['gender'];
          return ChatPage(
            conversationId: conversationId,
            userId: userId,
            userName: userName,
            userAvatar: userAvatar,
            avatarSeed: avatarSeed,
            avatarStyle: avatarStyle,
            gender: gender,
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
        path: RouteNames.walletHistory,
        name: 'WalletHistoryPage',
        builder: (context, state) => const WalletHistoryPage(),
      ),
      GoRoute(
        path: RouteNames.subscriptionHistory,
        name: 'SubscriptionHistoryPage',
        builder: (context, state) => const TransactionHistoryPage(),
      ),
      GoRoute(
        path: RouteNames.suspended,
        name: 'SuspendedScreen',
        builder: (context, state) => const BannedScreen(),
      ),
      GoRoute(
        path: RouteNames.banned,
        name: 'BannedScreen',
        builder: (context, state) => const BannedScreen(),
      ),
      GoRoute(
        path: RouteNames.recharge,
        name: 'RechargePage',
        builder: (context, state) => const WalletHubPage(initialTab: WalletHubTab.recharge),
      ),
      GoRoute(
        path: RouteNames.withdraw,
        name: 'WithdrawPage',
        builder: (context, state) => const WalletHubPage(initialTab: WalletHubTab.withdraw),
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
      GoRoute(
        path: RouteNames.devRecharge,
        name: 'DevRechargePage',
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          final coins = args['coins'] as int? ?? 100;
          final price = args['price'] as int? ?? 100;
          return DevRechargePage(coins: coins, price: price);
        },
      ),
      GoRoute(
        path: RouteNames.buddyActivity,
        name: 'MyBuddyActivityPage',
        builder: (context, state) => const MyBuddyActivityPage(),
      ),
      // Stateful Nested Shell for Main Dashboard (4 core tabs)
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return Scaffold(
            extendBody: true,
            backgroundColor: Colors.transparent,
            body: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: const Color(0xFFFAF9FE)),
                Image.asset(
                  'assets/images/app_bg.jpg',
                  fit: BoxFit.cover,
                ),
                navigationShell,
              ],
            ),
            bottomNavigationBar: Consumer(
              builder: (context, ref, child) {
                final matchState = ref.watch(matchmakingControllerProvider);
                if (matchState.phase != MatchmakingPhase.idle && !matchState.isCallMinimized) {
                  return const SizedBox.shrink();
                }
                final isFemale = ref.watch(authStateProvider).value?.isFemale ?? false;
                final isSubscribed = ref.watch(subscriptionStatusProvider).value?.isSubscribed ?? false;
                final unreadChatCount = ref.watch(totalUnreadMessagesCountProvider);
                return AppBottomNav(
                  currentIndex: navigationShell.currentIndex,
                  isFemale: isFemale,
                  isSubscribed: isSubscribed,
                  unreadChatCount: unreadChatCount,
                  onTap: (index) {
                    navigationShell.goBranch(
                      index,
                      initialLocation: index == navigationShell.currentIndex,
                    );
                  },
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

          // Tab 3: Dynamic Subscription / Coins / Withdraw
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.plans,
                name: 'SubscriptionTab',
                builder: (context, state) => const DynamicPlansOrWalletTab(),
              ),
            ],
          ),

          // Tab 4: Favorites
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.favorites,
                name: 'FavoritesPage',
                builder: (context, state) => const FavoritesPage(),
              ),
            ],
          ),

          // Tab 5: User Profile Settings
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

/// Dynamic Tab 3 router widget:
/// Renders the Unified Wallet Hub (Buy Coins & Withdraw) for all users.
class DynamicPlansOrWalletTab extends StatelessWidget {
  const DynamicPlansOrWalletTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const WalletHubPage();
  }
}
