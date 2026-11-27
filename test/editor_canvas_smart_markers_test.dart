import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';

void main() {
  test(
    'dense glyph starts are decluttered while their total stays visible',
    () {
      final starts = [
        for (var index = 0; index < 24; index++) Offset(index * 4, 0),
      ];
      final visible = smartPathMarkerIndices(starts);
      final section = SmartPathSection(
        id: 'title',
        kind: SmartSectionKind.text,
        bounds: Rect.fromLTWH(0.2, 0.1, 0.6, 0.1),
        label: 'Title',
        paths: [
          for (var index = 0; index < 24; index++)
            SmartGeneratedPath(
              points: [Offset(index / 30, 0.1), Offset(index / 30, 0.2)],
            ),
        ],
        recommendedRevealWidth: 0.02,
        mode: SmartSectionMode.handDraw,
      );

      expect(visible.first, 0);
      expect(visible.length, lessThan(8));
      expect(
        smartSectionCanvasLabel(
          number: 1,
          section: section,
          modeLabel: 'Hand',
          pathsLabel: 'Paths',
        ),
        '1  Hand • 24 Paths',
      );
    },
  );
}
