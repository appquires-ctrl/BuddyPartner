import 'package:flutter/foundation.dart';

/// AppLogger provides a centralized, human and AI-readable timeline debug logger.
/// Formats every user action, screen transition, API call, dialog, and error in
/// chronological order for debugging. Active strictly in kDebugMode.
class AppLogger {
  AppLogger._();

  /// Current active screen name tracked globally
  static String currentScreen = 'App';

  static String _timestamp() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    final ms = now.millisecond.toString().padLeft(3, '0');
    return '[$h:$m:$s.$ms]';
  }

  /// Log screen opened / loaded
  static void screen(String screenName) {
    if (!kDebugMode) return;
    currentScreen = screenName;
    debugPrint('\n${_timestamp()} [SCREEN]\nOpened $screenName\n');
  }

  /// Log screen loaded notification
  static void screenLoaded(String screenName) {
    if (!kDebugMode) return;
    currentScreen = screenName;
    debugPrint('${_timestamp()} [SCREEN]\n$screenName Loaded\n');
  }

  /// Log generic user click/tap action
  static void click(String description, {String? screen}) {
    if (!kDebugMode) return;
    final sc = screen ?? currentScreen;
    debugPrint('${_timestamp()} [CLICK]\nScreen: $sc\nUser tapped "$description"\n');
  }

  /// Log button tap action
  static void button(String buttonName, {String? screen}) {
    if (!kDebugMode) return;
    final sc = screen ?? currentScreen;
    debugPrint('${_timestamp()} [BUTTON]\nScreen: $sc\nButton: $buttonName\n');
  }

  /// Log navigation event
  static void navigation(String from, String to, {dynamic arguments}) {
    if (!kDebugMode) return;
    final argsStr = arguments != null ? '\nArguments:\n$arguments' : '';
    debugPrint('${_timestamp()} [NAVIGATION]\nFrom:\n$from\n\nTo:\n$to$argsStr\n');
  }

  /// Log SnackBar displayed
  static void snackbar(String message, {String type = 'Info', String? screen}) {
    if (!kDebugMode) return;
    final sc = screen ?? currentScreen;
    debugPrint('${_timestamp()} [SNACKBAR]\nScreen:\n$sc\nType:\n$type\nMessage:\n$message\n');
  }

  /// Log dialog opened
  static void dialogOpen(String title, {String? screen}) {
    if (!kDebugMode) return;
    final sc = screen ?? currentScreen;
    debugPrint('${_timestamp()} [DIALOG OPEN]\nTitle:\n$title\nScreen:\n$sc\n');
  }

  /// Log dialog closed
  static void dialogClose(String result, {String? screen}) {
    if (!kDebugMode) return;
    final sc = screen ?? currentScreen;
    debugPrint('${_timestamp()} [DIALOG CLOSE]\nScreen:\n$sc\nResult:\n$result\n');
  }

  /// Log API request start
  static void apiStart(String method, String path) {
    if (!kDebugMode) return;
    debugPrint('${_timestamp()} [API]\n$method $path\nStarted\n');
  }

  /// Log API request success
  static void apiSuccess(String method, String path, int statusCode) {
    if (!kDebugMode) return;
    debugPrint('${_timestamp()} [API]\n$method $path\nCompleted ($statusCode)\n');
  }

  /// Log API request failure
  static void apiError(String method, String path, int? statusCode, Object error) {
    if (!kDebugMode) return;
    final statusStr = statusCode != null ? ' ($statusCode)' : '';
    debugPrint('🚨 ${_timestamp()} [API FAILED]\n$method $path$statusStr\nError: $error\n');
  }

  /// Log loading state change
  static void loading(String action, bool isStart, {String? screen}) {
    if (!kDebugMode) return;
    final sc = screen ?? currentScreen;
    final stateStr = isStart ? 'Started' : 'Completed';
    debugPrint('${_timestamp()} [LOADING]\nScreen: $sc\n$action $stateStr\n');
  }

  /// Log exception or error
  static void error(String action, Object exception, [StackTrace? stackTrace, String? screen]) {
    if (!kDebugMode) return;
    final sc = screen ?? currentScreen;
    final stStr = stackTrace != null ? '\nStacktrace:\n$stackTrace' : '';
    debugPrint('🚨 ${_timestamp()} [ERROR]\nScreen:\n$sc\nAction:\n$action\nException:\n$exception$stStr\n');
  }
}
