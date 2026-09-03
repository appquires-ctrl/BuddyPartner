import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:buddypartner/app/router/route_names.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/app_radius.dart';

import 'package:buddypartner/core/widgets/cards/app_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/features/call/application/matchmaking_controller.dart';
import 'package:buddypartner/features/call/application/matchmaking_state.dart';

import 'package:buddypartner/core/widgets/app_avatar.dart';

import 'package:buddypartner/core/utils/app_logger.dart';

/// HostDetailsPage displays a host telecaller profile with large avatar
/// cover photo, overlapping stats card, bios, languages, and action triggers.
class HostDetailsPage extends ConsumerStatefulWidget {
  final String hostId;

  const HostDetailsPage({
    super.key,
    required this.hostId,
  });

  @override
  ConsumerState<HostDetailsPage> createState() => _HostDetailsPageState();
}

class _HostDetailsPageState extends ConsumerState<HostDetailsPage> {
  bool _isFavorited = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typography = context.typography;

    // Mock profiles database lookup
    final name = widget.hostId == 'host_2' ? 'Rohan' : 'Priya';
    final age = widget.hostId == 'host_2' ? 23 : 21;
    final rate = widget.hostId == 'host_2' ? 12 : 10;
    final rating = widget.hostId == 'host_2' ? 4.5 : 4.8;
    final reviews = widget.hostId == 'host_2' ? 16 : 24;
    final avatarSeed = widget.hostId == 'host_2' ? 'male_2f' : 'female_1_new';
    final gender = widget.hostId == 'host_2' ? 'Male' : 'Female';

    return Scaffold(
      body: Stack(
        children: [
          // Cover picture / SVG Avatar hero
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.45,
            child: Container(
              color: colors.primary.withValues(alpha: 0.12),
              child: Center(
                child: AppAvatar(
                  avatarSeed: avatarSeed,
                  gender: gender,
                  radius: 72,
                ),
              ),
            ),
          ),
          
          // Back button and favorite overlays
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.black.withValues(alpha: 0.4),
                  child: const BackButton(color: Colors.white),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.black.withValues(alpha: 0.4),
                  child: IconButton(
                    icon: Icon(
                      _isFavorited ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorited ? colors.danger : Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _isFavorited = !_isFavorited;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Profile Content details sheet
          Positioned(
            top: MediaQuery.of(context).size.height * 0.4,
            left: 0,
            right: 0,
            bottom: 80,
            child: Container(
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.space24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main name card
                    AppCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$name, $age',
                                style: typography.titleCard.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(Icons.star, color: Colors.amber, size: 18),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$rating ($reviews reviews)',
                                    style: typography.bodySmall,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Text(
                            '₹$rate/min',
                            style: typography.headlineGreeting.copyWith(
                              color: colors.primary,
                              fontSize: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.space24),

                    // Bios description
                    Text(
                      'About Me',
                      style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.space8),
                    Text(
                      'Hey there! I love speaking to new people and sharing stories. Let’s connect and talk about travel, music, life, or whatever is on your mind today! I’m highly active and love to keep the conversation positive and fun.',
                      style: typography.bodySmall.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: AppSpacing.space24),

                    // Language chips
                    Text(
                      'Languages',
                      style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.space8),
                    Row(
                      children: [
                        _buildTag('Hindi', colors),
                        const SizedBox(width: 8),
                        _buildTag('English', colors),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.space24),

                    // Interest chips
                    Text(
                      'Interests',
                      style: typography.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.space8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTag('Music', colors),
                        _buildTag('Travel', colors),
                        _buildTag('Gaming', colors),
                        _buildTag('Movies', colors),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Bar action row
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 80,
            child: Container(
              color: colors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        fixedSize: const Size.fromHeight(52),
                        side: BorderSide(color: colors.primary),
                        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
                      ),
                      icon: Icon(Icons.chat_bubble_outline, color: colors.primary),
                      label: Text('Chat', style: TextStyle(color: colors.primary)),
                      onPressed: () {
                        AppLogger.button('Message Host', screen: 'HostDetailsPage');
                        context.pushNamed(RouteNames.chat, queryParameters: {
                          'conversationId': 'conv_${widget.hostId}',
                          'userId': widget.hostId,
                          'userName': name,
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        fixedSize: const Size.fromHeight(52),
                        backgroundColor: colors.success,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: const RoundedRectangleBorder(borderRadius: AppRadius.pill),
                      ),
                      icon: const Icon(Icons.call),
                      label: const Text('Call Now'),
                      onPressed: () {
                        AppLogger.button('Call Now', screen: 'HostDetailsPage');
                        final matchState = ref.read(matchmakingControllerProvider);
                        if (matchState.phase != MatchmakingPhase.idle) return;

                        ref.read(matchmakingControllerProvider.notifier).callUser(
                          targetUserId: widget.hostId,
                          targetUserName: name,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, dynamic colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.chipLavender,
        borderRadius: AppRadius.pill,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: colors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
