import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../widgets/admin_shell.dart';
import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/users/user_management_screen.dart';
import '../features/reports/reports_queue_screen.dart';
import '../features/withdrawals/withdrawals_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: _ListenableFromNotifier(ref.watch(authProvider.notifier)),
    redirect: (BuildContext context, GoRouterState state) {
      final isLoggingIn = state.matchedLocation == '/login';
      final isAuthenticated = authState.isAuthenticated;

      if (!isAuthenticated && !isLoggingIn) {
        return '/login';
      }

      if (isAuthenticated && isLoggingIn) {
        return '/';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: LoginScreen(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return AdminShell(
            currentPath: state.matchedLocation,
            child: child,
          );
        },
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),
          GoRoute(
            path: '/users',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: UserManagementScreen(),
            ),
          ),
          GoRoute(
            path: '/reports',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReportsQueueScreen(),
            ),
          ),
          GoRoute(
            path: '/withdrawals',
            pageBuilder: (context, state) => const NoTransitionPage(
              child: WithdrawalsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
});

class _ListenableFromNotifier extends ChangeNotifier {
  _ListenableFromNotifier(StateNotifier notifier) {
    notifier.addListener((_) {
      notifyListeners();
    });
  }
}
