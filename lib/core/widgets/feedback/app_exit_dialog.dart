import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';

/// Professional exit confirmation dialog shown when user presses back at the app root.
class AppExitDialog extends StatefulWidget {
  const AppExitDialog({super.key});

  /// Shows the dialog and returns true if user confirmed exit, false otherwise.
  static Future<bool> show(BuildContext context) async {
    HapticFeedback.lightImpact();
    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim1, anim2) => const AppExitDialog(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: anim1,
            child: child,
          ),
        );
      },
    );
    return result ?? false;
  }

  @override
  State<AppExitDialog> createState() => _AppExitDialogState();
}

class _AppExitDialogState extends State<AppExitDialog> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1A2E) : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: isDark ? const Color(0xFF2E2942) : const Color(0xFFECEBF3),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Animated Icon Badge
            AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                final scale = 1.0 + (_animController.value * 0.05);
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8B7CF6), Color(0xFF7C6AEF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF7C6AEF).withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.waving_hand_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. Title & Subtitle
            Text(
              'Leaving So Soon?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to exit the app? Your active chats and connections will be waiting for you.',
              style: TextStyle(
                fontSize: 13.5,
                color: colors.textSecondary,
                height: 1.45,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 3. Action Buttons Row
            Row(
              children: [
                // Stay / Cancel Button
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(context).pop(false);
                      },
                      style: OutlinedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFF28233C) : const Color(0xFFF5F4FA),
                        foregroundColor: colors.textPrimary,
                        side: BorderSide(
                          color: isDark ? const Color(0xFF383252) : const Color(0xFFE2E0EC),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Stay',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Exit Button
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 2,
                        shadowColor: const Color(0xFFEF4444).withValues(alpha: 0.35),
                      ),
                      child: const Text(
                        'Exit App',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
