import 'package:flutter/material.dart';
import 'package:buddypartner/core/extensions/context_extensions.dart';

/// AppBottomSheet provides a standardized bottom sheet wrapper and container
/// that automatically prevents navigation bar overlap (e.g. Samsung 3-button nav bar,
/// gesture navigation pill, iOS home indicator) across all Android and iOS devices.
class AppBottomSheet {
  AppBottomSheet._();

  /// Show a standardized modal bottom sheet that is immune to system navigation
  /// bar overlaps and keyboard clipping.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool useRootNavigator = true,
    Color backgroundColor = Colors.transparent,
    ShapeBorder? shape,
    Clip clipBehavior = Clip.antiAlias,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isScrollControlled: isScrollControlled,
      backgroundColor: backgroundColor,
      shape: shape,
      clipBehavior: clipBehavior,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      builder: builder,
    );
  }
}

/// A standardized bottom sheet container that guarantees:
/// 1. The surface background extends behind the system navigation bar for a seamless edge-to-edge look.
/// 2. All content and CTA buttons are automatically padded above the system navigation bar (Samsung 3-button nav bar, gesture bar, etc.) via [SafeArea].
/// 3. Active keyboard insets are handled cleanly.
/// 4. Optional scrollable wrapper prevents RenderFlex overflows on smaller screens or high accessibility font scales.
class AppBottomSheetContainer extends StatelessWidget {
  final Widget child;
  final bool showDragHandle;
  final bool isScrollable;
  final ScrollPhysics? scrollPhysics;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;
  final double? maxHeight;

  const AppBottomSheetContainer({
    super.key,
    required this.child,
    this.showDragHandle = true,
    this.isScrollable = false,
    this.scrollPhysics,
    this.padding,
    this.backgroundColor,
    this.borderRadius,
    this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final media = MediaQuery.of(context);
    final effectiveBorderRadius = borderRadius ?? const BorderRadius.vertical(top: Radius.circular(28));
    final effectiveBgColor = backgroundColor ?? colors.surface;
    final keyboardBottom = media.viewInsets.bottom;

    Widget content = child;

    if (showDragHandle) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 14, bottom: 16),
              decoration: BoxDecoration(
                color: colors.border.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(
            fit: FlexFit.loose,
            child: child,
          ),
        ],
      );
    }

    if (isScrollable) {
      content = SingleChildScrollView(
        physics: scrollPhysics ?? const BouncingScrollPhysics(),
        padding: padding ??
            EdgeInsets.only(
              left: 20,
              right: 20,
              bottom: keyboardBottom + 16,
            ),
        child: content,
      );
    } else if (padding != null || keyboardBottom > 0) {
      content = Padding(
        padding: (padding ?? const EdgeInsets.symmetric(horizontal: 20)).add(
          EdgeInsets.only(bottom: keyboardBottom + 16),
        ),
        child: content,
      );
    }

    Widget sheet = Container(
      decoration: BoxDecoration(
        color: effectiveBgColor,
        borderRadius: effectiveBorderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        bottom: true,
        child: content,
      ),
    );

    if (maxHeight != null) {
      sheet = ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight!),
        child: sheet,
      );
    }

    return sheet;
  }
}
