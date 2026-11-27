// Opt-in benchmark output is intentionally machine readable.
// ignore_for_file: avoid_print
import 'dart:io';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/image_animation/domain/region_drawing_planner.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'dart:typed_data';

class _Files extends EditorFileService {
  const _Files(this.bytes);
  final Uint8List bytes;
  @override
  Future<ImportedEditorAsset?> pickDrawing({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) => loadImageBytes(path: 'source.png', bytes: bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'compare independent and integrated image animation stages',
    () async {
      const source = String.fromEnvironment('IMAGE');
      expect(
        source,
        isNotEmpty,
        reason: 'Pass --dart-define=IMAGE=/absolute/image.png',
      );
      final bytes = await File(source).readAsBytes();
      final watch = Stopwatch()..start();
      final plan = const RegionDrawingPlanner().build(bytes);
      print(
        'PROBE plan_ms=${watch.elapsedMilliseconds} strokes=${plan.strokes.length}',
      );
      final c = EditorCubit(fileService: _Files(bytes));
      watch.reset();
      await c.importDrawing();
      print('PROBE import_ms=${watch.elapsedMilliseconds}');
      watch.reset();
      await c.prepareImageAnimation();
      print(
        'PROBE analyze_commit_ms=${watch.elapsedMilliseconds} strokes=${c.project.strokes.length}',
      );
      for (var i = 0; i < 2; i++) {
        watch.reset();
        final snapshot = await c.acquireRenderSnapshot(
          kind: StagedAssetReferenceKind.preview,
        );
        print('PROBE snapshot_$i=${watch.elapsedMilliseconds}');
        await snapshot.release();
      }
      for (var i = 0; i < 3; i++) {
        watch.reset();
        projectTimelineDuration(c.project);
        projectTimelineSectionMetrics(c.project);
        c.timelineSectionRanges;
        print('PROBE chrome_$i=${watch.elapsedMilliseconds}');
      }
      final direct = HandDrawProject(
        canvasWidth: c.project.canvasWidth,
        canvasHeight: c.project.canvasHeight,
        imageAnimationEffect: 'drawPaint',
        durationSeconds: 6,
        strokes: plan.strokes.map((s) => s.stroke).toList(),
      );
      for (final entry in [('direct', direct), ('integrated', c.project)]) {
        final times = <int>[];
        for (var i = 0; i < 15; i++) {
          watch.reset();
          final im = await const FrameRenderer().render(
            project: entry.$2,
            drawing: c.state.drawingImage!,
            hand: null,
            progress: (i + 1) / 16,
          );
          await im.toByteData();
          im.dispose();
          times.add(watch.elapsedMicroseconds);
        }
        print('PROBE ${entry.$1} frame_us=$times');
      }
      final paints = <int>[];
      for (var i = 0; i < 15; i++) {
        watch.reset();
        final recorder = ui.PictureRecorder();
        EditorCanvasPainter(
          state: c.state,
          project: c.project,
          previewProgress: (i + 1) / 16,
          isPreviewing: true,
          interfaceTextDirection: TextDirection.ltr,
          emptyStateLabel: '',
          handModeLabel: '',
          revealModeLabel: '',
          ignoreModeLabel: '',
          pathsLabel: '',
          colors: AppPalette.dark,
        ).paint(ui.Canvas(recorder), const ui.Size(1100, 619));
        final picture = recorder.endRecording();
        final im = await picture.toImage(1100, 619);
        await im.toByteData();
        picture.dispose();
        im.dispose();
        paints.add(watch.elapsedMicroseconds);
      }
      print('PROBE canvas_us=$paints rss=${ProcessInfo.currentRss}');
      await c.close();
    },
    skip: !const bool.fromEnvironment('RUN_IMAGE_PROBE'),
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
