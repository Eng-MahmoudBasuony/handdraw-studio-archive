import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera canvas keeps domain free of UI and legacy dependencies', () {
    final files = Directory('lib/features/camera/domain')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: file.path);
      expect(source, isNot(contains('HandDrawProject')), reason: file.path);
      expect(source, isNot(contains('EditorCubit')), reason: file.path);
      expect(source, isNot(contains('AutoDirector')), reason: file.path);
      expect(source, isNot(contains('SemanticRegion')), reason: file.path);
    }
  });

  test('canvas interaction commits through editor transaction boundary', () {
    final overlay = File(
      'lib/features/camera/presentation/camera_canvas_overlay.dart',
    ).readAsStringSync();
    final commitService = File(
      'lib/features/camera/application/camera_editor_view_commit_service.dart',
    ).readAsStringSync();
    expect(overlay, contains('CameraEditorViewCommitService'));
    expect(commitService, contains('updateSimpleCameraView'));
    expect(overlay, isNot(contains('CameraDocumentOperations')));
    expect(overlay, isNot(contains('copyWith(cameraTrack:')));
    expect(commitService, isNot(contains('CameraDocumentOperations')));
    expect(commitService, isNot(contains('copyWith(cameraTrack:')));
  });

  test('shot preview is bounded by the existing global playback clock', () {
    final screen = File(
      'lib/features/editor/presentation/pages/editor_screen.dart',
    ).readAsStringSync();
    final overlay = File(
      'lib/features/camera/presentation/camera_canvas_overlay.dart',
    ).readAsStringSync();
    expect('PlaybackClock('.allMatches(screen), hasLength(1));
    expect(screen, contains('shot.startTime.microseconds'));
    expect(screen, contains('previewCameraShotEnd = shot.endTime'));
    expect(screen, contains("state.currentTime.compareTo(shotEnd) >= 0"));
    expect(screen, contains('_stopPreview();'));
    expect(overlay, isNot(contains('PlaybackClock')));
    expect(overlay, isNot(contains('Timer(')));
  });

  test('transient pointer path cannot compile timeline or write history', () {
    final overlay = File(
      'lib/features/camera/presentation/camera_canvas_overlay.dart',
    ).readAsStringSync();
    expect(overlay, isNot(contains('compileTimeline')));
    expect(overlay, isNot(contains('history.')));
    expect(overlay, isNot(contains('CameraDocumentOperations')));
  });
}
