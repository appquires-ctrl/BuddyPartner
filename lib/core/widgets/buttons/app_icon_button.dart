import 'package:flutter/material.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';
import 'package:buddypartner/core/utils/app_throttler.dart';

/// AppIconButton provides a themed icon button wrapper.
/// Can optionally render with a solid circular background.
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final Color? backgroundColor;
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.color,
    this.backgroundColor,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final buttonColor = color ?? colors.primary;
    final throttledOnPressed = AppThrottler.wrap(onPressed)!;

    if (backgroundColor != null) {
      return Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: throttledOnPressed,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              icon,
              color: buttonColor,
              size: size,
            ),
          ),
        ),
      );
    }

    return IconButton(
      icon: Icon(icon),
      color: buttonColor,
      iconSize: size,
      onPressed: throttledOnPressed,
    );
  }
}
