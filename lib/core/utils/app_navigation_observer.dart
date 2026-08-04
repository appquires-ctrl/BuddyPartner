import 'package:flutter/material.dart';
import 'package:dating_app/core/utils/app_logger.dart';

/// AppNavigationObserver tracks GoRouter navigation transitions and emits
/// chronological [NAVIGATION] and [SCREEN] timeline logs to the terminal.
class AppNavigationObserver extends NavigatorObserver {
  String _getRouteName(Route<dynamic>? route) {
    if (route == null) return 'UnknownScreen';
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      return _cleanScreenName(name);
    }
    // Fallback to route representation if settings.name is null
    final str = route.toString();
    return _cleanScreenName(str);
  }

  String _cleanScreenName(String raw) {
    String clean = raw;
    if (clean.startsWith('/')) {
      clean = clean.replaceFirst('/', '');
    }
    if (clean.isEmpty) {
      clean = 'HomeScreen';
    }
    // Capitalize first letter if lowercase
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

    if (previousRoute != null) {
      AppLogger.navigation(from, to, arguments: route.settings.arguments);
    }
    AppLogger.screenLoaded(to);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    final from = _getRouteName(route);
    final to = _getRouteName(previousRoute);

    AppLogger.navigation(from, to);
    AppLogger.screenLoaded(to);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    final from = _getRouteName(oldRoute);
    final to = _getRouteName(newRoute);

    AppLogger.navigation(from, to, arguments: newRoute?.settings.arguments);
    AppLogger.screenLoaded(to);
  }
}
