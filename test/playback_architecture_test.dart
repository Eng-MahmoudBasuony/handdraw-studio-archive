import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'playback domain stays independent from UI, plugins, Cubit, and legacy',
    () {
      final files = Directory('lib/features/playback')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));
      final source = files.map((file) => file.readAsStringSync()).join('\n');
      for (final forbidden in [
        'package:flutter/',
        'dart:ui',
        'just_audio',
        'audioplayers',
        'Cubit',
        'EditorCubit',
        'WritingAudioService',
        'HandDrawProject',
        'VideoExport',
        'Preview',
        'sleep(',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: 'Forbidden playback-domain dependency: $forbidden',
        );
      }
    },
  );

  test('editor Cubit is not a playback frame ticker', () {
    final source = File(
      'lib/features/editor/application/editor_cubit.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('PlaybackClock')));
    expect(source, isNot(contains('AudioCoordinator')));
  });
}
