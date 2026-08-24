import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/services/network_connectivity_service.dart';

/// Professional Modal Dialog shown when internet connection is lost.
class NoInternetDialog extends ConsumerStatefulWidget {
  final VoidCallback? onRetrySuccess;

  const NoInternetDialog({
    super.key,
    this.onRetrySuccess,
  });

  static Future<void> show(BuildContext context, {VoidCallback? onRetrySuccess}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => NoInternetDialog(onRetrySuccess: onRetrySuccess),
    );
  }

  @override
  ConsumerState<NoInternetDialog> createState() => _NoInternetDialogState();
}

class _NoInternetDialogState extends ConsumerState<NoInternetDialog>
    with SingleTickerProviderStateMixin {
  bool _isRetrying = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _handleRetry() async {
    if (_isRetrying) return;
    HapticFeedback.mediumImpact();
    setState(() => _isRetrying = true);

    final isOnline = await ref
        .read(networkConnectivityProvider.notifier)
        .checkConnection();

    if (mounted) {
      setState(() => _isRetrying = false);
      if (isOnline) {
        HapticFeedback.heavyImpact();
        Navigator.of(context).pop();
        widget.onRetrySuccess?.call();
      } else {
        HapticFeedback.vibrate();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Still offline. Please check your data connection.'),
              ],
            ),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Glowing Animated WiFi-Off Badge
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1.0 + (_pulseController.value * 0.08);
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Title & Subtitle
            const Text(
              'No Internet Connection',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You are currently offline. Please check your network connection and try again.',
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),

            // 3. Quick Network Tips Box
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF28233C) : const Color(0xFFF7F6FC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildTipRow(Icons.wifi_rounded, 'Check your Wi-Fi or Mobile Data', isDark),
                  const SizedBox(height: 8),
                  _buildTipRow(Icons.airplanemode_active_rounded, 'Toggle Airplane Mode On / Off', isDark),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // 4. Action Buttons
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isRetrying ? null : _handleRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C6AEF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                child: _isRetrying
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.refresh_rounded, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Retry Connection',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Dismiss',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipRow(IconData icon, String text, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF7C6AEF)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }
}
