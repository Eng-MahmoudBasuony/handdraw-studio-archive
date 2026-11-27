import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'active preview and export have no legacy or normalized timing source',
    () {
      final preview = File(
        'lib/features/editor/presentation/pages/editor_screen.dart',
      ).readAsStringSync();
      final export = File(
        'lib/features/export/infrastructure/video_export_service.dart',
      ).readAsStringSync();

      for (final source in [preview, export]) {
        expect(source, isNot(contains('projectTimelineDuration')));
        expect(source, isNot(contains('projectTimelineSectionSpans')));
        expect(source, isNot(contains('frameIndex / (frameCount - 1)')));
      }
      expect(preview, isNot(contains('writingAudioService.position()')));
      expect(preview, isNot(contains('_pollPreviewPosition')));
      expect(export, isNot(contains('PlaybackClock')));
      expect(export, contains('resolveForExportFrame'));
      expect(preview, contains('resolveForPreview'));
    },
  );

  test(
    'renderer has no EditorCubit dependency and legacy timing has one adapter',
    () {
      final renderer = File(
        'lib/features/export/infrastructure/frame_renderer.dart',
      ).readAsStringSync();
      expect(renderer, isNot(contains('EditorCubit')));
      expect(renderer, isNot(contains('GlobalTimelineResolver')));

      final adapters = Directory('lib/features/drawing_engine/infrastructure')
          .listSync()
          .whereType<File>()
          .where(
            (file) => file.path.endsWith('resolved_drawing_frame_adapter.dart'),
          );
      expect(adapters, hasLength(1));
    },
  );
}
