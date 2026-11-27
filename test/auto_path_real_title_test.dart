import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

class _TitleTextDetector implements TextLayoutDetector {
  const _TitleTextDetector();

  @override
  Future<List<SmartTextRegion>> detect(Uint8List encodedImage) async => const [
    SmartTextRegion(
      text: 'DEPENDENCY HELL',
      bounds: ui.Rect.fromLTWH(0.21, 0.075, 0.58, 0.08),
      confidence: 1,
    ),
    SmartTextRegion(
      text: 'When one package update breaks the whole project',
      bounds: ui.Rect.fromLTWH(0.23, 0.205, 0.55, 0.04),
      confidence: 1,
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real title paths remain in reading order before the underline',
    () async {
      final bytes = await File('test/fixtures/00-title.png').readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      final analysis = await const SmartPathEngine(
        textDetector: _TitleTextDetector(),
      ).analyze(image: image, encodedImage: bytes);
      final plan = const AutoPathStrokePlanner().build(
        sections: analysis.sections,
        project: HandDrawProject(),
      );
      final title = plan.strokes
          .where((stroke) => stroke.sectionId == 'text-0' && !stroke.revealOnly)
          .toList(growable: false);
      const detectedTitleBounds = ui.Rect.fromLTWH(0.21, 0.075, 0.58, 0.08);
      final underlineIndex = plan.strokes.indexWhere(
        (stroke) => stroke.sectionId?.startsWith('shape-') ?? false,
      );
      final lastTitleIndex = plan.strokes.lastIndexWhere(
        (stroke) => stroke.sectionId == 'text-0',
      );
      final firstSubtitleIndex = plan.strokes.indexWhere(
        (stroke) => stroke.sectionId == 'text-1',
      );
      final lastUnderlineIndex = plan.strokes.lastIndexWhere(
        (stroke) => stroke.sectionId?.startsWith('shape-') ?? false,
      );
      final underlineStrokes = plan.strokes
          .where((stroke) => stroke.sectionId == 'shape-0')
          .toList(growable: false);

      expect(analysis.sections, hasLength(3));
      expect(title.length, greaterThan(15));
      for (var index = 1; index < title.length; index++) {
        expect(
          _left(title[index]),
          greaterThanOrEqualTo(_left(title[index - 1])),
          reason: 'Title contours must progress left-to-right.',
        );
      }
      final underlineLikeTitlePaths = title
          .where((stroke) {
            final bounds = _bounds(stroke);
            return bounds.width > 0.2 &&
                bounds.center.dy > detectedTitleBounds.bottom;
          })
          .map(_bounds)
          .toList(growable: false);
      expect(
        underlineLikeTitlePaths,
        isEmpty,
        reason:
            'A nearby underline must remain a separate artwork section, not '
            'be traced as a title glyph path. Outside paths: '
            '$underlineLikeTitlePaths',
      );
      final titleClipBottoms = title
          .map((stroke) => stroke.clipBounds?.bottom)
          .toSet();
      expect(
        titleClipBottoms.every(
          (bottom) =>
              bottom != null && bottom <= detectedTitleBounds.bottom + 0.01,
        ),
        isTrue,
        reason:
            'Title reveal clips must stop before a nearby underline so the '
            'line cannot appear underneath the active pen tip. Clip bottoms: '
            '$titleClipBottoms',
      );
      expect(
        title.every((stroke) => stroke.exclusionBounds.isNotEmpty),
        isTrue,
        reason:
            'Nearby underline pixels must be excluded while title glyphs are '
            'being revealed.',
      );
      expect(underlineIndex, greaterThan(lastTitleIndex));
      expect(firstSubtitleIndex, greaterThan(lastUnderlineIndex));
      expect(
        underlineStrokes,
        hasLength(2),
        reason:
            'The two source underline strokes must stay distinct instead of '
            'being approximated by one oversized reveal path.',
      );
      expect(
        _centerY(underlineStrokes.first),
        lessThan(_centerY(underlineStrokes.last)),
        reason: 'The upper underline must be drawn before the lower one.',
      );
      expect(
        underlineStrokes.first.clipBounds!.bottom,
        lessThanOrEqualTo(underlineStrokes.last.clipBounds!.top),
        reason:
            'Each pen pass must reveal only its own source line so the lower '
            'line does not appear early under the upper pen tip.',
      );
      expect(
        underlineStrokes.every((stroke) => stroke.orderedPoints.length > 2),
        isTrue,
      );
      image.dispose();
    },
  );
}

double _centerY(DrawingStroke stroke) {
  final bounds = _bounds(stroke);
  return bounds.center.dy;
}

double _left(DrawingStroke stroke) => stroke.points
    .map((point) => point.dx)
    .reduce((left, value) => value < left ? value : left);

ui.Rect _bounds(DrawingStroke stroke) {
  var result = ui.Rect.fromPoints(
    stroke.orderedPoints.first,
    stroke.orderedPoints.first,
  );
  for (final point in stroke.orderedPoints.skip(1)) {
    result = result.expandToInclude(ui.Rect.fromPoints(point, point));
  }
  return result;
}
