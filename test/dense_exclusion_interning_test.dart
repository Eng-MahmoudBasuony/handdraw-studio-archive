import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_rect_list.dart';

void main() {
  test('dense paths share one exact text-exclusion working set', () {
    const textCount = 96;
    const pathCount = 1024;
    final textSections = List.generate(textCount, _textSection);
    final shapePaths = List.generate(pathCount, (index) {
      final x = (index % 64) / 64;
      final y = (index ~/ 64) / 16;
      return SmartGeneratedPath(
        points: [
          Offset(x, y),
          Offset((x + 0.008).clamp(0, 1), (y + 0.006).clamp(0, 1)),
        ],
      );
    });
    final shapeSection = SmartPathSection(
      id: 'dense-shapes',
      kind: SmartSectionKind.shape,
      bounds: const Rect.fromLTWH(0, 0, 1, 1),
      label: 'Dense shapes',
      paths: shapePaths,
      recommendedRevealWidth: 0.008,
      mode: SmartSectionMode.handDraw,
    );

    final plan = const AutoPathStrokePlanner().build(
      sections: [...textSections, shapeSection],
      project: HandDrawProject(),
    );
    final shapes = plan.strokes
        .where((stroke) => stroke.sectionId == shapeSection.id)
        .toList(growable: false);

    expect(shapes, hasLength(pathCount));
    final normalized = shapes.first.exclusionBounds;
    expect(normalized, isA<ImmutableRectList>());
    expect(normalized, hasLength(textCount));
    expect(
      normalized.first,
      textSections.first.bounds
          .inflate(0.003)
          .intersect(const Rect.fromLTWH(0, 0, 1, 1)),
    );
    for (final stroke in shapes.skip(1)) {
      expect(identical(stroke.exclusionBounds, normalized), isTrue);
    }

    const artworkRect = Rect.fromLTWH(12, 24, 1920, 1080);
    final geometries = buildStrokeGeometry(shapes, artworkRect);
    expect(geometries, hasLength(pathCount));
    final scaled = geometries.first.exclusionRects;
    expect(scaled, isA<ImmutableRectList>());
    expect(
      scaled.first,
      Rect.fromLTRB(
        artworkRect.left + normalized.first.left * artworkRect.width,
        artworkRect.top + normalized.first.top * artworkRect.height,
        artworkRect.left + normalized.first.right * artworkRect.width,
        artworkRect.top + normalized.first.bottom * artworkRect.height,
      ),
    );
    for (final geometry in geometries.skip(1)) {
      expect(identical(geometry.exclusionRects, scaled), isTrue);
    }

    final cached = scaled as ImmutableRectList;
    expect(cached.contentHash, Object.hashAll(scaled));
    expect(cached.contentHash, cached.contentHash);
  });

  test(
    'canonical exclusion lists stay immutable and copies preserve identity',
    () {
      final exclusions = ImmutableRectList.freeze(const [
        Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
      ]);
      final stroke = DrawingStroke(
        id: 'shared',
        name: 'Shared',
        points: const [Offset.zero, Offset(1, 1)],
        exclusionBounds: exclusions,
      );
      final copy = stroke.copyWith(name: 'Copy');

      expect(identical(stroke.exclusionBounds, exclusions), isTrue);
      expect(identical(copy.exclusionBounds, exclusions), isTrue);
      expect(() => exclusions.add(Rect.zero), throwsUnsupportedError);
    },
  );
}

SmartPathSection _textSection(int index) {
  final column = index % 12;
  final row = index ~/ 12;
  final bounds = Rect.fromLTWH(
    0.01 + column * 0.08,
    0.01 + row * 0.11,
    0.055,
    0.045,
  );
  return SmartPathSection(
    id: 'text-$index',
    kind: SmartSectionKind.text,
    bounds: bounds,
    label: 'Text $index',
    paths: [
      SmartGeneratedPath(points: [bounds.centerLeft, bounds.centerRight]),
    ],
    recommendedRevealWidth: 0.006,
    mode: SmartSectionMode.revealText,
  );
}
