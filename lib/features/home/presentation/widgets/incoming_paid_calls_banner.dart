import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/core/widgets/coins/app_coin_icon.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/call/presentation/widgets/scratch_card_dialog.dart';

class IncomingPaidCallsBanner extends ConsumerStatefulWidget {
  const IncomingPaidCallsBanner({super.key});

  @override
  ConsumerState<IncomingPaidCallsBanner> createState() => _IncomingPaidCallsBannerState();
}

class _IncomingPaidCallsBannerState extends ConsumerState<IncomingPaidCallsBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final instantConnectState = ref.watch(instantConnectControllerProvider);
    final isEnabled = instantConnectState.femaleStatus.incomingPaidCallsEnabled;
    final unscratchedCards =
        instantConnectState.scratchCards.where((c) => !c.isScratched).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 0,top: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isEnabled
              ? const [
                  Color(0xFF1E1B3A),
                  Color(0xFF28224F),
                  Color(0xFF181530),
                ]
              : const [
                  Color(0xFF1F1D2B),
                  Color(0xFF171622),
                ],
        ),
        border: Border.all(
          color: isEnabled
              ? const Color(0xFF8B5CF6).withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isEnabled
                ? const Color(0xFF7C6AEF).withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.2),
            blurRadius: isEnabled ? 20 : 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Background ambient decorative orbs
            if (isEnabled) ...[
              Positioned(
                top: -35,
                right: -35,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  ),
                ),
              ),
              Positioned(
                bottom: -40,
                left: -20,
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                  ),
                ),
              ),
            ],

            Padding(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header Row ──────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Status Icon Badge
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isEnabled
                                ? const [Color(0xFF10B981), Color(0xFF059669)]
                                : [
                                    Colors.white.withValues(alpha: 0.12),
                                    Colors.white.withValues(alpha: 0.05),
                                  ],
                          ),
                          boxShadow: isEnabled
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : null,
                          border: Border.all(
                            color: isEnabled
                                ? Colors.white.withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.08),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            isEnabled ? Icons.phone_in_talk_rounded : Icons.phone_paused_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Title & Live Status Chip
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Go Online and Earn',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            // Status Pill
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isEnabled
                                    ? const Color(0xFF10B981).withValues(alpha: 0.16)
                                    : Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isEnabled
                                      ? const Color(0xFF10B981).withValues(alpha: 0.35)
                                      : Colors.white.withValues(alpha: 0.1),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isEnabled) ...[
                                    AnimatedBuilder(
                                      animation: _pulseAnimation,
                                      builder: (context, child) {
                                        return Container(
                                          width: 7,
                                          height: 7,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF10B981)
                                                .withValues(alpha: _pulseAnimation.value),
                                            boxShadow: [
                                              BoxShadow(
                                                color: const Color(0xFF10B981)
                                                    .withValues(alpha: _pulseAnimation.value * 0.7),
                                                blurRadius: 6,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Active & Ready to Earn',
                                      style: TextStyle(
                                        color: Color(0xFF34D399),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ] else ...[
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Offline • Toggle ON to Earn',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.6),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Toggle Switch
                      Transform.scale(
                        scale: 0.88,
                        child: Switch(
                          value: isEnabled,
                          activeThumbColor: Colors.white,
                          activeTrackColor: const Color(0xFF10B981),
                          inactiveThumbColor: Colors.white70,
                          inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (val) {
                            HapticFeedback.selectionClick();
                            ref
                                .read(instantConnectControllerProvider.notifier)
                                .toggleIncomingPaidCalls(val);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  // ── Feature Badges & Subtitle ────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Perk 1: Earn Coins
                        Expanded(
                          child: Row(
                            children: [
                              const AppCoinIcon(size: 22, withGlow: true),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Earn Per Call',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                    Text(
                                      'Instant coins credited',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Vertical Divider
                        Container(
                          width: 1,
                          height: 28,
                          color: Colors.white.withValues(alpha: 0.08),
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                        ),

                        // Perk 2: 10m Scratch Cards
                        Expanded(
                          child: Row(
                            children: [
                              // Container(
                              //   padding: const EdgeInsets.all(5),
                              //   decoration: BoxDecoration(
                              //     color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                              //     shape: BoxShape.circle,
                              //   ),
                              //   child: const Icon(
                              //     Icons.card_giftcard_rounded,
                              //     color: Color(0xFFC084FC),
                              //     size: 15,
                              //   ),
                              // ),
                              // const SizedBox(width: 8),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '10 min Bonus Card',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                    Text(
                                      'Unlock gift rewards',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 10,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Unclaimed Scratch Cards Callout (if any) ─────────────
                  if (unscratchedCards.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        ScratchCardDialog.show(context, unscratchedCards.first);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFB703), Color(0xFFFB8500)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFB703).withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.redeem_rounded,
                                color: Color(0xFF3F2305),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${unscratchedCards.length} Scratch Card${unscratchedCards.length > 1 ? 's' : ''} Ready! Tap to Reveal',
                                style: const TextStyle(
                                  color: Color(0xFF3F2305),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Color(0xFF3F2305),
                              size: 13,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
