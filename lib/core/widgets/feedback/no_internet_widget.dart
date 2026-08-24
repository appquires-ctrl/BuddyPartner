import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// In-page placeholder widget displayed when a network fetch fails.
class NoInternetWidget extends StatelessWidget {
  final VoidCallback onRetry;
  final String? customMessage;

  const NoInternetWidget({
    super.key,
    required this.onRetry,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                color: Color(0xFFEF4444),
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No Internet Connection',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              customMessage ??
                  'Please check your Wi-Fi or cellular network settings and try again.',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  onRetry();
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Try Again',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C6AEF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
