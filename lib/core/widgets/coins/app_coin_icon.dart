import 'package:flutter/material.dart';

/// AppCoinIcon is the universal, standardized 3D-styled Gold Coin icon
/// used consistently across the entire BuddyPartner application.
class AppCoinIcon extends StatelessWidget {
  final double size;
  final bool withGlow;

  const AppCoinIcon({super.key, this.size = 22.0, this.withGlow = true});

  @override
  Widget build(BuildContext context) {
    final innerIconSize = size * 0.58;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFE082), // Soft gold highlight
            Color(0xFFFFB300), // Rich amber gold
            Color(0xFFFF8F00), // Deep golden border tone
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: withGlow
            ? [
                BoxShadow(
                  color: const Color(0xFFFFB300).withValues(alpha: 0.4),
                  blurRadius: size * 0.35,
                  offset: Offset(0, size * 0.1),
                ),
              ]
            : null,
      ),
      child: Center(
        child: Container(
          width: size * 0.84,
          height: size * 0.84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFCA28), Color(0xFFFFA000)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: size * 0.04,
            ),
          ),
          child: Center(
            child: Icon(
              Icons.monetization_on_rounded,
              color: Colors.white,
              size: innerIconSize,
            ),
          ),
        ),
      ),
    );
  }
}
