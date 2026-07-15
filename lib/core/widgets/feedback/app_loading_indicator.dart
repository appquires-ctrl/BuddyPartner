import 'package:flutter/material.dart';
import '../../extensions/context_extensions.dart';

/// AppLoadingIndicator provides a themed spinner loader.
class AppLoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;

  const AppLoadingIndicator({
    super.key,
    this.size = 36.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(color ?? colors.primary),
          strokeWidth: 3,
        ),
      ),
    );
  }
}
