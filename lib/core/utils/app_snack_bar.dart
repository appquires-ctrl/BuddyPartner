import 'package:flutter/material.dart';

/// Centralized utility for showing SnackBars across the application.
/// Automatically prints every error, success, or info SnackBar message
/// to the terminal console for debugging and monitoring.
class AppSnackBar {
  /// Displays a custom [SnackBar] and prints its message to the terminal console.
  static void show(
    BuildContext context,
    SnackBar snackBar, {
    String? customLogMessage,
  }) {
    String logText = customLogMessage ?? '';
    if (logText.isEmpty && snackBar.content is Text) {
      logText = (snackBar.content as Text).data ?? '';
    }

    final isError = snackBar.backgroundColor == Colors.red ||
        snackBar.backgroundColor == const Color(0xFFDC2626) ||
        snackBar.backgroundColor == const Color(0xFFEF4444) ||
        logText.toLowerCase().contains('error') ||
        logText.toLowerCase().contains('fail') ||
        logText.toLowerCase().contains('required') ||
        logText.toLowerCase().contains('invalid');

    if (isError) {
      debugPrint('🚨 [SNACKBAR ERROR]: $logText');
    } else {
      debugPrint('✅ [SNACKBAR SUCCESS/INFO]: $logText');
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// Displays an Error SnackBar with red background and logs to terminal.
  static void showError(BuildContext context, String message) {
    debugPrint('🚨 [SNACKBAR ERROR]: $message');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Displays a Success SnackBar with green background and logs to terminal.
  static void showSuccess(BuildContext context, String message) {
    debugPrint('✅ [SNACKBAR SUCCESS]: $message');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Displays an Info SnackBar and logs to terminal.
  static void showInfo(BuildContext context, String message) {
    debugPrint('ℹ️ [SNACKBAR INFO]: $message');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }
}
