import 'package:flutter/material.dart';
import 'package:dating_app/core/utils/app_logger.dart';

/// Centralized utility for showing SnackBars across the application.
/// Automatically logs every error, success, or info SnackBar message to the terminal.
class AppSnackBar {
  /// Displays a custom [SnackBar] and routes logs to AppLogger.
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

    final typeStr = isError ? 'Error' : 'Success';
    AppLogger.snackbar(logText, type: typeStr);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// Displays an Error SnackBar with red background and logs to AppLogger.
  static void showError(BuildContext context, String message) {
    AppLogger.snackbar(message, type: 'Error');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  /// Displays a Success SnackBar with green background and logs to AppLogger.
  static void showSuccess(BuildContext context, String message) {
    AppLogger.snackbar(message, type: 'Success');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Displays an Info SnackBar and logs to AppLogger.
  static void showInfo(BuildContext context, String message) {
    AppLogger.snackbar(message, type: 'Info');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }
}
