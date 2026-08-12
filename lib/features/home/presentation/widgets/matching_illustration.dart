import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';

/// MatchingIllustration renders the central radar illustration.
/// Customisable for both Home (group/purple) and Favorites (heart/pink) pages.
class MatchingIllustration extends StatefulWidget {
  final Color? primaryColor;
  final Color? centerCircleColor;
  final IconData? icon;
  final Color? iconColor;
  final Widget? centerWidget;

  const MatchingIllustration({
    super.key,
    this.primaryColor,
    this.centerCircleColor,
    this.icon,
    this.iconColor,
    this.centerWidget,
  });

  @override
  State<MatchingIllustration> createState() => _MatchingIllustrationState();
}

class _MatchingIllustrationState extends State<MatchingIllustration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Use passed colors/icons or fallback to Home screen (purple) defaults
    final orbitPrimary = widget.primaryColor ?? colors.primary;
    final centerBg = widget.centerCircleColor ?? const Color(0xFFE5DFFF);
    final iconData = widget.icon ?? Icons.people;
    final iconColor = widget.iconColor ?? const Color(0xFF6B4EFF);

    return SizedBox(
      width: 280,
      height: 280,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              // Rotating orbital paths & glow dots
              CustomPaint(
                size: const Size(280, 280),
                painter: _OrbitsPainter(
                  rotationValue: _controller.value,
                  primaryColor: orbitPrimary,
                  greenColor: colors.success,
                  amberColor: colors.warningAmber,
                  redColor: colors.danger,
                ),
              ),
              
              // Pulsing Center calling icon container matching mockup styles
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: centerBg,
                ),
                child: widget.centerWidget ?? Icon(
                  iconData,
                  color: iconColor,
                  size: 32,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OrbitsPainter extends CustomPainter {
  final double rotationValue;
  final Color primaryColor;
  final Color greenColor;
  final Color amberColor;
  final Color redColor;

  _OrbitsPainter({
    required this.rotationValue,
    required this.primaryColor,
    required this.greenColor,
    required this.amberColor,
    required this.redColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    
    // Style for Concentric Circles
    final circlePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = primaryColor.withOpacity(0.1);

    final radii = [55.0, 90.0, 125.0];

    for (final radius in radii) {
      canvas.drawCircle(center, radius, circlePaint);
    }

    // Helper to draw a glowing dot
    void drawDot(Offset offset, Color color, double radius) {
      final shadowPaint = Paint()
        ..color = color.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(offset, radius + 2.0, shadowPaint);

      final dotPaint = Paint()..color = color;
      canvas.drawCircle(offset, radius, dotPaint);
    }

    // Orbiting Dot 1: Green (Online status)
    final angle1 = rotationValue * 2 * math.pi;
    final dot1 = Offset(
      center.dx + radii[0] * math.cos(angle1),
      center.dy + radii[0] * math.sin(angle1),
    );
    drawDot(dot1, greenColor, 6.0);

    // Orbiting Dot 2: Amber (Busy status)
    final angle2 = -rotationValue * 2 * math.pi + (math.pi * 0.6);
    final dot2 = Offset(
      center.dx + radii[1] * math.cos(angle2),
      center.dy + radii[1] * math.sin(angle2),
    );
    drawDot(dot2, amberColor, 8.0);

    // Orbiting Dot 3: Red (Offline/matching status)
    final angle3 = rotationValue * 2 * math.pi * 0.75 + math.pi;
    final dot3 = Offset(
      center.dx + radii[2] * math.cos(angle3),
      center.dy + radii[2] * math.sin(angle3),
    );
    drawDot(dot3, redColor, 7.0);
  }

  @override
  bool shouldRepaint(covariant _OrbitsPainter oldDelegate) {
    return oldDelegate.rotationValue != rotationValue;
  }
}
