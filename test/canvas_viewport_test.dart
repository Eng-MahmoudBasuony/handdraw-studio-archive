import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/canvas_geometry.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/canvas_viewport_frame.dart';

void main() {
  group('CanvasGeometry.contain', () {
    test('keeps wide artwork centered without cropping', () {
      final rect = CanvasGeometry.contain(
        viewportSize: const Size(1920, 1080),
        contentSize: const Size(2000, 1000),
      );

      expect(rect, const Rect.fromLTWH(0, 60, 1920, 960));
    });

    test('keeps tall artwork centered without cropping', () {
      final rect = CanvasGeometry.contain(
        viewportSize: const Size(1920, 1080),
        contentSize: const Size(1000, 1000),
      );

      expect(rect, const Rect.fromLTWH(420, 0, 1080, 1080));
    });

    test('uses the complete viewport when there is no artwork', () {
      expect(
        CanvasGeometry.contain(viewportSize: const Size(320, 180)),
        const Rect.fromLTWH(0, 0, 320, 180),
      );
    });
  });

  testWidgets('canvas frame keeps the complete square output boundary', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: const [AppPalette.light]),
        home: Center(
          child: SizedBox(
            width: 200,
            height: 100,
            child: CanvasViewportFrame(
              showShadow: false,
              child: const ColoredBox(color: Colors.red),
            ),
          ),
        ),
      ),
    );

    final frame = find.byKey(const ValueKey('canvas-viewport-frame'));
    final clips = tester.widgetList<ClipRRect>(
      find.descendant(of: frame, matching: find.byType(ClipRRect)),
    );
    final radii = clips.map((clip) => clip.borderRadius).toList();

    expect(clips, hasLength(2));
    expect(clips.every((clip) => clip.clipBehavior == Clip.antiAlias), isTrue);
    expect(radii.first, BorderRadius.zero);
    expect(radii.last, BorderRadius.zero);
  });
}
