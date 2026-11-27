import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';
import 'package:handdraw_studio/features/scene_composer/infrastructure/scene_library.dart';

void main() {
  late Directory directory;
  late SceneLibrary library;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('scene-library-test-');
    library = SceneLibrary(directory);
  });
  tearDown(() => directory.delete(recursive: true));

  test('damaged entries do not hide valid assets or templates', () async {
    final design = SceneDesign.example();
    await library.save(design);
    final invalid = ['[]', 'null', '{', '{"elements":[null],"title":"Bad"}'];
    for (final folder in ['elements', 'scenes']) {
      for (final (index, value) in invalid.indexed) {
        await File(
          '${directory.path}/$folder/bad-$index.json',
        ).writeAsString(value);
      }
    }
    expect(await library.read(), hasLength(design.elements.length));
    expect(await library.scenes(), hasLength(1));
    expect(library.diagnostics, hasLength(8));
    expect(
      library.diagnostics.every(
        (d) => d.path.endsWith('.json') && d.message.isNotEmpty,
      ),
      isTrue,
    );
    expect(
      await File('${directory.path}/scenes/bad-0.json').readAsString(),
      '[]',
    );
    await library.read();
    await library.scenes();
    expect(
      library.diagnostics,
      hasLength(8),
      reason: 'refresh replaces diagnostics',
    );
  });

  test('broken recent files cannot consume the valid template limit', () async {
    await library.save(SceneDesign.example());
    for (var i = 0; i < 31; i++) {
      await File('${directory.path}/scenes/z-$i.json').writeAsString('null');
    }
    expect(await library.scenes(), hasLength(1));
    expect(library.diagnostics, hasLength(31));
  });

  test('nested malformed paths are isolated', () async {
    final design = SceneDesign.example();
    await library.save(design);
    final broken = design.elements.first.toJson()..['paths'] = [null];
    await File(
      '${directory.path}/elements/bad.json',
    ).writeAsString(jsonEncode(broken));
    expect(await library.read(), hasLength(design.elements.length));
    expect(library.diagnostics, hasLength(1));
  });
  test('invalid SVG syntax is isolated from valid library entries', () async {
    final design = SceneDesign.example();
    await library.save(design);
    final broken = design.elements.first.toJson()
      ..['paths'] = [
        {'d': 'M 0', 'fill': '#FFFFFF', 'stroke': '#000000'},
      ];
    await File(
      '${directory.path}/elements/bad-path.json',
    ).writeAsString(jsonEncode(broken));
    expect(await library.read(), hasLength(design.elements.length));
    expect(library.diagnostics, hasLength(1));
  });
}
