import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:buddypartner/features/auth/application/auth_controller.dart';
import 'package:buddypartner/features/call/application/instant_connect_controller.dart';
import 'package:buddypartner/features/call/domain/models/instant_connect_models.dart';

class ScratchCardDialog extends ConsumerStatefulWidget {
  final ScratchCardModel card;

  const ScratchCardDialog({super.key, required this.card});

  static Future<void> show(BuildContext context, ScratchCardModel card) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (ctx) => ScratchCardDialog(card: card),
    );
  }

  @override
  ConsumerState<ScratchCardDialog> createState() => _ScratchCardDialogState();
}

class _ScratchCardDialogState extends ConsumerState<ScratchCardDialog>
    with TickerProviderStateMixin {
  // Scratching state
  final List<Offset> _scratchPoints = [];
  final Set<int> _scratchedGridCells = {};
  static const int _gridCols = 12;
  static const int _gridRows = 8;
  static const int _totalGridCells = _gridCols * _gridRows;

  bool _isRevealed = false;
  bool _isClaiming = false;
  bool _isClaimed = false;
  int? _claimedCoins;

  // Animations
  late AnimationController _burstController;
  late AnimationController _sunburstController;
  late AnimationController _cardPopController;
  late AnimationController _shimmerController;
  late List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();

    // Setup animation controllers
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    _sunburstController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _cardPopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _initParticles();

    if (widget.card.isScratched) {
      _isRevealed = true;
      _isClaimed = true;
      _claimedCoins = widget.card.coinReward;
      _cardPopController.value = 1.0;
    }
  }

  void _initParticles() {
    final rand = math.Random();
    const colors = [
      Color(0xFFFFD700), // Gold
      Color(0xFFFFB300), // Amber
      Color(0xFFFF4081), // Pink
      Color(0xFF7C4DFF), // Purple
      Color(0xFF00E676), // Green
      Color(0xFF00E5FF), // Cyan
      Color(0xFFFF6E40), // Orange
      Color(0xFFFFFFFF), // White star
    ];

    _particles = List.generate(55, (index) {
      final angle = rand.nextDouble() * math.pi * 2;
      final speed = 80 + rand.nextDouble() * 220;
      final particleType = _ParticleType.values[rand.nextInt(_ParticleType.values.length)];
      return _ConfettiParticle(
        color: colors[rand.nextInt(colors.length)],
        angle: angle,
        speed: speed,
        size: 5 + rand.nextDouble() * 9,
        rotationSpeed: (rand.nextDouble() - 0.5) * 8,
        type: particleType,
        gravity: 120 + rand.nextDouble() * 100,
      );
    });
  }

  @override
  void dispose() {
    _burstController.dispose();
    _sunburstController.dispose();
    _cardPopController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details, Size cardSize) {
    if (_isRevealed) return;
    _addScratchPoint(details.localPosition, cardSize);
  }

  void _onPanUpdate(DragUpdateDetails details, Size cardSize) {
    if (_isRevealed) return;
    _addScratchPoint(details.localPosition, cardSize);
  }

  void _addScratchPoint(Offset pos, Size cardSize) {
    if (pos.dx < 0 || pos.dx > cardSize.width || pos.dy < 0 || pos.dy > cardSize.height) {
      return;
    }

    _scratchPoints.add(pos);

    // Calculate grid cell
    final cellX = (pos.dx / (cardSize.width / _gridCols)).floor().clamp(0, _gridCols - 1);
    final cellY = (pos.dy / (cardSize.height / _gridRows)).floor().clamp(0, _gridRows - 1);
    _scratchedGridCells.add(cellY * _gridCols + cellX);

    // Provide light haptic on active scratching
    if (_scratchPoints.length % 6 == 0) {
      HapticFeedback.selectionClick();
    }

    setState(() {});

    // If 32% or more of card is scratched, reveal automatically with explosion
    final progress = _scratchedGridCells.length / _totalGridCells;
    if (progress >= 0.32) {
      _triggerCelebrationReveal();
    }
  }

  Future<void> _triggerCelebrationReveal() async {
    if (_isRevealed) return;

    setState(() {
      _isRevealed = true;
    });

    // Intense celebratory haptic sequence
    HapticFeedback.heavyImpact();
    Future.delayed(const Duration(milliseconds: 120), () => HapticFeedback.mediumImpact());
    Future.delayed(const Duration(milliseconds: 240), () => HapticFeedback.lightImpact());

    // Run burst animations
    _cardPopController.forward(from: 0.0);
    _burstController.forward(from: 0.0);

    if (!_isClaimed && !widget.card.isScratched) {
      _handleClaim();
    }
  }

  Future<void> _handleClaim() async {
    if (_isClaiming || _isClaimed) return;
    setState(() => _isClaiming = true);

    final reward = await ref
        .read(instantConnectControllerProvider.notifier)
        .claimScratchCard(widget.card.id);

    if (mounted) {
      setState(() {
        _isClaiming = false;
        _isClaimed = true;
        _claimedCoins = reward ?? widget.card.coinReward;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // STRICT FEMALE ONLY PROTECTION:
    // If not female, do not render scratch card (prevent male from knowing female earning cuts)
    final currentUser = ref.watch(authStateProvider).value;
    if (currentUser != null && !currentUser.isFemale) {
      return const SizedBox.shrink();
    }

    final reward = _claimedCoins ?? widget.card.coinReward;
    const cardSize = Size(250, 160);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Background Sunburst Glow on Reveal
          if (_isRevealed)
            Positioned(
              top: -30,
              child: AnimatedBuilder(
                animation: _sunburstController,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _sunburstController.value * math.pi * 2,
                    child: CustomPaint(
                      size: const Size(360, 360),
                      painter: _SunburstPainter(),
                    ),
                  );
                },
              ),
            ),

          // Main Card Dialog Surface
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 340),
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1E1535),
                  Color(0xFF130E24),
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: _isRevealed
                    ? const Color(0xFFFFD54F).withValues(alpha: 0.6)
                    : const Color(0xFF9E8CF8).withValues(alpha: 0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: (_isRevealed ? const Color(0xFFFFB300) : const Color(0xFF7C6AEF))
                      .withValues(alpha: 0.35),
                  blurRadius: 30,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Tag Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFFD946EF)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD946EF).withValues(alpha: 0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.card_giftcard_rounded, color: Colors.white, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        _isRevealed ? '🎉 REWARD UNLOCKED' : '🎁 10-MIN CALL REWARD',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Title
                Text(
                  _isRevealed ? 'Woohoo! You Won!' : 'Scratch Your Card! ✨',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _isRevealed
                      ? 'Coins directly credited to your earnings wallet'
                      : 'Rub your finger across the gold foil to reveal coins',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),

                // ── Interactive Scratch Card Box ─────────────────────────────
                AnimatedBuilder(
                  animation: _cardPopController,
                  builder: (context, child) {
                    final scale = _isRevealed
                        ? 1.0 + math.sin(_cardPopController.value * math.pi) * 0.08
                        : 1.0;
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: Container(
                    width: cardSize.width,
                    height: cardSize.height,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        children: [
                          // 1. Prize Layer (Revealed Content)
                          Container(
                            width: cardSize.width,
                            height: cardSize.height,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFFF9C4),
                                  Color(0xFFFFE082),
                                  Color(0xFFFFD54F),
                                ],
                              ),
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Subtle coin background pattern
                                Positioned(
                                  top: -15,
                                  right: -15,
                                  child: Icon(
                                    Icons.monetization_on_rounded,
                                    size: 90,
                                    color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                                  ),
                                ),
                                Positioned(
                                  bottom: -20,
                                  left: -15,
                                  child: Icon(
                                    Icons.stars_rounded,
                                    size: 80,
                                    color: const Color(0xFFFFB300).withValues(alpha: 0.15),
                                  ),
                                ),

                                // Prize Details
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFFFFD54F), Color(0xFFFF8F00)],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFF8F00).withValues(alpha: 0.4),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: const Icon(
                                        Icons.monetization_on_rounded,
                                        color: Colors.white,
                                        size: 34,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '+$reward COINS',
                                      style: const TextStyle(
                                        color: Color(0xFFB74700),
                                        fontSize: 24,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _isClaimed ? '✓ Added to Wallet (₹$reward)' : '≈ ₹$reward Real Cash',
                                        style: const TextStyle(
                                          color: Color(0xFF2E7D32),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // 2. Interactive Scratchable Foil Mask Layer
                          if (!_isRevealed)
                            GestureDetector(
                              onPanStart: (details) => _onPanStart(details, cardSize),
                              onPanUpdate: (details) => _onPanUpdate(details, cardSize),
                              onTap: _triggerCelebrationReveal,
                              child: AnimatedBuilder(
                                animation: _shimmerController,
                                builder: (context, child) {
                                  return CustomPaint(
                                    size: cardSize,
                                    painter: _ScratchFoilPainter(
                                      scratchPoints: _scratchPoints,
                                      shimmerValue: _shimmerController.value,
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

                const SizedBox(height: 20),

                // Bottom Action Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: !_isRevealed
                        ? _triggerCelebrationReveal
                        : () => Navigator.of(context, rootNavigator: true).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isRevealed ? const Color(0xFF10B981) : const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      elevation: 6,
                      shadowColor: (_isRevealed ? const Color(0xFF10B981) : const Color(0xFF8B5CF6))
                          .withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isClaiming
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _isRevealed ? Icons.check_circle_rounded : Icons.auto_awesome_rounded,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isRevealed
                                    ? 'Done (Claimed to Wallet)'
                                    : 'Tap to Reveal Instantly',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),

          // ── Celebratory Confetti & Coin Burst Popper ────────────────────────
          if (_isRevealed)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _burstController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _ConfettiBurstPainter(
                        progress: _burstController.value,
                        particles: _particles,
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Particle System & Painters ───────────────────────────────────────────────

enum _ParticleType { ribbon, circle, star, sparkle }

class _ConfettiParticle {
  final Color color;
  final double angle;
  final double speed;
  final double size;
  final double rotationSpeed;
  final _ParticleType type;
  final double gravity;

  _ConfettiParticle({
    required this.color,
    required this.angle,
    required this.speed,
    required this.size,
    required this.rotationSpeed,
    required this.type,
    required this.gravity,
  });
}

class _ConfettiBurstPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiParticle> particles;

  _ConfettiBurstPainter({
    required this.progress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2 - 10);
    final paint = Paint()..style = PaintingStyle.fill;

    // Fade out towards end
    final alpha = (1.0 - progress).clamp(0.0, 1.0);

    for (final p in particles) {
      final t = progress;
      // Physics: outward burst with velocity decay + gravity
      final dist = p.speed * t * (1.0 - t * 0.3);
      final dx = center.dx + math.cos(p.angle) * dist;
      final dy = center.dy + math.sin(p.angle) * dist + (p.gravity * t * t);

      final rotation = p.rotationSpeed * t * math.pi * 2;
      paint.color = p.color.withValues(alpha: alpha);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rotation);

      switch (p.type) {
        case _ParticleType.ribbon:
          final rect = Rect.fromCenter(center: Offset.zero, width: p.size * 1.5, height: p.size * 0.6);
          canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(2)), paint);
          break;

        case _ParticleType.circle:
          canvas.drawCircle(Offset.zero, p.size / 2, paint);
          break;

        case _ParticleType.star:
          _drawStar(canvas, paint, p.size);
          break;

        case _ParticleType.sparkle:
          _drawSparkle(canvas, paint, p.size * 1.3);
          break;
      }

      canvas.restore();
    }
  }

  void _drawStar(Canvas canvas, Paint paint, double size) {
    final path = Path();
    const points = 5;
    final rOuter = size / 2;
    final rInner = rOuter / 2;
    for (int i = 0; i < points * 2; i++) {
      final r = i.isEven ? rOuter : rInner;
      final a = i * math.pi / points - math.pi / 2;
      final x = r * math.cos(a);
      final y = r * math.sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawSparkle(Canvas canvas, Paint paint, double size) {
    final path = Path();
    final half = size / 2;
    path.moveTo(0, -half);
    path.quadraticBezierTo(0, 0, half, 0);
    path.quadraticBezierTo(0, 0, 0, half);
    path.quadraticBezierTo(0, 0, -half, 0);
    path.quadraticBezierTo(0, 0, 0, -half);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ConfettiBurstPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _SunburstPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const numRays = 16;
    final angleStep = (math.pi * 2) / numRays;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFD54F).withValues(alpha: 0.28),
          const Color(0xFFFFB300).withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius));

    for (int i = 0; i < numRays; i++) {
      if (i.isEven) {
        final startAngle = i * angleStep;
        final sweepAngle = angleStep * 0.65;
        final path = Path()
          ..moveTo(center.dx, center.dy)
          ..arcTo(
            Rect.fromCircle(center: center, radius: maxRadius),
            startAngle,
            sweepAngle,
            false,
          )
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SunburstPainter oldDelegate) => false;
}

class _ScratchFoilPainter extends CustomPainter {
  final List<Offset> scratchPoints;
  final double shimmerValue;

  _ScratchFoilPainter({
    required this.scratchPoints,
    required this.shimmerValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // 1. Draw Shimmering Holographic Foil Surface
    final foilRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final shimmerShift = shimmerValue * size.width * 2 - size.width;

    final foilPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [
          Color(0xFF3B2D71),
          Color(0xFF6B46C1),
          Color(0xFF8B5CF6),
          Color(0xFF4C1D95),
        ],
      ).createShader(foilRect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(foilRect, const Radius.circular(22)),
      foilPaint,
    );

    // Dynamic metallic shine beam
    final shinePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.25),
          Colors.white.withValues(alpha: 0.45),
          Colors.transparent,
        ],
        stops: const [0.0, 0.45, 0.55, 1.0],
      ).createShader(Rect.fromLTWH(shimmerShift, 0, size.width * 0.8, size.height));

    canvas.drawRRect(
      RRect.fromRectAndRadius(foilRect, const Radius.circular(22)),
      shinePaint,
    );

    // Foil Icon & Instructions Text
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '✨ SCRATCH HERE ✨',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 15,
          letterSpacing: 1.5,
          shadows: [
            Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(
      canvas,
      Offset((size.width - textPainter.width) / 2, size.height / 2 - 8),
    );

    final subTextPainter = TextPainter(
      text: TextSpan(
        text: 'Rub to reveal instant cash',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.85),
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    subTextPainter.paint(
      canvas,
      Offset((size.width - subTextPainter.width) / 2, size.height / 2 + 14),
    );

    // 2. Erase Scratched Paths using BlendMode.clear
    final erasePaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 38.0;

    for (int i = 0; i < scratchPoints.length; i++) {
      final p = scratchPoints[i];
      if (i == 0) {
        canvas.drawCircle(p, 19.0, erasePaint..style = PaintingStyle.fill);
      } else {
        final prev = scratchPoints[i - 1];
        canvas.drawLine(prev, p, erasePaint..style = PaintingStyle.stroke);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScratchFoilPainter oldDelegate) {
    return oldDelegate.scratchPoints.length != scratchPoints.length ||
        oldDelegate.shimmerValue != shimmerValue;
  }
}
