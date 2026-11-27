import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history foundation has no legacy, UI, IO, or container dependency', () {
    final files = Directory('lib/features/editor/application/history')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final forbidden = RegExp(
      r'HandDrawProject|EditorCubit|BuildContext|ui\.Image|dart:io|'
      r'package:flutter/|package:koni_|ProjectContainerStore|readAsBytes|'
      r'Uint8List|ByteData',
    );
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(matches(forbidden)), reason: file.path);
    }
  });

  test('runtime cutover uses the unified EditorHistory', () {
    final source = File(
      'lib/features/editor/application/editor_cubit.dart',
    ).readAsStringSync();
    expect(source, contains('/application/history/'));
    expect(source, contains('EditorHistory'));
  });
}
