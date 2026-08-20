import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';

class IncomingPaidCallDialog extends ConsumerStatefulWidget {
  const IncomingPaidCallDialog({super.key});

  @override
  ConsumerState<IncomingPaidCallDialog> createState() => _IncomingPaidCallDialogState();
}

class _IncomingPaidCallDialogState extends ConsumerState<IncomingPaidCallDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  Timer? _countdownTimer;
  int _secondsRemaining = 7;
  bool _actionHandled = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining <= 1) {
        timer.cancel();
        _onDecline();
      } else {
        setState(() {
          _secondsRemaining -= 1;
        });
      }
    });
  }

  void _onAccept() {
    if (_actionHandled) return;
    _actionHandled = true;
    HapticFeedback.mediumImpact();
    _countdownTimer?.cancel();
    ref.read(instantConnectControllerProvider.notifier).acceptIncomingCall();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _onDecline() {
    if (_actionHandled) return;
    _actionHandled = true;
    HapticFeedback.lightImpact();
    _countdownTimer?.cancel();
    ref.read(instantConnectControllerProvider.notifier).declineIncomingCall();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    // Auto-dismiss dialog if phase leaves incomingRequest (e.g. connected or dismissed)
    ref.listen<InstantConnectState>(instantConnectControllerProvider, (prev, next) {
      if (next.phase != InstantPhase.incomingRequest && !_actionHandled && mounted) {
        _actionHandled = true;
        _countdownTimer?.cancel();
        Navigator.of(context, rootNavigator: true).pop();
      }
    });

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB300).withValues(alpha: 0.35),
                blurRadius: 30,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // VIP Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF8F00).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      'INSTANT PAID CALL',
                      style: typography.bodySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Animated Pulsing Avatar Placeholder
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final scale = 1.0 + (_pulseController.value * 0.08);
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF8B7CF6), Color(0xFFE8A9E0)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF8B7CF6).withValues(alpha: 0.4),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.person_rounded, color: Colors.white, size: 48),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // Anonymous Title
              Text(
                'Incoming Paid Connection',
                style: typography.titleCard.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Answer within $_secondsRemaining seconds to earn your 10-min Scratch Card!',
                style: typography.bodySmall.copyWith(
                  color: colors.textSecondary,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Actions (Decline & Accept)
              Row(
                children: [
                  // Decline
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _onDecline,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(color: colors.danger.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        'Decline',
                        style: TextStyle(
                          color: colors.danger,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Accept
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _onAccept,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: colors.success,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.call, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Accept',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
