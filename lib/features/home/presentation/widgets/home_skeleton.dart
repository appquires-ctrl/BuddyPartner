import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/app/theme/app_spacing.dart';
import 'package:buddypartner/app/theme/skeleton_colors.dart';
import 'package:buddypartner/core/widgets/shimmer/app_shimmer.dart';
import 'package:buddypartner/features/auth/application/auth_state_provider.dart';

/// HomeSkeleton renders an accurate shimmering placeholder for the Home screen.
/// Accurately reflects both top cards (Matchmaking banner + Female Incoming Calls Toggle / Male VIP Instant Connect)
/// alongside the Discover section and matched user cards.
class HomeSkeleton extends ConsumerWidget {
  final bool? isFemale;

  const HomeSkeleton({
    super.key,
    this.isFemale,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = SkeletonColors.accentColor(isDark);
    final authUser = ref.watch(authStateProvider).value;
    final effectiveIsFemale = isFemale ?? authUser?.isFemale;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 16.0,
        title: AppShimmer(
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 90,
                    height: 16,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    width: 60,
                    height: 12,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: AppShimmer(
                child: Container(
                  width: 96,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space24),
          child: AppShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 16),

                // ── Card 1: Matchmaking Main Banner Skeleton ────────────────
                Container(
                  height: 132,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 110,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.black12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: 130,
                              height: 22,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white12 : Colors.black12,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              width: 170,
                              height: 13,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.black12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white12 : Colors.black12,
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Card 2: Gender-Specific Secondary Card Skeleton ──────────
                if (effectiveIsFemale == true)
                  // Female User: Incoming Paid Calls Toggle Banner Skeleton
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    height: 112,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white12 : Colors.black12,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    width: 130,
                                    height: 15,
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white12 : Colors.black12,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: 165,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : Colors.black12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Toggle Switch Pill Skeleton
                        Container(
                          width: 52,
                          height: 30,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white12 : Colors.black12,
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (effectiveIsFemale == false)
                  // Male User: VIP Instant Connect Banner Skeleton
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    height: 100,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white12 : Colors.black12,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 140,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white12 : Colors.black12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                width: 180,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white10 : Colors.black12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : Colors.black12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  // Gender not yet loaded: generic second card skeleton
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    height: 100,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),

                const SizedBox(height: 24),

                // ── DISCOVER and History Row Skeleton ────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 75,
                      height: 16,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    Container(
                      width: 50,
                      height: 16,
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ── Discover Cards Horizontal Row Skeleton ───────────────────
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 3,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 16.0),
                        child: Container(
                          width: 150,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Avatar circle
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white12 : Colors.black12,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Name bar
                              Container(
                                width: 80,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white12 : Colors.black12,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Call / Chat Button pill
                              Container(
                                width: 100,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white12 : Colors.black12,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

