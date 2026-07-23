import 'package:flutter/material.dart';
import 'package:dating_app/core/widgets/shimmer/app_shimmer.dart';
import 'package:dating_app/app/theme/app_spacing.dart';
import 'package:dating_app/app/theme/skeleton_colors.dart';
import 'package:dating_app/core/extensions/context_extensions.dart';

/// ChatMessageSkeleton renders realistic chat bubble skeletons with text lines
/// shimmering inside distinct message bubble frames.
class ChatMessageSkeleton extends StatelessWidget {
  const ChatMessageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blockColor = SkeletonColors.baseColor(isDark);

    // Mock chat bubbles with realistic layouts: (widthRatio, alignment, lineCount)
    final bubbleConfigs = [
      (0.65, CrossAxisAlignment.start, 2), // 2 lines, left aligned
      (0.45, CrossAxisAlignment.end, 1),   // 1 line, right aligned
      (0.70, CrossAxisAlignment.start, 2), // 2 lines, left aligned
      (0.50, CrossAxisAlignment.end, 1),   // 1 line, right aligned
      (0.40, CrossAxisAlignment.start, 1), // 1 line, left aligned
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.space16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: bubbleConfigs.length,
      itemBuilder: (context, index) {
        final (widthRatio, alignment, lineCount) = bubbleConfigs[index];
        final isMe = alignment == CrossAxisAlignment.end;
        final bubbleBg = isMe
            ? colors.primary.withValues(alpha: 0.12)
            : (isDark ? colors.surface.withValues(alpha: 0.5) : colors.surface);
        final borderColor = isMe ? null : colors.border.withValues(alpha: 0.5);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            crossAxisAlignment: alignment,
            children: [
              Container(
                width: MediaQuery.of(context).size.width * widthRatio,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bubbleBg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isMe ? 16 : 0),
                    bottomRight: Radius.circular(isMe ? 0 : 16),
                  ),
                  border: borderColor != null ? Border.all(color: borderColor) : null,
                ),
                child: AppShimmer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: blockColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      if (lineCount > 1) ...[
                        const SizedBox(height: 6),
                        Container(
                          height: 12,
                          width: MediaQuery.of(context).size.width * (widthRatio * 0.55),
                          decoration: BoxDecoration(
                            color: blockColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
