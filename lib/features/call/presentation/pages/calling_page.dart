import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';

/// CallingPage renders a brief "connecting" or "ringing" screen
/// shown before the Agora channel is fully joined.
class CallingPage extends ConsumerWidget {
  final String name;
  final String imageUrl;

  const CallingPage({
    super.key,
    this.name = 'Connecting...',
    this.imageUrl = '',
  });

  String getInitials(String name) {
    return name.isNotEmpty ? name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchState = ref.watch(matchmakingControllerProvider);

    ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      if (next.phase == MatchmakingPhase.idle) {
        if (mounted(context)) {
          context.go(RouteNames.home);
        }
      }
    });

    final displayName = matchState.matchedUser?.fullName ?? name;
    final initials = getInitials(displayName);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0C22), // Solid dark purple-blue background
      body: Stack(
        children: [
          // Concentric circular paths in the background
          const Positioned.fill(
            child: CustomPaint(
              painter: _ConcentricCirclesPainter(),
            ),
          ),

          // Central Profile Avatar and Text info
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  // Pulsing Ring avatar
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF7A58FF).withValues(alpha: 0.4),
                        width: 3.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF7A58FF).withValues(alpha: 0.15),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundColor: const Color(0xFFE5DFFF), // Light lavender background
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: Color(0xFF6B4EFF),
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                  Text(
                    matchState.phase == MatchmakingPhase.outgoingRequest
                        ? 'Ringing...'
                        : 'Connecting...',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Call action bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // End Call / Cancel button
                GestureDetector(
                  onTap: () {
                    if (matchState.phase == MatchmakingPhase.outgoingRequest) {
                      ref.read(matchmakingControllerProvider.notifier).cancelCallRequest();
                    } else {
                      ref.read(matchmakingControllerProvider.notifier).endCall();
                    }
                  },
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF5350), // Red end call button color
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
                  ),
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

/// Custom Painter to draw faint concentric circle outlines in the background.
class _ConcentricCirclesPainter extends CustomPainter {
  const _ConcentricCirclesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45); // Centered behind avatar position
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
