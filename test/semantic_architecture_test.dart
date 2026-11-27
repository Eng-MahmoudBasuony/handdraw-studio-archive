import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('semantic domain has no UI, runtime, legacy, or camera dependency', () {
    final files = Directory('lib/features/semantic/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: file.path);
      expect(source, isNot(contains("import 'dart:ui'")), reason: file.path);
      expect(source, isNot(contains('/camera/')), reason: file.path);
      expect(source, isNot(contains('HandDrawProject')), reason: file.path);
      expect(source, isNot(contains('Cubit')), reason: file.path);
      expect(source, isNot(contains('normalizedProgress')), reason: file.path);
    }
  });

  test('derived semantic graph is absent from manifest codec', () {
    final codec = File(
      'lib/features/project/infrastructure/development_project_manifest_codec.dart',
    ).readAsStringSync();
    expect(codec, isNot(contains('CompiledSemanticRegionGraph')));
    expect(codec, isNot(contains('SemanticWorldBounds')));
    expect(codec, isNot(contains('SemanticAdjacencyEdge')));
  });
}
