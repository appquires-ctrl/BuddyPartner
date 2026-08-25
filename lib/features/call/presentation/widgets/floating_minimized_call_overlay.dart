import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/app_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/widgets/gradient_avatar.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';

/// FloatingMinimizedCallOverlay displays a floating, interactive Picture-in-Picture (PiP)
/// bar when the user minimizes an active call to continue exploring the application.
class FloatingMinimizedCallOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const FloatingMinimizedCallOverlay({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<FloatingMinimizedCallOverlay> createState() =>
      _FloatingMinimizedCallOverlayState();
}

class _FloatingMinimizedCallOverlayState
    extends ConsumerState<FloatingMinimizedCallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Draggable position offsets
  double? _top;
  double? _left;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatTimer(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _restoreCall() {
    HapticFeedback.lightImpact();
    ref.read(matchmakingControllerProvider.notifier).restoreCall();

    final navContext = rootNavigatorKey.currentContext;
    if (navContext != null && navContext.mounted) {
      navContext.push(RouteNames.activeCall);
    }
  }

  void _toggleSpeaker() {
    HapticFeedback.lightImpact();
    ref.read(matchmakingControllerProvider.notifier).toggleSpeaker();
  }

  void _endCall() {
    HapticFeedback.mediumImpact();
    ref.read(matchmakingControllerProvider.notifier).endCall();
    ref.read(instantConnectControllerProvider.notifier).endCall();
  }

  @override
  Widget build(BuildContext context) {
    final matchState = ref.watch(matchmakingControllerProvider);
    final isCallActive = matchState.phase == MatchmakingPhase.inCall;
    final isMinimized = matchState.isCallMinimized && isCallActive;

    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Default position docked near bottom above bottom navigation
    final defaultTop = screenSize.height - bottomPadding - 160;
    const defaultLeft = 14.0;

    final currentTop = (_top ?? defaultTop).clamp(
      topPadding + 10,
      screenSize.height - bottomPadding - 85,
    );
    final currentLeft = (_left ?? defaultLeft).clamp(
      8.0,
      screenSize.width - 240,
    );

    final matchedUser = matchState.matchedUser;
    final displayName = matchedUser?.fullName.split(' ').first ?? 'User';
    final initials = (displayName.isNotEmpty ? displayName[0] : 'U').toUpperCase();

    return Stack(
      children: [
        widget.child,

        // ── Floating Minimized Call Overlay ──────────────────────────────
        if (isMinimized)
          Positioned(
            top: currentTop,
            left: currentLeft,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _top = (_top ?? defaultTop) + details.delta.dy;
                  _left = (_left ?? defaultLeft) + details.delta.dx;
                });
              },
              onTap: _restoreCall,
              child: Material(
                type: MaterialType.transparency,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1F1B38), Color(0xFF131024)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF7C6AEF).withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C6AEF).withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: 1,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Avatar with pulsing live indicator halo
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7C6AEF), Color(0xFFE879F9)],
                              ),
                            ),
                            child: GradientAvatar(
                              initials: initials,
                              avatarSeed: matchedUser?.avatarSeed,
                              avatarStyle: matchedUser?.avatarStyle,
                              gender: matchedUser?.gender,
                              userAvatar: matchedUser?.avatarUrl,
                              radius: 17,
                            ),
                          ),
                          Positioned(
                            bottom: -1,
                            right: -1,
                            child: ScaleTransition(
                              scale: _pulseAnimation,
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF131024),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),

                      // 2. Caller Name & Live Call Timer
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.phone_in_talk_rounded,
                                color: Color(0xFF10B981),
                                size: 11,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatTimer(matchState.callDurationSeconds),
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      

                      // 3. Speaker Toggle Button
                      GestureDetector(
                        onTap: _toggleSpeaker,
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: matchState.isSpeakerOn
                                ? const Color(0xFF7C6AEF)
                                : Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            matchState.isSpeakerOn
                                ? Icons.volume_up_rounded
                                : Icons.volume_down_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),

                      // 4. Maximize / Restore Button
                      GestureDetector(
                        onTap: _restoreCall,
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.open_in_full_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),

                      // 5. End Call Button
                      GestureDetector(
                        onTap: _endCall,
                        child: Container(
                          width: 36,
                          height: 36,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x66EF4444),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.call_end_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
