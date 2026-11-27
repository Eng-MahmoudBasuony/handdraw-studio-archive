import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/policies/hand_display_policy.dart';
import 'package:handdraw_studio/features/camera/presentation/hand_display_transform.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/hand_image_painter.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'hand image edges are feathered while its center stays opaque',
    () async {
      final sourceRecorder = ui.PictureRecorder();
      final sourceCanvas = ui.Canvas(sourceRecorder);
      sourceCanvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 100, 100),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      );
      final source = await sourceRecorder.endRecording().toImage(100, 100);

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      drawFeatheredHandImage(
        canvas: canvas,
        image: source,
        source: const ui.Rect.fromLTWH(0, 0, 100, 100),
        destination: const ui.Rect.fromLTWH(0, 0, 100, 100),
        opacity: 1,
        featherFraction: 0.1,
      );
      final result = await recorder.endRecording().toImage(100, 100);
      final data = (await result.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final rgba = data.buffer.asUint8List();
      int alphaAt(int x, int y) => rgba[(y * 100 + x) * 4 + 3];

      expect(alphaAt(0, 50), lessThan(30));
      expect(alphaAt(5, 50), inInclusiveRange(80, 200));
      expect(alphaAt(50, 50), greaterThan(245));

      source.dispose();
      result.dispose();
    },
  );

  test('directional arm fade removes the rectangular exit edge', () async {
    final sourceRecorder = ui.PictureRecorder();
    final sourceCanvas = ui.Canvas(sourceRecorder);
    sourceCanvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 100, 100),
      ui.Paint()..color = const ui.Color(0xFFFF0000),
    );
    final source = await sourceRecorder.endRecording().toImage(100, 100);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    drawFeatheredHandImage(
      canvas: canvas,
      image: source,
      source: const ui.Rect.fromLTWH(0, 0, 100, 100),
      destination: const ui.Rect.fromLTWH(0, 0, 100, 100),
      opacity: 1,
      armExit: const ui.Offset(1, 1),
    );
    final result = await recorder.endRecording().toImage(100, 100);
    final rgba = (await result.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    int alphaAt(int x, int y) => rgba[(y * 100 + x) * 4 + 3];

    expect(alphaAt(20, 20), greaterThan(245));
    expect(alphaAt(50, 50), greaterThan(245));
    expect(alphaAt(70, 70), inInclusiveRange(40, 210));
    expect(alphaAt(99, 70), lessThan(5));
    expect(alphaAt(70, 99), lessThan(5));

    source.dispose();
    result.dispose();
  });

  test('the real marker has no opaque pixels at its arm exit', () async {
    final bytes = await File(
      'assets/hands/hand-writing-marker.png',
    ).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 384,
      targetHeight: 256,
    );
    final source = (await codec.getNextFrame()).image;
    codec.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    drawFeatheredHandImage(
      canvas: canvas,
      image: source,
      source: ui.Rect.fromLTWH(
        0,
        0,
        source.width.toDouble(),
        source.height.toDouble(),
      ),
      destination: const ui.Rect.fromLTWH(0, 0, 384, 256),
      opacity: 1,
      armExit: const ui.Offset(1, 1),
    );
    final result = await recorder.endRecording().toImage(384, 256);
    final rgba = (await result.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    int alphaAt(int x, int y) => rgba[(y * 384 + x) * 4 + 3];
    var bottomMax = 0;
    var rightMax = 0;
    for (var x = 0; x < 384; x++) {
      bottomMax = bottomMax < alphaAt(x, 255) ? alphaAt(x, 255) : bottomMax;
    }
    for (var y = 0; y < 256; y++) {
      rightMax = rightMax < alphaAt(383, y) ? alphaAt(383, y) : rightMax;
    }

    expect(bottomMax, lessThan(5));
    expect(rightMax, lessThan(5));
    expect(alphaAt(190, 120), greaterThan(80));

    source.dispose();
    result.dispose();
  });

  test('the bundled marker blends cleanly over a paper background', () async {
    final bytes = await File(
      'assets/hands/hand-writing-marker.png',
    ).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 384,
      targetHeight: 256,
    );
    final source = (await codec.getNextFrame()).image;
    codec.dispose();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 640, 360),
      ui.Paint()..color = const ui.Color(0xFFF1E2C5),
    );

    drawFeatheredHandImage(
      canvas: canvas,
      image: source,
      source: ui.Rect.fromLTWH(
        0,
        0,
        source.width.toDouble(),
        source.height.toDouble(),
      ),
      destination: const ui.Rect.fromLTWH(120, 42, 384, 256),
      opacity: 1,
      armExit: const ui.Offset(1, 1),
    );
    final result = await recorder.endRecording().toImage(640, 360);

    await expectLater(
      result,
      matchesGoldenFile('goldens/feathered_marker_on_paper.png'),
    );

    source.dispose();
    result.dispose();
  });

  test('generated hand assets keep their calibrated pen tips', () async {
    for (final preset in _generatedPresets) {
      final bytes = await File(preset.assetPath!).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final tipX = (preset.penTip.dx * image.width).round();
      final tipY = (preset.penTip.dy * image.height).round();
      var localMaxAlpha = 0;
      for (var y = tipY - 10; y <= tipY + 10; y++) {
        for (var x = tipX - 10; x <= tipX + 10; x++) {
          if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
            continue;
          }
          final alpha = rgba[(y * image.width + x) * 4 + 3];
          if (alpha > localMaxAlpha) localMaxAlpha = alpha;
        }
      }

      expect(localMaxAlpha, greaterThan(150), reason: preset.name);
      expect(rgba[3], 0, reason: '${preset.name} must have transparent alpha.');
      if (preset.id == 'marker-front-black-right') {
        int alphaAt(int x, int y) => rgba[(y * image.width + x) * 4 + 3];
        for (final corner in [
          (0, 0),
          (image.width - 1, 0),
          (0, image.height - 1),
          (image.width - 1, image.height - 1),
        ]) {
          expect(
            alphaAt(corner.$1, corner.$2),
            0,
            reason: '${preset.name} must have transparent corners.',
          );
        }
      }
      expect(
        handArmExitForProject(presetId: preset.id, imagePath: preset.assetPath),
        preset.id == 'marker-front-black-right'
            ? const ui.Offset(0.5, 1)
            : const ui.Offset(1, 1),
      );
      image.dispose();
    }
  });

  test('every bundled calibration lands on the visible nib apex', () async {
    final cases = [
      (preset: BuiltInHands.markerRight, topEdge: false, darkSum: 240),
      (preset: BuiltInHands.darkMarkerRight, topEdge: false, darkSum: 240),
      (preset: BuiltInHands.fineLinerRight, topEdge: false, darkSum: 240),
      (preset: BuiltInHands.blueMarkerRight, topEdge: false, darkSum: 240),
      (
        preset: BuiltInHands.wheatTechnicalPenRight,
        topEdge: false,
        darkSum: 240,
      ),
      (preset: BuiltInHands.frontBlackMarkerRight, topEdge: true, darkSum: 180),
    ];
    for (final entry in cases) {
      final preset = entry.preset;
      final bytes = await File(preset.assetPath!).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      var edge = 1 << 30;
      var orthogonalTotal = 0.0;
      var count = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final offset = (y * image.width + x) * 4;
          final alpha = rgba[offset + 3];
          final channelSum = rgba[offset] + rgba[offset + 1] + rgba[offset + 2];
          if (alpha <= 100 || channelSum >= entry.darkSum) continue;
          final primary = entry.topEdge ? y : x;
          final orthogonal = entry.topEdge ? x : y;
          if (primary < edge) {
            edge = primary;
            orthogonalTotal = 0;
            count = 0;
          }
          if (primary == edge) {
            orthogonalTotal += orthogonal;
            count++;
          }
        }
      }
      expect(count, greaterThan(0), reason: preset.name);
      final detected = entry.topEdge
          ? ui.Offset(orthogonalTotal / count, edge.toDouble())
          : ui.Offset(edge.toDouble(), orthogonalTotal / count);
      final calibrated = ui.Offset(
        preset.penTip.dx * image.width,
        preset.penTip.dy * image.height,
      );
      expect(
        (detected - calibrated).distance,
        lessThanOrEqualTo(1.5),
        reason: '${preset.name}: detected=$detected calibrated=$calibrated',
      );
      image.dispose();
    }
    expect(BuiltInHands.markerLeft.penTip, BuiltInHands.markerRight.penTip);
    expect(BuiltInHands.markerCompact.penTip, BuiltInHands.markerRight.penTip);
  });

  test('generated hands blend cleanly over paper', () async {
    final outputHeight = 36 + _generatedPresets.length * 288;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, 640, outputHeight.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFF1E2C5),
    );

    for (var index = 0; index < _generatedPresets.length; index++) {
      final preset = _generatedPresets[index];
      final bytes = await File(preset.assetPath!).readAsBytes();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 384,
        targetHeight: 256,
      );
      final source = (await codec.getNextFrame()).image;
      codec.dispose();
      drawFeatheredHandImage(
        canvas: canvas,
        image: source,
        source: ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        destination: ui.Rect.fromLTWH(120, 28 + index * 288, 384, 256),
        opacity: 1,
        armExit: handArmExitForProject(
          presetId: preset.id,
          imagePath: preset.assetPath,
        ),
      );
      source.dispose();
    }
    final result = await recorder.endRecording().toImage(640, outputHeight);

    await expectLater(
      result,
      matchesGoldenFile('goldens/generated_hands_on_paper.png'),
    );
    result.dispose();
  });

  test('front marker uses its large video scale and calibrated nib', () async {
    const preset = BuiltInHands.frontBlackMarkerRight;
    final bytes = await File(preset.assetPath!).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final source = (await codec.getNextFrame()).image;
    codec.dispose();
    final layout = const HandDisplayPolicy().resolve(
      outputWidth: 640,
      outputHeight: 360,
      imageWidth: 1536,
      imageHeight: 1024,
      preferredHeightFraction: preset.defaultScale,
      penTipX: preset.penTip.dx,
      penTipY: preset.penTip.dy,
    );
    const contact = ui.Offset(280, 90);
    final transform = HandDisplayTransform(
      layout: layout,
      projectedPathPoint: contact,
      rotationRadians: 0,
      flipX: false,
    );
    expect(layout.outputHeightFraction, .85);
    expect(transform.displayedPenTip, contact);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xFFF7F1E4), ui.BlendMode.src)
      ..drawLine(
        const ui.Offset(180, 90),
        contact,
        ui.Paint()
          ..color = const ui.Color(0xFF1769D2)
          ..strokeWidth = 5
          ..strokeCap = ui.StrokeCap.round,
      );
    transform.apply(canvas);
    drawFeatheredHandImage(
      canvas: canvas,
      image: source,
      source: ui.Rect.fromLTWH(
        0,
        0,
        source.width.toDouble(),
        source.height.toDouble(),
      ),
      destination: ui.Rect.fromLTWH(0, 0, layout.width, layout.height),
      opacity: 1,
      armExit: const ui.Offset(0.5, 1),
    );
    final result = await recorder.endRecording().toImage(640, 360);
    await expectLater(
      result,
      matchesGoldenFile('goldens/front_black_marker_reference_scale.png'),
    );
    source.dispose();
    result.dispose();
  });

  test(
    'all hands visually meet the stroke at small default and large scales',
    () async {
      const cellSize = ui.Size(400, 260);
      final outputHeight = (cellSize.height * BuiltInHands.all.length).round();
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(const ui.Color(0xFFF7F1E4), ui.BlendMode.src);
      for (var row = 0; row < BuiltInHands.all.length; row++) {
        final preset = BuiltInHands.all[row];
        final bytes = await File(preset.assetPath!).readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final source = (await codec.getNextFrame()).image;
        codec.dispose();
        final scales = [.08, preset.defaultScale, .9];
        for (var column = 0; column < scales.length; column++) {
          final layout = const HandDisplayPolicy().resolve(
            outputWidth: cellSize.width,
            outputHeight: cellSize.height,
            imageWidth: source.width.toDouble(),
            imageHeight: source.height.toDouble(),
            preferredHeightFraction: scales[column],
            penTipX: preset.penTip.dx,
            penTipY: preset.penTip.dy,
            flipX: preset.flipX,
          );
          final rotation = preset.defaultRotationDegrees * math.pi / 180;
          final originTransform = HandDisplayTransform(
            layout: layout,
            projectedPathPoint: ui.Offset.zero,
            rotationRadians: rotation,
            flipX: preset.flipX,
          );
          final bounds =
              (ui.Path()..addPolygon(originTransform.projectedFootprint, true))
                  .getBounds();
          final contact = cellSize.center(ui.Offset.zero) - bounds.center;
          final transform = HandDisplayTransform(
            layout: layout,
            projectedPathPoint: contact,
            rotationRadians: rotation,
            flipX: preset.flipX,
          );
          canvas.save();
          canvas.translate(column * cellSize.width, row * cellSize.height);
          canvas.drawLine(
            contact - const ui.Offset(62, 0),
            contact,
            ui.Paint()
              ..color = const ui.Color(0xFF1769D2)
              ..strokeWidth = 4
              ..strokeCap = ui.StrokeCap.round,
          );
          transform.apply(canvas);
          drawFeatheredHandImage(
            canvas: canvas,
            image: source,
            source: ui.Rect.fromLTWH(
              0,
              0,
              source.width.toDouble(),
              source.height.toDouble(),
            ),
            destination: ui.Rect.fromLTWH(0, 0, layout.width, layout.height),
            opacity: 1,
            armExit: handArmExitForProject(
              presetId: preset.id,
              imagePath: preset.assetPath,
            ),
          );
          canvas.restore();
        }
        source.dispose();
      }
      final result = await recorder.endRecording().toImage(1200, outputHeight);
      await expectLater(
        result,
        matchesGoldenFile('goldens/all_hands_pen_tip_at_scales.png'),
      );
      result.dispose();
    },
  );
}

const _generatedPresets = [
  BuiltInHands.darkMarkerRight,
  BuiltInHands.fineLinerRight,
  BuiltInHands.blueMarkerRight,
  BuiltInHands.frontBlackMarkerRight,
  BuiltInHands.wheatTechnicalPenRight,
];
