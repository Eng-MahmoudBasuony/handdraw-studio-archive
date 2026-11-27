import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads SVG as a portable PNG preview plus editable vector paths',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'handdraw-svg-import-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/lesson.svg');
      await file.writeAsString('''
      <svg viewBox="0 0 200 100" width="200" height="100"
        xmlns="http://www.w3.org/2000/svg">
        <path id="lesson-path" fill="none" stroke="#111" stroke-width="4"
          d="M 20 50 C 60 10 140 90 180 50" />
      </svg>
    ''');

      final asset = await const EditorFileService().loadImage(file.path);
      addTearDown(asset.image.dispose);
      addTearDown(() => asset.revealBaseImage?.dispose());
      addTearDown(() => asset.svgRevealLayers?.strokes.dispose());
      addTearDown(() => asset.svgRevealLayers?.globalStrokes?.dispose());

      expect(asset.path, file.path);
      expect(asset.image.width, 4096);
      expect(asset.image.height, 2048);
      expect(asset.encoded, isNotEmpty);
      expect(asset.sourceKind, ArtworkSourceKind.svg);
      expect(asset.sourceEncoded, isNotEmpty);
      expect(asset.revealBaseEncoded, isNotEmpty);
      expect(asset.revealBaseImage, isNotNull);
      expect(asset.revealStrokeEncoded, isNotEmpty);
      expect(asset.svgRevealLayers, isNotNull);
      expect(asset.svgRevealLayers!.globalStrokes, isNull);
      expect(asset.vectorPaths, hasLength(1));
      expect(asset.vectorPaths.single.id, 'lesson-path');
      expect(asset.importWarnings, isEmpty);
    },
  );

  test('loads an isolated reveal layer for canvas-spanning strokes', () async {
    final asset = await const EditorFileService().loadImage(
      'test/fixtures/complex-crossing-strokes.svg',
    );
    addTearDown(asset.image.dispose);
    addTearDown(() => asset.revealBaseImage?.dispose());
    addTearDown(() => asset.svgRevealLayers?.strokes.dispose());
    addTearDown(() => asset.svgRevealLayers?.globalStrokes?.dispose());

    expect(asset.svgRevealLayers, isNotNull);
    expect(asset.svgRevealLayers!.globalStrokes, isNotNull);
    expect(
      asset.vectorPaths.where((path) => path.isGlobalDecoration),
      hasLength(2),
    );
  });
}
