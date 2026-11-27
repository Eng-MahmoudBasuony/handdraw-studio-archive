import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_canvas_overlay.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_zoom_preset_dialog.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/canvas_viewport_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('camera zoom preset dialog ${locale.languageCode} golden', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(720, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          theme: ThemeData(colorSchemeSeed: const Color(0xff5b5bd6)),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('camera-zoom-preset-golden'),
              child: ColoredBox(
                color: const Color(0xffeeeeee),
                child: Center(
                  child: CameraZoomPresetDialog(
                    totalDuration: TimelineDuration.fromMicroseconds(6000000),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('camera-zoom-preset-golden')),
        matchesGoldenFile(
          'goldens/camera_zoom_preset_${locale.languageCode}.png',
        ),
      );
    });
  }

  for (final variant in const [
    'simple_view',
    'simple_view_thirds',
    'simple_view_locked_ar',
    'full_view',
  ]) {
    testWidgets('camera canvas $variant golden', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 650));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final editor = EditorCubit();
      final editing = CameraEditingCubit();
      addTearDown(editor.close);
      addTearDown(editing.close);
      final view = variant == 'full_view'
          ? const CameraView.identity()
          : const CameraView(centerX: .62, centerY: .43, viewportWidth: .48);
      editor.addCameraShotAtWithView(TimelineTime.zero, view);
      final shot = editor.state.document.cameraTrack!.shots.single;
      if (variant.endsWith('locked_ar')) {
        editor.setCameraShotsLocked({shot.id}, true);
      }
      editing.selectKeyframe(shot.id, shot.keyframes.single.id);
      editing.restoreEditorView(view);
      if (variant.endsWith('thirds')) {
        editing.setCompositionGrid(CameraCompositionGrid.ruleOfThirds);
      }
      await tester.pumpWidget(
        MaterialApp(
          locale: variant.endsWith('ar')
              ? const Locale('ar')
              : const Locale('en'),
          theme: ThemeData(colorSchemeSeed: const Color(0xff5b5bd6)),
          home: Scaffold(
            body: RepaintBoundary(
              child: ColoredBox(
                color: const Color(0xffeeeeee),
                child: Column(
                  children: [
                    CameraViewControlBar(
                      editor: editor,
                      editing: editing,
                      readOnly: false,
                      playheadTime: TimelineTime.zero,
                      onPreviewShot: (_) {},
                    ),
                    Expanded(
                      child: variant == 'full_view'
                          ? CanvasViewportFrame(
                              showShadow: false,
                              child: CameraCanvasOverlay(
                                editor: editor,
                                editing: editing,
                                readOnly: false,
                              ),
                            )
                          : CameraCanvasOverlay(
                              editor: editor,
                              editing: editing,
                              readOnly: false,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(RepaintBoundary).last,
        matchesGoldenFile('goldens/camera_canvas_$variant.png'),
      );
    });
  }
}
