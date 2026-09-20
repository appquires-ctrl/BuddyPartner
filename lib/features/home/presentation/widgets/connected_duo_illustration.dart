import 'package:flutter/material.dart';

/// 3D couple illustration for the "Let's Connect" hero banner.
class ConnectedDuoIllustration extends StatelessWidget {
  final double? width;
  final double? height;
  final BoxFit fit;

  const ConnectedDuoIllustration({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/lets_connect_illustration.png',
      width: width,
      height: height,
      fit: fit,
      alignment: Alignment.bottomRight,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }
}
