import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'camera domain has no UI, legacy, rendering, matrix or double timing',
    () {
      final source = Directory('lib/features/camera/domain')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      for (final forbidden in [
        'package:flutter/',
        'dart:ui',
        'HandDrawProject',
        'Matrix4',
        'FrameRenderer',
        'AutoDirector',
        'durationSeconds',
        'startSeconds',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(source, contains('CameraAuthorship'));
      expect(source, contains('isLocked'));
    },
  );

  test('decoder reads camera IDs and never owns an ID generator', () {
    final source = File(
      'lib/features/project/infrastructure/development_project_manifest_codec.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('IdGenerator')));
    expect(source, contains("CameraShotId(_string"));
    expect(source, isNot(contains('Matrix4')));
  });
}
