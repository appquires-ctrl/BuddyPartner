import 'package:flutter/material.dart';
import 'package:buddypartner/core/utils/app_logger.dart';

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

  /// Displays an Error SnackBar with clean formatting and logs to AppLogger.
  static void showError(BuildContext context, String message) {
    String cleanMessage = message;
    final lower = message.toLowerCase();

    if (lower.contains('socketexception') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('connection timeout') ||
        lower.contains('connection error') ||
        lower.contains('network error') ||
        lower.contains('clientexception') ||
        lower.contains('handshakeexception') ||
        lower.contains('os error: no address associated with hostname')) {
      cleanMessage = 'No internet connection. Please check your network settings and try again.';
    }

    AppLogger.snackbar(cleanMessage, type: 'Error');
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                cleanMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        duration: const Duration(seconds: 3),
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
