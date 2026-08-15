import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:buddypartner/features/call/domain/models/icebreaker_question.dart';

/// SpinWheelDialog renders an interactive, physics-driven custom spin wheel
/// in a glassmorphism bottom sheet for icebreaker questions during call sessions.
class SpinWheelDialog extends StatefulWidget {
  const SpinWheelDialog({super.key});

  /// Helper to show the dialog as a modern modal bottom sheet.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => const SpinWheelDialog(),
    );
  }

  @override
  State<SpinWheelDialog> createState() => _SpinWheelDialogState();
}

class _SpinWheelDialogState extends State<SpinWheelDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _wheelAnimation;

  double _currentRotation = 0.0;
  bool _isSpinning = false;
  IcebreakerQuestion? _selectedQuestion;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );

    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _isSpinning = false;
          _selectedQuestion = _calculateSelectedQuestion(_currentRotation);
        });
        HapticFeedback.heavyImpact();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _spinWheel() {
    if (_isSpinning) return;

    HapticFeedback.mediumImpact();

    setState(() {
      _isSpinning = true;
      _selectedQuestion = null;
    });

    // Random target index (0 to length - 1)
    final randomTargetIndex = math.Random().nextInt(kIcebreakerQuestions.length);
    final sliceAngle = (2 * math.pi) / kIcebreakerQuestions.length;

    // Minimum 5 full rotations (10 * pi) + target angle offset
    final extraRotations = 5 + math.Random().nextInt(3);
    // Align wheel so pointer at top (3*pi/2 or -pi/2) points accurately to selected slice
    final targetAngleOffset = (kIcebreakerQuestions.length - randomTargetIndex - 0.5) * sliceAngle;
    final totalTargetRotation = _currentRotation + (extraRotations * 2 * math.pi) + targetAngleOffset;

    _wheelAnimation = Tween<double>(
      begin: _currentRotation,
      end: totalTargetRotation,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.decelerate,
      ),
    );

    _animationController.reset();
    _animationController.forward().then((_) {
      _currentRotation = totalTargetRotation % (2 * math.pi);
    });
  }

  IcebreakerQuestion _calculateSelectedQuestion(double finalRotationAngle) {
    final sliceAngle = (2 * math.pi) / kIcebreakerQuestions.length;
    // The ticker is fixed at the top (which is -pi/2 or 270 deg in canvas coordinates)
    // Calculate effective index based on final angle
    final normalizedAngle = (2 * math.pi - (finalRotationAngle % (2 * math.pi))) % (2 * math.pi);
    final index = (normalizedAngle / sliceAngle).floor() % kIcebreakerQuestions.length;
    return kIcebreakerQuestions[index];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF130F26), // Deep purple glassmorphism card
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border.all(
          color: const Color(0xFF7A58FF).withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7A58FF).withValues(alpha: 0.2),
            blurRadius: 32,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle pill
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7A58FF).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.casino_rounded,
                      color: Color(0xFF9E7CFF),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Icebreaker Spin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white60),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 12),
          const Text(
            'Spin the wheel to break the ice with a fun question!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFA19EBB),
              fontSize: 13.5,
            ),
          ),

          const SizedBox(height: 24),

          // Spin Wheel Stack
          SizedBox(
            width: 260,
            height: 260,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glowing outer aura ring
                Container(
                  width: 256,
                  height: 256,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7A58FF).withValues(alpha: 0.35),
                        blurRadius: 28,
                        spreadRadius: 6,
                      ),
                    ],
                  ),
                ),

                // Animated Custom Wheel
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    final angle = _isSpinning ? _wheelAnimation.value : _currentRotation;
                    return Transform.rotate(
                      angle: angle,
                      child: CustomPaint(
                        size: const Size(240, 240),
                        painter: _SpinWheelPainter(
                          questions: kIcebreakerQuestions,
                        ),
                      ),
                    );
                  },
                ),

                // Top Center Pointer Ticker Arrow
                Positioned(
                  top: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.6),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: CustomPaint(
                      size: const Size(22, 28),
                      painter: _PointerTickerPainter(),
                    ),
                  ),
                ),

                // Center Spin Button
                GestureDetector(
                  onTap: _spinWheel,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isSpinning
                            ? [const Color(0xFF555555), const Color(0xFF333333)]
                            : [const Color(0xFF9E7CFF), const Color(0xFF6C38FF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _isSpinning ? '...' : 'SPIN',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Selected Question Result Card
          if (_selectedQuestion != null)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _selectedQuestion!.primaryColor.withValues(alpha: 0.25),
                    _selectedQuestion!.secondaryColor.withValues(alpha: 0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _selectedQuestion!.primaryColor.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  // Row(
                  //   mainAxisAlignment: MainAxisAlignment.center,
                  //   children: [
                  //     Icon(
                  //       _selectedQuestion!.icon,
                  //       color: _selectedQuestion!.primaryColor,
                  //       size: 20,
                  //     ),
                  //     const SizedBox(width: 8),
                  //     Container(
                  //       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  //       decoration: BoxDecoration(
                  //         color: _selectedQuestion!.primaryColor.withValues(alpha: 0.3),
                  //         borderRadius: BorderRadius.circular(12),
                  //       ),
                  //       child: Text(
                  //         _selectedQuestion!.category.toUpperCase(),
                  //         style: TextStyle(
                  //           color: _selectedQuestion!.primaryColor,
                  //           fontSize: 11,
                  //           fontWeight: FontWeight.bold,
                  //           letterSpacing: 0.8,
                  //         ),
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  // const SizedBox(height: 10),
                  Text(
                    '"${_selectedQuestion!.text}"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            )
          else if (!_isSpinning)
            const Text(
              'Tap SPIN to select a question!',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),

          const SizedBox(height: 20),

          // Bottom Action Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isSpinning ? null : _spinWheel,
              icon: Icon(
                _selectedQuestion != null ? Icons.autorenew_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
              ),
              label: Text(
                _selectedQuestion != null ? 'Spin Again 🎲' : 'Spin Wheel Now',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7A58FF),
                disabledBackgroundColor: Colors.white10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                shadowColor: const Color(0xFF7A58FF).withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter for rendering high-performance gradient wheel slices directly on GPU canvas
class _SpinWheelPainter extends CustomPainter {
  final List<IcebreakerQuestion> questions;

  _SpinWheelPainter({required this.questions});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final sliceAngle = (2 * math.pi) / questions.length;

    final paint = Paint()..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      final startAngle = i * sliceAngle;

      // Draw Slice with Shader Gradient
      final rect = Rect.fromCircle(center: center, radius: radius);
      paint.shader = SweepGradient(
        center: Alignment.center,
        startAngle: startAngle,
        endAngle: startAngle + sliceAngle,
        colors: [question.primaryColor, question.secondaryColor],
      ).createShader(rect);

      canvas.drawArc(rect, startAngle, sliceAngle, true, paint);
      canvas.drawArc(rect, startAngle, sliceAngle, true, borderPaint);

      // Draw Category Icon & Label on Slice
      _drawSliceContent(canvas, center, radius, startAngle, sliceAngle, question);
    }
  }

  void _drawSliceContent(
    Canvas canvas,
    Offset center,
    double radius,
    double startAngle,
    double sliceAngle,
    IcebreakerQuestion question,
  ) {
    final textAngle = startAngle + (sliceAngle / 2);
    final contentRadius = radius * 0.65;

    final x = center.dx + contentRadius * math.cos(textAngle);
    final y = center.dy + contentRadius * math.sin(textAngle);

    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(textAngle + math.pi / 2);

    // Draw Short Category Name
    final textPainter = TextPainter(
      text: TextSpan(
        text: question.category,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.black54, blurRadius: 4),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(-textPainter.width / 2, -textPainter.height / 2),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// CustomPainter for rendering the top ticker arrow pointer
class _PointerTickerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.amber
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
