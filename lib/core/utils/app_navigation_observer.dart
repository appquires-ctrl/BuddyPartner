import 'package:flutter/material.dart';
import 'package:buddypartner/core/utils/app_logger.dart';

/// AppNavigationObserver tracks GoRouter navigation transitions and emits
/// chronological [NAVIGATION] and [SCREEN] timeline logs to the terminal.
class AppNavigationObserver extends NavigatorObserver {
  String _getRouteName(Route<dynamic>? route) {
    if (route == null) return 'UnknownScreen';
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      return _cleanScreenName(name);
    }
    if (route is PopupRoute) {
      return 'ModalDialog';
    }
    // Fallback to route representation if settings.name is null
    final str = route.toString();
    return _cleanScreenName(str);
  }

  String _cleanScreenName(String raw) {
    if (raw.startsWith('_PageBasedMaterialPageRoute') ||
        raw.startsWith('MaterialPage') ||
        raw.startsWith('MaterialPageRoute')) {
      return AppLogger.currentScreen;
    }

    String clean = raw;
    if (clean.contains('(')) {
      clean = clean.split('(').first;
    }
    if (clean.startsWith('/')) {
      clean = clean.replaceFirst('/', '');
    }
    if (clean.isEmpty) {
      clean = 'HomeScreen';
    }

    // Map route paths to clean readable Screen names
    switch (clean) {
      case 'login':
        return 'LoginScreen';
      case 'signup':
        return 'SignUpPage';
      case 'home':
        return 'HomeScreen';
      case 'profile':
      case 'settings':
        return 'ProfilePage';
      case 'account':
        return 'AccountPage';
      case 'help':
        return 'HelpPage';
      case 'chat':
        return 'ChatPage';
      case 'conversations':
        return 'ConversationsListPage';
      case 'favorites':
      case 'discover':
        return 'DiscoverPage';
      case 'call-history':
      case 'history':
        return 'CallHistoryPage';
      case 'subscribe':
        return 'SubscribePage';
      case 'dev-subscription':
        return 'DevSubscriptionPage';
      case 'dev-recharge':
        return 'DevRechargePage';
      case 'recharge':
        return 'RechargePage';
      case 'withdraw':
        return 'WithdrawPage';
      case 'calling':
        return 'CallingPage';
      case 'active-call':
        return 'ActiveCallPage';
      case 'incoming-call':
        return 'IncomingCallPage';
      case 'call-summary':
        return 'CallSummaryPage';
      case 'banned':
      case 'suspended':
        return 'BannedScreen';
      case 'transaction-history':
        return 'TransactionHistoryPage';
      case 'wallet-history':
        return 'WalletHistoryPage';
    }

    if (clean.isNotEmpty) {
      clean = clean[0].toUpperCase() + clean.substring(1);
    }
    return clean;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    final from = _getRouteName(previousRoute);
    final to = _getRouteName(route);

    if (previousRoute != null && from != to && to != 'ModalDialog') {
      AppLogger.navigation(from, to, arguments: route.settings.arguments);
    }
    if (to != 'UnknownScreen' && to != from && to != 'ModalDialog') {
      AppLogger.screenLoaded(to);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final from = _getRouteName(route);
    final to = _getRouteName(previousRoute);

    if (from != to && to != 'UnknownScreen' && from != 'ModalDialog') {
      AppLogger.navigation(from, to);
      AppLogger.screenLoaded(to);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final from = _getRouteName(oldRoute);
    final to = _getRouteName(newRoute);

    if (from != to && to != 'ModalDialog') {
      AppLogger.navigation(from, to, arguments: newRoute?.settings.arguments);
    }
    if (to != 'UnknownScreen' && to != from && to != 'ModalDialog') {
      AppLogger.screenLoaded(to);
    }
  }
}
