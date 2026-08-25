import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/core/widgets/app_avatar.dart';

class IncomingCallPage extends ConsumerWidget {
  const IncomingCallPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchState = ref.watch(matchmakingControllerProvider);
    final controller = ref.read(matchmakingControllerProvider.notifier);

    ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      if (next.phase == MatchmakingPhase.idle) {
        if (mounted(context)) {
          context.go(RouteNames.home);
        }
      }
    });

    final String displayName = matchState.matchedUser?.fullName ?? 'User';
    final String initials = getInitials(displayName);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0C22), // Solid dark purple-blue background
      body: Stack(
        children: [
          // Background concentric circles
          const Positioned.fill(
            child: CustomPaint(
              painter: _ConcentricCirclesPainter(),
            ),
          ),

          // Central Profile Avatar and Caller name
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  // Pulsing avatar circle
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF6B4EFF).withValues(alpha: 0.4),
                        width: 3.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6B4EFF).withValues(alpha: 0.15),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: AppAvatar(
                      avatarSeed: matchState.matchedUser?.avatarSeed,
                      avatarStyle: matchState.matchedUser?.avatarStyle,
                      gender: matchState.matchedUser?.gender,
                      initials: initials,
                      radius: 70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Incoming Call...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Accept/Decline action buttons at bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline Button (Red)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        controller.declineCall();
                      },
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF5350), // Red
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.call_end_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Decline',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),

                // Accept Button (Green)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        controller.acceptCall();
                      },
                      child: Container(
                        width: 68,
                        height: 68,
                        decoration: const BoxDecoration(
                          color: Color(0xFF4CAF50), // Green
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.phone_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Accept',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool mounted(BuildContext context) {
    try {
      // ignore: unnecessary_null_comparison
      return context != null && (context as Element).mounted;
    } catch (_) {
      return false;
    }
  }
}

class _ConcentricCirclesPainter extends CustomPainter {
  const _ConcentricCirclesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xFF7A58FF).withValues(alpha: 0.15)
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, 90, paint);
    canvas.drawCircle(center, 130, paint);
    canvas.drawCircle(center, 170, paint..color = const Color(0xFF7A58FF).withValues(alpha: 0.08));
    canvas.drawCircle(center, 210, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
