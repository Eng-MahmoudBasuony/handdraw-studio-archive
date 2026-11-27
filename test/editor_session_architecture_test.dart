import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'session application ports do not depend on UI, legacy, or infrastructure',
    () {
      final files = Directory('lib/features/editor/application/session')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final forbidden = RegExp(
        r'EditorCubit|HandDrawProject|BuildContext|package:flutter/|dart:io|'
        r'package:koni_|DevelopmentProjectManifestCodec|readAsBytes',
      );
      for (final file in files) {
        expect(
          file.readAsStringSync(),
          isNot(matches(forbidden)),
          reason: file.path,
        );
      }
    },
  );

  test('staging and fingerprint infrastructure never use readAsBytes', () {
    final files = [
      File(
        'lib/features/editor/infrastructure/file_editor_asset_staging_store.dart',
      ),
      File(
        'lib/features/editor/infrastructure/'
        'canonical_document_fingerprint_calculator.dart',
      ),
    ];
    for (final file in files) {
      expect(file.readAsStringSync(), isNot(contains('readAsBytes')));
    }
  });

  test('runtime EditorCubit owns the session lifecycle after cutover', () {
    final source = File(
      'lib/features/editor/application/editor_cubit.dart',
    ).readAsStringSync();
    expect(source, contains('EditorSessionCoordinator'));
    expect(source, contains('FileEditorAssetStagingStore'));
    expect(source, contains('StagedAssetReferenceKind.preview'));
  });
}
