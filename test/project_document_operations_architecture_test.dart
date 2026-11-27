import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('document operations stay pure and independent from runtime owners', () {
    final files = Directory('lib/features/project/domain/operations')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final forbidden = RegExp(
      r'HandDrawProject|EditorCubit|BuildContext|ui\.Image|dart:io|'
      r'package:flutter/|package:koni_|ProjectContainerStore|readAsBytes',
    );
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(matches(forbidden)), reason: file.path);
      expect(source, isNot(contains('DocumentRevision')), reason: file.path);
    }
  });

  test('runtime editor is wired to pure document operations', () {
    final source = File(
      'lib/features/editor/application/editor_cubit.dart',
    ).readAsStringSync();
    expect(source, contains('/domain/operations/'));
    expect(source, contains('DocumentOperations'));
  });
}
