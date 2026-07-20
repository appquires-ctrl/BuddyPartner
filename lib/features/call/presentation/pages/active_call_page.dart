import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';

/// ActiveCallPage displays the active voice call interface.
/// Wired to the MatchmakingController for real Agora audio/video and
/// server-authoritative call lifecycle.
class ActiveCallPage extends ConsumerStatefulWidget {
  const ActiveCallPage({super.key});

  @override
  ConsumerState<ActiveCallPage> createState() => _ActiveCallPageState();
}

class _ActiveCallPageState extends ConsumerState<ActiveCallPage> {
  @override
  void initState() {
    super.initState();
  }

  String _formatCountdown(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final matchState = ref.watch(matchmakingControllerProvider);
    final controller = ref.read(matchmakingControllerProvider.notifier);

    // Listen for call_ended — navigate to call summary page
    ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      if (next.phase == MatchmakingPhase.ended) {
        if (mounted) {
          context.go(RouteNames.callSummary);
        }
      }
    });

    // If somehow we're on this page but not in a call, go home
    if (matchState.phase == MatchmakingPhase.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go(RouteNames.home);
      });
    }

    final matchedUser = matchState.matchedUser;
    final displayName = matchedUser?.fullName ?? 'User';
    final initials = _getInitials(displayName);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0C22), // Solid dark purple-blue background
      body: Stack(
        children: [
          // Background - either remote video view or concentric circles
          if (matchState.isVideoEnabled)
            Positioned.fill(
              child: controller.agoraEngine != null && matchState.remoteUid != null
                  ? AgoraVideoView(
                      controller: VideoViewController.remote(
                        rtcEngine: controller.agoraEngine!,
                        canvas: VideoCanvas(uid: matchState.remoteUid),
                        connection: RtcConnection(channelId: matchState.agoraChannel),
                      ),
                    )
                  : Container(
                      color: const Color(0xFF0F0C22),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: Color(0xFF7A58FF)),
                            const SizedBox(height: 16),
                            Text(
                              'Waiting for ${matchState.matchedUser?.fullName ?? "user"} to share video...',
                              style: const TextStyle(color: Colors.white70, fontSize: 15),
                            ),
                          ],
                        ),
                      ),
                    ),
            )
          else
            // Concentric circular paths in the background for voice calls
            const Positioned.fill(
              child: CustomPaint(
                painter: _ConcentricCirclesPainter(),
              ),
            ),

          // Floating local video view (PiP)
          if (matchState.isVideoEnabled && controller.agoraEngine != null)
            Positioned(
              top: 96,
              right: 24,
              child: Container(
                width: 110,
                height: 160,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF7A58FF), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: controller.agoraEngine!,
                      canvas: const VideoCanvas(uid: 0),
                    ),
                  ),
                ),
              ),
            ),



          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                  const SizedBox(height: 12),
                  // Top Navigation & Timer Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                        onPressed: () {
                          // Minimize — just pop the overlay, call continues
                          if (Navigator.of(context).canPop()) {
                            context.pop();
                          }
                        },
                      ),
                      // Countdown timer badge pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              color: Colors.white70,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatCountdown(matchState.remainingSeconds),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 24),
                        onPressed: () {
                          // Action menu placeholder
                        },
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),

                  // Connected status indicator pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2DCE89), // Green dot
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          matchState.isVideoEnabled ? displayName : 'Connected',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (!matchState.isVideoEnabled) ...[
                    const Spacer(flex: 2),

                    // Circular Profile Avatar with purple glowing ring
                    Container(
                      width: 172,
                      height: 172,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF7A58FF), // Violet glowing outline ring
                          width: 4.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF7A58FF).withValues(alpha: 0.25),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        backgroundColor: const Color(0xFFE5DFFF), // Light lavender background
                        backgroundImage: matchedUser?.avatarUrl != null
                            ? NetworkImage(matchedUser!.avatarUrl!)
                            : null,
                        child: matchedUser?.avatarUrl == null
                            ? Text(
                                initials,
                                style: const TextStyle(
                                  color: Color(0xFF6B4EFF), // Purple initials text
                                  fontSize: 52,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                ),
                              )
                            : null,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // User name with verified badge placeholder
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_rounded,
                          color: Color(0xFF9E7CFF), // Violet verified checkmark
                          size: 22,
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Placeholder location/age info (not wired to real data per prompt)
                    const Text(
                      'Voice Call',
                      style: TextStyle(
                        color: Color(0xFFA19EBB),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Action Buttons row: Follow & Message (no-op stubs)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildActionButton(
                          icon: Icons.person_add_alt_1_outlined,
                          label: 'Follow',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Coming soon!'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: 16),
                        _buildActionButton(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: 'Message',
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Coming soon!'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                    const Spacer(flex: 3),
                  ] else ...[
                    const Spacer(flex: 5),
                  ],

                  // Switch to Video Call banner card
                  if (!matchState.isVideoEnabled)
                    GestureDetector(
                      onTap: () {
                        controller.upgradeToVideo();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF7A58FF),
                              ),
                              child: const Icon(
                                Icons.videocam_outlined,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Switch to',
                                    style: TextStyle(
                                      color: Color(0xFFA19EBB),
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Video Call',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.white60,
                              size: 24,
                            ),
                          ],
                        ),
                      ),
                    ),

                  const Spacer(flex: 2),

                  // Bottom Controls row: Mute, End Call, Speaker
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildBottomControl(
                        icon: matchState.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        label: 'Mute',
                        isActive: matchState.isMuted,
                        onTap: () {
                          controller.toggleMute();
                        },
                      ),
                      // End Call button
                      GestureDetector(
                        onTap: () {
                          controller.endCall();
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF5350), // Red end call button
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.call_end_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'End Call',
                              style: TextStyle(
                                color: Color(0xFFA19EBB),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _buildBottomControl(
                        icon: matchState.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        label: 'Speaker',
                        isActive: matchState.isSpeakerOn,
                        onTap: () {
                          controller.toggleSpeaker();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      );
    },
  ),
),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().toUpperCase().split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}';
    }
    return parts[0].isNotEmpty ? parts[0][0] : 'U';
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1,
          ),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControl({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.12),
            ),
            child: Icon(
              icon,
              color: isActive ? const Color(0xFF0F0C22) : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFA19EBB),
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom Painter to draw faint concentric circle outlines in the background.
class _ConcentricCirclesPainter extends CustomPainter {
  const _ConcentricCirclesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.45); // Centered roughly behind avatar position
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withValues(alpha: 0.04);

    final radii = [120.0, 190.0, 260.0, 330.0, 400.0];
    for (final radius in radii) {
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
