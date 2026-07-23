import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dating_app/core/widgets/shimmer/skeletons/call_history_skeleton.dart';
import 'package:dating_app/features/auth/application/auth_state_provider.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/app_radius.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';
import 'package:dating_app/features/home/presentation/widgets/matching_illustration.dart';
import 'package:dating_app/features/history/data/call_history_provider.dart';
import 'package:dating_app/features/call/application/matchmaking_controller.dart';
import 'package:dating_app/features/call/application/matchmaking_state.dart';

/// CallHistoryPage renders the list of call logs fetched dynamically from Supabase.
class CallHistoryPage extends ConsumerStatefulWidget {
  const CallHistoryPage({super.key});

  @override
  ConsumerState<CallHistoryPage> createState() => _CallHistoryPageState();
}

class _CallHistoryPageState extends ConsumerState<CallHistoryPage> {
  Future<void> _handleRefresh() async {
    ref.invalidate(callHistoryProvider);
    await ref.read(callHistoryProvider.future);
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m > 0) {
      return '${m}m ${s}s';
    }
    return '${s}s';
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final difference = now.difference(dt);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().toUpperCase().split(RegExp(r'\s+'));
    if (parts.length > 1) {
      return '${parts[0][0]}${parts[1][0]}';
    }
    return parts[0].isNotEmpty ? parts[0][0] : 'U';
  }

  /// Initiate a direct call to this user and navigate to the calling screen.
  void _callUser(CallLog log) {
    final controller = ref.read(matchmakingControllerProvider.notifier);
    final currentState = ref.read(matchmakingControllerProvider);

    // Only start if not already in a call/queue
    if (currentState.phase != MatchmakingPhase.idle) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A call is already in progress.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Determine the other user's ID (caller or matched, whichever isn't us)
    final currentUserId = ref.read(authStateProvider).value?.id;
    final targetUserId = log.matchedUserId == currentUserId
        ? log.callerId
        : log.matchedUserId;

    controller.callUser(
      targetUserId: targetUserId,
      targetUserName: log.otherUserName,
      targetUserAvatar: log.otherUserAvatar,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;
    final historyAsync = ref.watch(callHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => context.pop(),
        ),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              'Call History',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'View your recent calls',
              style: typography.bodySmall.copyWith(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: const Color(0xFF3B82F6), // Blue refresh indicator
        child: historyAsync.when(
          loading: () => ListView.builder(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.space16,
              vertical: AppSpacing.space12,
            ),
            itemCount: 5,
            itemBuilder: (context, index) => const CallHistorySkeleton(),
          ),
          error: (err, stack) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.space24),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 80),
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Failed to load call history',
                      style: typography.titleCard.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      err.toString(),
                      style: TextStyle(color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
          data: (logs) {
            if (logs.isEmpty) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 80),
                      // Centered concentric call orbits radar illustration
                      const Center(
                        child: MatchingIllustration(
                          primaryColor: Color(0xFF3B82F6), // Blue orbits
                          centerCircleColor: Color(0xFFEAF5FF), // Light blue background
                          icon: Icons.call, // Phone icon
                          iconColor: Color(0xFF3B82F6), // Blue icon
                        ),
                      ),
                      const SizedBox(height: 48),

                      // Heading text
                      Text(
                        'No Call History',
                        style: typography.titleCard.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: colors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),

                      // Helper Subtitle information
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Your call history will appear here once you make your first call.',
                          style: typography.bodySmall.copyWith(
                            color: colors.textSecondary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    //   const SizedBox(height: 32),

                    //   // Light blue pull down action button
                    //   GestureDetector(
                    //     onTap: _handleRefresh,
                    //     child: Container(
                    //       padding: const EdgeInsets.symmetric(
                    //         horizontal: 20,
                    //         vertical: 10,
                    //       ),
                    //       decoration: BoxDecoration(
                    //         color: const Color(0xFFEAF5FF), // light blue fill
                    //         borderRadius: AppRadius.pill,
                    //       ),
                    //       child: const Row(
                    //         mainAxisSize: MainAxisSize.min,
                    //         children: [
                    //           Icon(
                    //             Icons.refresh,
                    //             color: Color(0xFF3B82F6), // blue icon
                    //             size: 16,
                    //           ),
                    //           SizedBox(width: 8),
                    //           Text(
                    //             'Pull down to refresh',
                    //             style: TextStyle(
                    //               color: Color(0xFF3B82F6), // blue text
                    //               fontSize: 12,
                    //               fontWeight: FontWeight.bold,
                    //             ),
                    //           ),
                    //         ],
                    //       ),
                    //     ),
                    //   ),
                    //   const SizedBox(height: 80),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.space24,
                vertical: AppSpacing.space16,
              ),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                final isOutgoing = log.callerId == ref.read(authStateProvider).value?.id;
                final isVideo = log.callType == 'video';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Other user's avatar or initials
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: const Color(0xFFE5DFFF),
                        backgroundImage: log.otherUserAvatar != null
                            ? NetworkImage(log.otherUserAvatar!)
                            : null,
                        child: log.otherUserAvatar == null
                            ? Text(
                                _getInitials(log.otherUserName),
                                style: const TextStyle(
                                  color: Color(0xFF6B4EFF),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),

                      // Caller info details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log.otherUserName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: colors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  isOutgoing ? Icons.call_made_rounded : Icons.call_received_rounded,
                                  color: isOutgoing ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isOutgoing ? 'Outgoing' : 'Incoming',
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 3.5,
                                  height: 3.5,
                                  decoration: BoxDecoration(
                                    color: colors.textSecondary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatDateTime(log.startedAt),
                                  style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Call duration & Call-back button
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Tappable call button
                          GestureDetector(
                            onTap: () => _callUser(log),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF3EFFF),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isVideo ? Icons.videocam_rounded : Icons.phone_rounded,
                                color: const Color(0xFF7A58FF),
                                size: 20,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDuration(log.durationSeconds),
                            style: TextStyle(
                              color: colors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
