import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/core/widgets/feedback/app_loading_indicator.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/utils/app_snack_bar.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';
import 'package:buddypartner/features/call/presentation/widgets/spin_wheel_dialog.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/call/presentation/widgets/scratch_card_dialog.dart';

import 'package:buddypartner/features/auth/application/auth_state_provider.dart';
import 'package:buddypartner/core/widgets/app_avatar.dart';

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
    Future.microtask(() {
      if (mounted) {
        ref.read(matchmakingControllerProvider.notifier).restoreCall();
      }
    });
  }

  @override
  void dispose() {
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
      if (next.phase == MatchmakingPhase.idle && prev?.phase != MatchmakingPhase.idle ||
          next.phase == MatchmakingPhase.ended) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).popUntil((route) => route is! PopupRoute);
          context.go(RouteNames.home);
        }
      }
      if (next.errorMessage != null &&
          next.errorMessage!.isNotEmpty &&
          prev?.errorMessage != next.errorMessage) {
        if (mounted) {
          AppSnackBar.showError(context, next.errorMessage!);
        }
      }
    });

    // Auto-popup Scratch Card dialog & auto-navigate home on instant call finish
    ref.listen<InstantConnectState>(instantConnectControllerProvider, (prev, next) {
      if (prev?.phase == InstantPhase.inCall && (next.phase == InstantPhase.idle || next.phase == InstantPhase.ended)) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).popUntil((route) => route is! PopupRoute);
          context.go(RouteNames.home);
        }
      }
      if (next.is10mReached && prev?.is10mReached != true && next.latestUnlockedCard != null) {
        if (mounted) {
          ScratchCardDialog.show(context, next.latestUnlockedCard!);
        }
      }
    });

    final matchedUser = matchState.matchedUser;
    final displayName = matchedUser?.fullName ?? 'User';
    final initials = _getInitials(displayName);

    void minimizeCall() {
      HapticFeedback.lightImpact();
      controller.minimizeCall();
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(RouteNames.home);
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        minimizeCall();
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
                        tooltip: 'Minimize Call',
                        onPressed: minimizeCall,
                      ),
                      // Countdown timer badge pill
                      Builder(
                        builder: (context) {
                          final instantState = ref.watch(instantConnectControllerProvider);
                          final isInstantCall = instantState.phase == InstantPhase.inCall;
                          final currentUser = ref.watch(authStateProvider).value;
                          final isFemale = currentUser?.isFemale ?? false;

                          if (isInstantCall) {
                            if (isFemale) {
                              if (instantState.is10mReached) {
                                return GestureDetector(
                                  onTap: () {
                                    if (instantState.latestUnlockedCard != null) {
                                      ScratchCardDialog.show(context, instantState.latestUnlockedCard!);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFFFFD54F), Color(0xFFFFB300)],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFFB300).withValues(alpha: 0.5),
                                          blurRadius: 10,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        Icon(Icons.card_giftcard_rounded, color: Color(0xFF5D4037), size: 16),
                                        SizedBox(width: 6),
                                        Text(
                                          '🎁 Scratch Card Unlocked!',
                                          style: TextStyle(
                                            color: Color(0xFF5D4037),
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }

                              final remainingToMilestone = (600 - instantState.callSecondsElapsed).clamp(0, 600);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C6AEF).withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF7C6AEF).withValues(alpha: 0.6)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.bolt_rounded, color: Color(0xFFFFD54F), size: 16),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Reward in ${_formatCountdown(remainingToMilestone)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            } else {
                              // Male User Screen: Normal instant call timer without reward text
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C6AEF).withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF7C6AEF).withValues(alpha: 0.6)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.bolt_rounded, color: Color(0xFFFFD54F), size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatCountdown(instantState.callSecondsElapsed > 0
                                          ? instantState.callSecondsElapsed
                                          : matchState.callDurationSeconds),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                          }

                          return Container(
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
                                  _formatCountdown(matchState.callDurationSeconds),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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
                        userAvatar: matchedUser?.avatarUrl,
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

                    const Text(
                      'Voice Call',
                      style: TextStyle(
                        color: Color(0xFFA19EBB),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Action Buttons row: Spin Wheel, Follow & Message
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _buildActionButton(
                          icon: Icons.casino_rounded,
                          label: 'Spin Wheel',
                          onTap: () {
                            SpinWheelDialog.show(context);
                          },
                        ),
                        _buildActionButton(
                          icon: Icons.person_add_alt_1_outlined,
                          label: 'Follow',
                          onTap: () {
                            AppSnackBar.showInfo(context, 'Coming soon!');
                          },
                        ),
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
                          HapticFeedback.mediumImpact();
                          controller.endCall();
                          ref.read(instantConnectControllerProvider.notifier).endCall();
                          if (mounted) {
                            Navigator.of(context, rootNavigator: true).popUntil((route) => route is! PopupRoute);
                            context.go(RouteNames.home);
                          }
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

          // Incoming Video Call Request top banner overlay (Topmost Z-Index Layer)
          if (matchState.isVideoRequestIncoming)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: Material(
                elevation: 16,
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF1E1B3A),
                shadowColor: Colors.black.withValues(alpha: 0.9),
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
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
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
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
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
                                padding: const EdgeInsets.symmetric(vertical: 12),
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
],
),
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
