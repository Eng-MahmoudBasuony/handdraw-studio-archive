import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';

/// Theme-aware vector colors for a branded path marker.
@immutable
class BrandedPathMarkerColors {
  const BrandedPathMarkerColors({
    required this.glow,
    required this.ring,
    required this.core,
    required this.label,
  });

  factory BrandedPathMarkerColors.fromStudio(StudioThemeColors colors) =>
      BrandedPathMarkerColors(
        glow: colors.pathMarkerGlow,
        ring: colors.pathMarkerRing,
        core: colors.pathMarkerCore,
        label: colors.pathMarkerText,
      );

  final Color glow;
  final Color ring;
  final Color core;
  final Color label;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BrandedPathMarkerColors &&
          other.glow == glow &&
          other.ring == ring &&
          other.core == core &&
          other.label == label;

  @override
  int get hashCode => Object.hash(glow, ring, core, label);
}

/// Widget counterpart of [BrandedPathMarkerPainter] for lists and inspectors.
class BrandedPathMarker extends StatelessWidget {
  const BrandedPathMarker({
    super.key,
    required this.number,
    this.size = 34,
    this.semanticLabel,
  });

  final int number;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final marker = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _BrandedPathMarkerCustomPainter(
          number: number,
          colors: BrandedPathMarkerColors.fromStudio(context.studioColors),
          scale: size / 38,
        ),
      ),
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: marker);
    return Semantics(label: label, image: true, child: marker);
  }
}

class _BrandedPathMarkerCustomPainter extends CustomPainter {
  const _BrandedPathMarkerCustomPainter({
    required this.number,
    required this.colors,
    required this.scale,
  });

  final int number;
  final BrandedPathMarkerColors colors;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    BrandedPathMarkerPainter.drawNumbered(
      canvas: canvas,
      position: Offset.zero,
      number: number,
      colors: colors,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BrandedPathMarkerCustomPainter oldDelegate) =>
      oldDelegate.number != number ||
      oldDelegate.colors != colors ||
      oldDelegate.scale != scale;
}

/// Draws the motion-path node used throughout the editor canvas.
///
/// The marker deliberately uses canvas vectors instead of raster or repeatedly
/// decoding an SVG. This preserves Retina sharpness while staying inexpensive
/// when an automatic section contains hundreds of path starts.
abstract final class BrandedPathMarkerPainter {
  static const _fontFamily = 'PlaypenSansArabic';

  static double radiusForLabel(String label) {
    if (label.length <= 2) return 11.5;
    return 11.5 + (label.length - 2) * 1.6;
  }

  static void drawNumbered({
    required Canvas canvas,
    required Offset position,
    required int number,
    required BrandedPathMarkerColors colors,
  }) {
    final label = '$number';
    final radius = radiusForLabel(label);
    _drawBody(
      canvas: canvas,
      position: position,
      radius: radius,
      colors: colors,
      emphasized: true,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: colors.label,
          fontFamily: _fontFamily,
          fontSize: label.length <= 2 ? 10.5 : 9,
          fontWeight: FontWeight.w800,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    textPainter.paint(
      canvas,
      position - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  static void drawDot({
    required Canvas canvas,
    required Offset position,
    required BrandedPathMarkerColors colors,
  }) {
    _drawBody(
      canvas: canvas,
      position: position,
      radius: 4.2,
      colors: colors,
      emphasized: false,
    );
  }

  static void _drawBody({
    required Canvas canvas,
    required Offset position,
    required double radius,
    required BrandedPathMarkerColors colors,
    required bool emphasized,
  }) {
    final glowRadius = radius + (emphasized ? 8 : 3.5);
    final glowBounds = Rect.fromCircle(center: position, radius: glowRadius);
    canvas.drawCircle(
      position,
      glowRadius,
      Paint()
        ..isAntiAlias = true
        ..shader = RadialGradient(
          colors: [
            colors.glow.withValues(alpha: emphasized ? 0.48 : 0.30),
            colors.glow.withValues(alpha: 0),
          ],
          stops: const [0.12, 1],
        ).createShader(glowBounds),
    );

    final markerBounds = Rect.fromCircle(center: position, radius: radius);
    canvas.drawCircle(
      position,
      radius,
      Paint()
        ..isAntiAlias = true
        ..shader = RadialGradient(
          center: const Alignment(-0.28, -0.32),
          radius: 0.92,
          colors: [
            colors.core.withValues(alpha: 0.98),
            colors.ring,
            colors.glow,
          ],
          stops: const [0, 0.68, 1],
        ).createShader(markerBounds),
    );
    canvas.drawCircle(
      position,
      radius - 0.55,
      Paint()
        ..isAntiAlias = true
        ..color = colors.core.withValues(alpha: emphasized ? 0.18 : 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = emphasized ? 1.2 : 0.8,
    );
    canvas.drawCircle(
      position,
      radius,
      Paint()
        ..isAntiAlias = true
        ..color = colors.ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = emphasized ? 1.45 : 1,
    );

    if (!emphasized) return;
    canvas.drawArc(
      Rect.fromCircle(center: position, radius: radius - 2.2),
      math.pi * 1.08,
      math.pi * 0.42,
      false,
      Paint()
        ..isAntiAlias = true
        ..color = colors.core.withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.15,
    );
  }
}
