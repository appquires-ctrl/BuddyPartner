import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../extensions/context_extensions.dart';

/// AppLoadingIndicator provides a horizontal staggered wave animation.
/// Replaces generic spinners with a modern 5-bar ripple effect.
class AppLoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;

  const AppLoadingIndicator({
    super.key,
    this.size = 28.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final waveColor = color ?? colors.primary;

    final barWidth = (size * 0.14).clamp(3.0, 6.0);
    final barHeight = size;

    return Center(
      child: SizedBox(
        height: barHeight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(5, (index) {
            final delay = index * 100;
            return Container(
              margin: EdgeInsets.symmetric(horizontal: (barWidth * 0.35).clamp(1.5, 3.0)),
              width: barWidth,
              height: barHeight * 0.75,
              decoration: BoxDecoration(
                color: waveColor,
                borderRadius: BorderRadius.circular(barWidth / 2),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scaleY(
                  begin: 0.35,
                  end: 1.0,
                  duration: 450.ms,
                  delay: delay.ms,
                  curve: Curves.easeInOut,
                );
          }),
        ),
      ),
    );
  }
}
