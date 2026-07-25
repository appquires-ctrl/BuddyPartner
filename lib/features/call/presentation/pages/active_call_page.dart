import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/core/widgets/feedback/app_loading_indicator.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:dating_app/app/router/route_names.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'package:dating_app/core/widgets/app_avatar.dart';

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

  @override
  void dispose() {
    // Safety Net: If the page is disposed while still in an active call,
    // automatically trigger controller.endCall() to disconnect audio/video and socket.
    final matchState = ref.read(matchmakingControllerProvider);
    if (matchState.phase == MatchmakingPhase.inCall ||
        matchState.phase == MatchmakingPhase.matched) {
      ref.read(matchmakingControllerProvider.notifier).endCall();
    }
    super.dispose();
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

    ref.listen<MatchmakingState>(matchmakingControllerProvider, (prev, next) {
      if (next.phase == MatchmakingPhase.ended) {
        if (mounted) {
          context.go(RouteNames.callSummary);
        }
      } else if (next.phase == MatchmakingPhase.idle && prev?.phase != MatchmakingPhase.idle) {
        if (mounted) {
          context.go(RouteNames.home);
        }
      }
      if (next.errorMessage != null &&
          next.errorMessage!.isNotEmpty &&
          prev?.errorMessage != next.errorMessage) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.errorMessage!),
              backgroundColor: const Color(0xFFEF4444),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    });

    final matchedUser = matchState.matchedUser;
    final displayName = matchedUser?.fullName ?? 'User';
    final initials = _getInitials(displayName);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _showLeaveCallConfirmationDialog(context, controller);
      },
      child: Scaffold(
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
                            const AppLoadingIndicator(
                              size: 32,
                              color: Color(0xFF7A58FF),
                            ),
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

          // Incoming Video Call Request top banner overlay
          if (matchState.isVideoRequestIncoming)
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1B3A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF7A58FF),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0xFF7A58FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.videocam_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Video Call Request',
                                  style: TextStyle(
                                    color: Color(0xFFA19EBB),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${matchState.videoRequestSenderName ?? "User"} wants to switch to video call',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                              onPressed: () {
                                controller.declineVideoUpgrade();
                              },
                              child: const Text(
                                'Decline',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7A58FF),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                elevation: 0,
                              ),
                              onPressed: () {
                                controller.acceptVideoUpgrade();
                              },
                              child: const Text(
                                'Accept',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                      child: AppAvatar(
                        avatarSeed: matchedUser?.avatarSeed,
                        avatarStyle: matchedUser?.avatarStyle,
                        gender: matchedUser?.gender,
                        initials: initials,
                        radius: 86,
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

                    Consumer(
                      builder: (context, ref, child) {
                        final currentUser = ref.watch(authStateProvider).value;
                        final isFemale = currentUser?.isFemale ?? false;

                        if (isFemale) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.pink.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.pinkAccent.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('🌹 ', style: TextStyle(fontSize: 14)),
                                Text(
                                  '${matchState.rosesEarnedThisCall} Roses earned',
                                  style: const TextStyle(
                                    color: Colors.pinkAccent,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return const Text(
                          'Voice Call',
                          style: TextStyle(
                            color: Color(0xFFA19EBB),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      },
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
                            if (matchedUser == null) return;
                            context.push(RouteNames.chat, extra: {
                              'conversationId': 'user:${matchedUser.id}',
                              'userId': matchedUser.id,
                              'userName': matchedUser.fullName,
                              'userAvatar': matchedUser.avatarUrl,
                            });
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
                      onTap: matchState.isVideoRequestOutgoing
                          ? null
                          : () {
                              controller.upgradeToVideo();
                            },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: matchState.isVideoRequestOutgoing
                              ? const Color(0xFF7A58FF).withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: matchState.isVideoRequestOutgoing
                                ? const Color(0xFF7A58FF)
                                : Colors.white.withValues(alpha: 0.08),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: matchState.isVideoRequestOutgoing
                                    ? const Color(0xFF7A58FF).withValues(alpha: 0.6)
                                    : const Color(0xFF7A58FF),
                              ),
                              child: matchState.isVideoRequestOutgoing
                                  ? const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.videocam_outlined,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    matchState.isVideoRequestOutgoing
                                        ? 'Waiting for response...'
                                        : 'Switch to',
                                    style: const TextStyle(
                                      color: Color(0xFFA19EBB),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    matchState.isVideoRequestOutgoing
                                        ? 'Requesting Video Call'
                                        : 'Video Call',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!matchState.isVideoRequestOutgoing)
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
      ],
    ),
  ),
);
}

  Future<void> _showLeaveCallConfirmationDialog(
    BuildContext context,
    MatchmakingController controller,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1A3A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          icon: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEF5350).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFEF5350),
              size: 32,
            ),
          ),
          title: const Text(
            'Leave Call?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: const Text(
            'Are you sure you want to leave this screen? Leaving will automatically end your call.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFA19EBB),
              fontSize: 14.5,
              height: 1.4,
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          actions: [
            // Button 1: Stay on Call (Cancel)
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'Stay on Call',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            // Button 2: End Call & Exit (Confirm)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF5350),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text(
                'End Call & Exit',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (result == true) {
      await controller.endCall();
    }
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
