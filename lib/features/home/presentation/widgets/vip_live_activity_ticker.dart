import 'dart:async';
import 'package:flutter/material.dart';
import 'package:buddypartner/core/widgets/app_avatar.dart';
import 'package:buddypartner/features/home/presentation/widgets/instant_connect_sheet.dart';

/// Pulsing green live indicator dot with expanding radar glow
class PulsingLiveDot extends StatefulWidget {
  final double size;
  final Color color;

  const PulsingLiveDot({
    super.key,
    this.size = 8.0,
    this.color = const Color(0xFF10B981), // Emerald green
  });

  @override
  State<PulsingLiveDot> createState() => _PulsingLiveDotState();
}

class _PulsingLiveDotState extends State<PulsingLiveDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 2.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 2.2,
      height: widget.size * 2.2,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Radar pulse ring
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: _opacityAnimation.value),
                  ),
                ),
              );
            },
          ),
          // Inner solid dot
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.6),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini overlapping avatar stack with online count badge
class VipLiveAvatarStack extends StatelessWidget {
  final int count;
  final double radius;

  const VipLiveAvatarStack({
    super.key,
    required this.count,
    this.radius = 11,
  });

  static const List<String> _sampleSeeds = ['female_1', 'female_11', 'female_12'];

  @override
  Widget build(BuildContext context) {
    final overlap = radius * 1.35;
    final itemDiameter = (radius * 2) + 3.0; // matches avatar + 1.5px border on both sides

    return SizedBox(
      height: itemDiameter,
      width: (_sampleSeeds.length * overlap) + itemDiameter,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerLeft,
        children: [
          for (int i = 0; i < _sampleSeeds.length; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                width: itemDiameter,
                height: itemDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: AppAvatar(
                  avatarSeed: _sampleSeeds[i],
                  gender: 'female',
                  radius: radius,
                ),
              ),
            ),
          Positioned(
            left: _sampleSeeds.length * overlap,
            child: Container(
              width: itemDiameter,
              height: itemDiameter,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 5,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '+$count',
                    style: TextStyle(
                      color: const Color(0xFFEA580C), // Matching VIP orange theme
                      fontSize: radius * 0.95,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Smoothly rotating live activity ticker for VIP Call features
class VipLiveActivityTicker extends StatefulWidget {
  final bool isCompact;
  final TextStyle? textStyle;
  final List<String>? customMessages;

  const VipLiveActivityTicker({
    super.key,
    this.isCompact = true,
    this.textStyle,
    this.customMessages,
  });

  @override
  State<VipLiveActivityTicker> createState() => _VipLiveActivityTickerState();
}

class _VipLiveActivityTickerState extends State<VipLiveActivityTicker> {
  int _currentIndex = 0;
  Timer? _rotationTimer;

  // Realistic dynamic counts based on time of day
  int get _girlsCount {
    final hour = DateTime.now().hour;
    final base = (hour >= 18 && hour <= 23)
        ? 32
        : (hour >= 12 && hour < 18 ? 24 : 20);
    return base + (hour % 5);
  }

  int get _vipAvailableCount => _girlsCount + 5;

  List<String> get _messages =>
      widget.customMessages ??
      (widget.isCompact
          ? [
              '$_girlsCount+ girls active now',
              'Connect in < 5 seconds',
              'Switch to Video ready',
            ]
          : [
              '$_girlsCount+ girls are active right now',
              '$_vipAvailableCount+ users are available for a VIP call',
              'People are waiting to connect',
              'Switch to Video supported in-call',
              'Avg. connection: under 5 seconds',
            ]);

  @override
  void initState() {
    super.initState();
    _rotationTimer = Timer.periodic(const Duration(milliseconds: 3400), (_) {
      if (mounted) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % _messages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.95),
      fontSize: widget.isCompact ? 11.5 : 13.0,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    );

    final currentMessage = _messages[_currentIndex % _messages.length];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const PulsingLiveDot(size: 7.0),
        const SizedBox(width: 6),
        Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            transitionBuilder: (child, animation) {
              final inAnimation = Tween<Offset>(
                begin: const Offset(0.0, 0.45),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
              return SlideTransition(
                position: inAnimation,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: FittedBox(
              key: ValueKey<String>(currentMessage),
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                currentMessage,
                style: widget.textStyle ?? defaultStyle,
                maxLines: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Standalone High-Demand Live Indicator Banner for Sheets and Dialogs
class VipLiveDemandBanner extends StatelessWidget {
  final bool isDark;
  final VoidCallback? onTap;

  const VipLiveDemandBanner({
    super.key,
    this.isDark = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final activeUsers = (hour >= 18 && hour <= 23) ? 36 : (hour >= 12 ? 28 : 22);

    final bannerContent = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF10B981).withValues(alpha: 0.12)
            : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? const Color(0xFF10B981).withValues(alpha: 0.35)
              : const Color(0xFFA7F3D0),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const PulsingLiveDot(size: 8.5),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      '$activeUsers+ Users Available Right Now',
                      style: TextStyle(
                        color: isDark ? const Color(0xFF10B981) : const Color(0xFF047857),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'HIGH DEMAND',
                        style: TextStyle(
                          color: isDark ? const Color(0xFF10B981) : const Color(0xFF065F46),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                VipLiveActivityTicker(
                  isCompact: true,
                  textStyle: TextStyle(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.75)
                        : const Color(0xFF374151),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white70 : const Color(0xFF047857),
              size: 20,
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: bannerContent,
      );
    }

    return bannerContent;
  }
}

/// Standalone Interactive VIP Call Promotion Card for Matchmaking & Queue Views
class VipLiveActivityCard extends StatelessWidget {
  final VoidCallback? onTap;
  final String title;
  final String subtitle;

  const VipLiveActivityCard({
    super.key,
    this.onTap,
    this.title = 'VIP INSTANT CONNECT ⚡',
    this.subtitle = 'Skip the line • Connect immediately',
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => InstantConnectSheet.show(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFFEA580C), Color(0xFFC2410C)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEA580C).withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            // Glowing Bolt Icon Container
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const VipLiveActivityTicker(
                    isCompact: true,
                    textStyle: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const VipLiveAvatarStack(count: 25, radius: 10),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 13,
            ),
          ],
        ),
      ),
    );
  }
}
