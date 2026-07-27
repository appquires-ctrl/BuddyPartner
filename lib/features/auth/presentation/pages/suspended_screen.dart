import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';

class SuspendedScreen extends StatefulWidget {
  final String? suspendedUntilIso;

  const SuspendedScreen({super.key, this.suspendedUntilIso});

  @override
  State<SuspendedScreen> createState() => _SuspendedScreenState();
}

class _SuspendedScreenState extends State<SuspendedScreen> {
  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _calculateRemaining();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _calculateRemaining() {
    if (widget.suspendedUntilIso == null) return;
    try {
      final until = DateTime.parse(widget.suspendedUntilIso!).toLocal();
      final now = DateTime.now();
      final diff = until.difference(now);
      setState(() {
        _remaining = diff.isNegative ? Duration.zero : diff;
      });
    } catch (_) {
      setState(() {
        _remaining = Duration.zero;
      });
    }
  }

  String _formatDuration(Duration d) {
    if (d == Duration.zero) return 'Suspension expired. Please restart the app.';
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: colors.warningAmber.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.timer_outlined,
                  size: 48,
                  color: colors.warningAmber,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Account Temporarily Suspended',
                style: typography.titleCard.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your account has received a moderation strike and is currently suspended from making calls or messaging.',
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: AppRadius.lg,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  children: [
                    Text(
                      'Time Remaining Until Access Restored',
                      style: typography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDuration(_remaining),
                      style: typography.titleCard.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 28,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Further policy violations will lead to increased suspension time or a permanent ban.',
                style: typography.bodySmall.copyWith(
                  color: colors.danger,
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
