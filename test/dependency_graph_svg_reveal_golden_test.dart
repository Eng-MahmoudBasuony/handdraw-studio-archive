import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'dependency graph filled nodes stay solid during native SVG reveal',
    () async {
      final asset = await const EditorFileService().loadImage(
        'test/fixtures/dependency-graph-diagram.svg',
      );
      addTearDown(asset.image.dispose);
      addTearDown(() => asset.revealBaseImage?.dispose());
      addTearDown(() => asset.svgRevealLayers?.strokes.dispose());
      addTearDown(() => asset.svgRevealLayers?.globalStrokes?.dispose());
      final base = asset.revealBaseImage!;
      final pixels = await base.toByteData(format: ImageByteFormat.rawRgba);
      expect(pixels, isNotNull);
      Color pixelAt(double x, double y) {
        final px = (x * base.width).floor().clamp(0, base.width - 1);
        final py = (y * base.height).floor().clamp(0, base.height - 1);
        final offset = (py * base.width + px) * 4;
        return Color.fromARGB(
          pixels!.getUint8(offset + 3),
          pixels.getUint8(offset),
          pixels.getUint8(offset + 1),
          pixels.getUint8(offset + 2),
        );
      }

      final nodeFill = pixelAt(400 / 900, 95 / 500);
      expect(pixelAt(450 / 900, 95 / 500), nodeFill);
      expect(pixelAt(500 / 900, 95 / 500), nodeFill);
      final strokeLayer = asset.svgRevealLayers!.strokes;
      final strokePixels = await strokeLayer.toByteData(
        format: ImageByteFormat.rawRgba,
      );
      expect(strokePixels, isNotNull);
      Color strokePixelAt(double x, double y) {
        final px = (x * strokeLayer.width).floor().clamp(
          0,
          strokeLayer.width - 1,
        );
        final py = (y * strokeLayer.height).floor().clamp(
          0,
          strokeLayer.height - 1,
        );
        final offset = (py * strokeLayer.width + px) * 4;
        return Color.fromARGB(
          strokePixels!.getUint8(offset + 3),
          strokePixels.getUint8(offset),
          strokePixels.getUint8(offset + 1),
          strokePixels.getUint8(offset + 2),
        );
      }

      // The line source must never contain neighboring card colors. This is
      // the pixel-level regression for the green/orange arrowhead artifacts.
      expect(strokePixelAt(450 / 900, 95 / 500).a, 0);
      expect(pixelAt(335 / 900, 160 / 500).a, 0);
      final textExclusions = asset.vectorPaths
          .where((path) => path.isText)
          .map(
            (path) => path.clipBounds
                .inflate(0.001)
                .intersect(const Rect.fromLTWH(0, 0, 1, 1)),
          )
          .toList(growable: false);
      final project = HandDrawProject(
        canvasWidth: 900,
        canvasHeight: 500,
        durationSeconds: 8,
        drawingDurationSeconds: 8,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        strokes: [
          for (var index = 0; index < asset.vectorPaths.length; index++)
            DrawingStroke(
              id: 'svg-$index',
              name: asset.vectorPaths[index].id,
              geometry: asset.vectorPaths[index].geometry,
              animationGeometry: asset.vectorPaths[index].animationGeometry,
              isFilledShape: asset.vectorPaths[index].isFilled,
              isTextShape: asset.vectorPaths[index].isText,
              fillColorValue: asset.vectorPaths[index].fillColorValue,
              revealStyle:
                  asset.vectorPaths[index].isFilled ||
                      asset.vectorPaths[index].isText
                  ? RevealMaskStyle.directionalWipe
                  : RevealMaskStyle.brush,
              clipBounds: asset.vectorPaths[index].clipBounds,
              exclusionBounds: asset.vectorPaths[index].isFilled
                  ? textExclusions
                  : const [],
              revealWidth:
                  asset.vectorPaths[index].recommendedRevealWidth * 500,
            ),
        ],
      );

      final frame = await const FrameRenderer().render(
        project: project,
        drawing: asset.image,
        drawingRevealBase: asset.revealBaseImage,
        svgRevealLayers: asset.svgRevealLayers,
        hand: null,
        progress: 0.38,
      );
      addTearDown(frame.dispose);
      await expectLater(
        frame,
        matchesGoldenFile('goldens/dependency_graph_svg_reveal_38.png'),
      );
    },
  );
}
