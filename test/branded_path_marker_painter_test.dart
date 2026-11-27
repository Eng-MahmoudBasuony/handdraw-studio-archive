import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/branded_path_marker_painter.dart';

void main() {
  test('numbered path marker scales to keep long labels readable', () {
    expect(
      BrandedPathMarkerPainter.radiusForLabel('120'),
      greaterThan(BrandedPathMarkerPainter.radiusForLabel('12')),
    );
  });

  test('numbered path marker renders an opaque core and soft halo', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    BrandedPathMarkerPainter.drawNumbered(
      canvas: canvas,
      position: const Offset(40, 40),
      number: 12,
      colors: BrandedPathMarkerColors(
        glow: AppPalette.dark.pathMarkerGlow,
        ring: AppPalette.dark.pathMarkerRing,
        core: AppPalette.dark.pathMarkerCore,
        label: AppPalette.dark.pathMarkerText,
      ),
    );

    final image = await recorder.endRecording().toImage(80, 80);
    addTearDown(image.dispose);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);

    int alphaAt(int x, int y) => bytes!.getUint8((y * 80 + x) * 4 + 3);
    expect(alphaAt(40, 40), 255, reason: 'the numbered core stays crisp');
    expect(
      alphaAt(25, 40),
      greaterThan(0),
      reason: 'the brand halo is visible',
    );
    expect(alphaAt(0, 0), 0, reason: 'the halo remains locally bounded');
  });
}
