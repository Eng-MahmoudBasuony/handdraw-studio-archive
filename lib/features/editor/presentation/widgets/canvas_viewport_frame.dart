import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';

/// Owns the complete visual boundary of an editor canvas.
///
/// Painters inside this frame draw content only. Keeping clipping, the border,
/// and elevation here makes the frame reusable by future canvas surfaces. The
/// editor defaults to square corners so its visible boundary matches the exact
/// rectangular Preview and exported frame.
class CanvasViewportFrame extends StatelessWidget {
  const CanvasViewportFrame({
    super.key,
    required this.child,
    this.radius = 0,
    this.borderWidth = 1,
    this.showShadow = true,
  });

  final Widget child;
  final double radius;
  final double borderWidth;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    assert(radius >= 0);
    final colors = context.studioColors;
    final outerRadius = BorderRadius.circular(radius);
    final innerRadius = BorderRadius.circular(
      (radius - borderWidth).clamp(0, double.infinity),
    );

    return RepaintBoundary(
      key: const ValueKey('canvas-viewport-frame'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: outerRadius,
          boxShadow: showShadow
              ? [
                  BoxShadow(
                    color: colors.scrim.withValues(alpha: 0.56),
                    blurRadius: 30,
                    offset: const Offset(0, 14),
                  ),
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.06),
                    blurRadius: 18,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: outerRadius,
          clipBehavior: Clip.antiAlias,
          child: ColoredBox(
            color: colors.border.withValues(alpha: 0.82),
            child: Padding(
              padding: EdgeInsets.all(borderWidth),
              child: ClipRRect(
                borderRadius: innerRadius,
                clipBehavior: Clip.antiAlias,
                child: ColoredBox(color: colors.appBackground, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
