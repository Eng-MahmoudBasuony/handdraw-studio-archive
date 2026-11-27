import 'dart:io';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';
import 'package:handdraw_studio/features/scene_composer/infrastructure/scene_library.dart';
import 'package:handdraw_studio/features/scene_composer/presentation/scene_design_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'scene retains editable text, geometry and categorized reusable assets',
    () async {
      final dir = await Directory.systemTemp.createTemp('handdraw-scene-test-');
      addTearDown(() => dir.delete(recursive: true));
      final library = SceneLibrary(dir), scene = SceneDesign.example();
      await library.save(scene);
      await library.save(scene);
      final elements = await library.read();
      expect(elements.length, scene.elements.length);
      expect(elements.where((e) => e.isText).length, 5);
      expect(elements.any((e) => e.category == 'تقنية'), isTrue);
      final templates = await library.scenes();
      expect(templates.length, 2);
      expect(templates.first.toJson(), scene.toJson());
      final moved = scene.elements.first.copyWith(
        bounds: const Rect.fromLTWH(.1, .1, .2, .2),
      );
      expect(moved.assetId, scene.elements.first.assetId);
    },
  );
  test(
    'scene rejects external content, invalid coordinates and oversized content',
    () {
      final json = SceneDesign.example().toJson();
      final first = (json['elements'] as List).first as Map<String, dynamic>;
      first['x'] = 2;
      expect(() => SceneDesign.parse(json), throwsFormatException);
      first['x'] = .07;
      first['paths'] = [
        {'d': '<script/>', 'fill': '#ffffff', 'stroke': 'none'},
      ];
      expect(() => SceneDesign.parse(json), throwsFormatException);
    },
  );
  test('local preview renders both vector and text on transparency', () async {
    final image = await SceneDesignPainter(
      SceneDesign.example(),
    ).rasterize(width: 640, height: 360);
    final data = (await image.toByteData())!.buffer.asUint8List();
    var colored = 0, ink = 0;
    for (var p = 0; p < data.length; p += 4) {
      if (data[p + 3] > 128) {
        if (data[p + 1] > 100) {
          colored++;
        } else {
          ink++;
        }
      }
    }
    expect(colored, greaterThan(2000));
    expect(ink, greaterThan(1000));
    expect(data[3], 0);
    image.dispose();
  });
}
