import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'camera timeline UI has one shared viewport and no document mutation',
    () {
      final source = File(
        'lib/features/editor/presentation/widgets/editor_timeline_dock.dart',
      ).readAsStringSync();
      expect('ScrollController'.allMatches(source), hasLength(2));
      expect(source, contains('CameraEditingCubit'));
      expect(source, contains('TimelineSnapService'));
      expect(source, isNot(contains('copyWith(cameraTrack:')));
      expect(source, isNot(contains('CameraDocumentOperations()')));
      expect(source, isNot(contains('SemanticRegion')));
      expect(source, isNot(contains('SmartAutoDirector')));
      expect(source, isNot(contains('AutoDirectorApplicationService')));
      expect(source, isNot(contains('CameraShotId(')));
    },
  );

  test('camera clip rendering is painter-backed, not a widget per shot', () {
    final source = File(
      'lib/features/editor/presentation/widgets/editor_timeline_dock.dart',
    ).readAsStringSync();
    expect(source, contains('class _CameraTrackPainter extends CustomPainter'));
    expect(source, isNot(contains('for (final shot in track.shots) _Camera')));
  });
}
