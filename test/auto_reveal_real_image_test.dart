import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_reveal_planner.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

class _NoTextDetector implements TextLayoutDetector {
  const _NoTextDetector();

  @override
  Future<List<SmartTextRegion>> detect(Uint8List encodedImage) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Auto Reveal progressively reveals the real build-fails artwork',
    () async {
      final bytes = await File(
        'test/fixtures/04-build-fails.png',
      ).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final source = (await codec.getNextFrame()).image;
      codec.dispose();
      final analysis = await const SmartPathEngine(
        textDetector: _NoTextDetector(),
      ).analyze(image: source, encodedImage: bytes);
      final baseProject = HandDrawProject(
        canvasWidth: 1920,
        canvasHeight: 1080,
        durationSeconds: 2,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
      );
      final plan = const AutoRevealPlanner().build(
        sections: analysis.sections,
        project: baseProject,
      );
      final project = baseProject.copyWith(strokes: plan.strokes);
      const renderer = FrameRenderer();
      final start = await renderer.render(
        project: project,
        drawing: source,
        hand: null,
        progress: 0,
      );
      final middle = await renderer.render(
        project: project,
        drawing: source,
        hand: null,
        progress: 0.5,
      );
      final end = await renderer.render(
        project: project,
        drawing: source,
        hand: null,
        progress: 1,
      );

      final startVisible = await _visiblePixelCount(start);
      final middleVisible = await _visiblePixelCount(middle);
      final endVisible = await _visiblePixelCount(end);

      expect(plan.strokes, isNotEmpty);
      expect(plan.strokes.every((stroke) => stroke.revealOnly), isTrue);
      expect(startVisible, 0);
      expect(middleVisible, greaterThan(0));
      expect(middleVisible, lessThan(endVisible));
      expect(endVisible, greaterThan(10000));
      await expectLater(
        middle,
        matchesGoldenFile('goldens/auto_reveal_build_fails_mid.png'),
      );

      start.dispose();
      middle.dispose();
      end.dispose();
      source.dispose();
    },
  );
}

Future<int> _visiblePixelCount(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  var count = 0;
  for (var index = 3; index < bytes.length; index += 4) {
    if (bytes[index] > 0) count++;
  }
  return count;
}
