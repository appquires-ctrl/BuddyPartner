import 'package:flutter/material.dart';
import 'package:dating_app/core/widgets/shimmer/app_shimmer.dart';
import 'package:dating_app/app/theme/app_radius.dart';

/// RechargePlanSkeleton renders a loading layout skeleton
/// matching the RechargePlanCard visual layout block.
class RechargePlanSkeleton extends StatelessWidget {
  const RechargePlanSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.lg,
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Mock coin display block
            Container(
              width: 80,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 12),
            // Mock prices block
            Column(
              children: [
                Container(
                  width: 50,
                  height: 14,
                  color: Colors.white,
                ),
                const SizedBox(height: 6),
                Container(
                  width: 60,
                  height: 12,
                  color: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Mock button block
            Container(
              width: 95,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.pill,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
