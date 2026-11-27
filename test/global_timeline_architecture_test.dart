import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'global timeline domain has no legacy, UI, runtime, or second timing source',
    () {
      final files = Directory('lib/features/timeline/domain')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final source = files.map((file) => file.readAsStringSync()).join('\n');

      for (final forbidden in [
        'HandDrawProject',
        'drawing_project.dart',
        'package:flutter/',
        "dart:ui",
        'Cubit',
        'EditorState',
        'Playback',
        'VideoExport',
        'normalizedProgress',
        'double ',
        'timelineRevision',
        'CameraKeyframe',
        'CameraShot',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: 'Forbidden timeline-domain dependency: $forbidden',
        );
      }
    },
  );
}
