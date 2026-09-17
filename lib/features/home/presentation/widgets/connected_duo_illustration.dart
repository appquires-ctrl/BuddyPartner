import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:buddypartner/core/widgets/app_avatar.dart';
import 'package:buddypartner/core/constants/avatar_catalog.dart';

/// Connected duo visual showing two tilted polaroid avatars
/// connected by a glowing heart badge for the Let's Connect hero banner.
class ConnectedDuoIllustration extends StatelessWidget {
  const ConnectedDuoIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Left tilted polaroid avatar (Male)
          // Positioned(
          //   left: 2,
          //   top: 14,
          //   child: Transform.rotate(
          //     angle: -math.pi / 15, // -12 degrees
          //     child: _buildPolaroidCard(
          //       child: const AppAvatar(
          //         gender: 'Male',
          //         avatarSeed: AvatarCatalog.defaultMaleSeed,
          //         radius: 17,
          //       ),
          //     ),
          //   ),
          // ),

          // Right tilted polaroid avatar (Female)
          // Positioned(
          //   right: 2,
          //   top: 8,
          //   child: Transform.rotate(
          //     angle: math.pi / 13, // +14 degrees
          //     child: _buildPolaroidCard(
          //       child: const AppAvatar(
          //         gender: 'Female',
          //         avatarSeed: AvatarCatalog.defaultFemaleSeed,
          //         radius: 17,
          //       ),
          //     ),
          //   ),
          // ),

          // Center glowing heart connector badge
          // Positioned(
          //   bottom: 12,
          //   child: Container(
          //     width: 28,
          //     height: 28,
          //     decoration: BoxDecoration(
          //       gradient: const LinearGradient(
          //         colors: [Color(0xFFF43F5E), Color(0xFFEC4899)],
          //         begin: Alignment.topLeft,
          //         end: Alignment.bottomRight,
          //       ),
          //       shape: BoxShape.circle,
          //       border: Border.all(
          //         color: Colors.white,
          //         width: 2.0,
          //       ),
          //       boxShadow: [
          //         BoxShadow(
          //           color: const Color(0xFFF43F5E).withValues(alpha: 0.6),
          //           blurRadius: 10,
          //           spreadRadius: 2,
          //           offset: const Offset(0, 2),
          //         ),
          //       ],
          //     ),
          //     child: const Center(
          //       child: Icon(
          //         Icons.favorite_rounded,
          //         color: Colors.white,
          //         size: 14,
          //       ),
          //     ),
          //   ),
          // ),

          // Subtle decorative floating sparkle
          // Positioned(
          //   top: 0,
          //   right: 0,
          //   child: Icon(
          //     Icons.auto_awesome,
          //     color: Colors.white.withValues(alpha: 0.85),
          //     size: 13,
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildPolaroidCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(4.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: child,
      ),
    );
  }
}
