import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';
import 'package:handdraw_studio/features/canvas_background/presentation/canvas_background_panel.dart';
import 'package:handdraw_studio/features/canvas_background/presentation/canvas_background_renderer.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/project/infrastructure/legacy_project_view_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all procedural backgrounds render as opaque reusable surfaces',
    () async {
      final signatures = <int>{};
      for (final preset in CanvasBackgroundPreset.values) {
        final image = await _renderBackground(
          CanvasBackground.preset(preset),
          const ui.Size(180, 100),
        );
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        final center = (50 * 180 + 90) * 4;
        expect(bytes[center + 3], 255, reason: '${preset.name} must be opaque');
        signatures.add(
          Object.hash(
            bytes[center],
            bytes[center + 1],
            bytes[center + 2],
            bytes[(22 * 180 + 30) * 4],
          ),
        );
        image.dispose();
      }
      expect(signatures.length, greaterThanOrEqualTo(8));
    },
  );

  test('project background is composited by the shared MOV renderer', () async {
    final source = await _renderBackground(
      const CanvasBackground.transparent(),
      const ui.Size(64, 64),
    );
    final output = await const FrameRenderer().renderResolved(
      frame: ResolvedProjectFrame(
        time: TimelineTime.zero,
        drawing: null,
        camera: const ResolvedSingleCameraView(CameraView.identity()),
        activeAudio: const [],
        voiceGuide: null,
        markers: const [],
        isFinalFrame: false,
      ),
      project: HandDrawProject(
        canvasWidth: 64,
        canvasHeight: 64,
        canvasBackground: const CanvasBackground.solid(0xFF2673D9),
        strokes: const [],
      ),
      drawing: source,
      hand: null,
    );
    final bytes = (await output.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!.buffer.asUint8List();
    final center = (32 * 64 + 32) * 4;

    expect(bytes.sublist(center, center + 4), [38, 115, 217, 255]);
    output.dispose();
    source.dispose();
  });

  test(
    'camera Preview and MOV render the exact same background pixels',
    () async {
      const size = ui.Size(96, 54);
      final drawing = await _renderBackground(
        const CanvasBackground.transparent(),
        size,
      );
      final initial = EditorState.initial();
      final state = initial.copyWith(
        documentState: EditorDocumentState(
          document: initial.document.copyWith(
            canvas: const ProjectCanvas(
              width: 96,
              height: 54,
              background: CanvasBackground.preset(
                CanvasBackgroundPreset.blueprint,
              ),
            ),
          ),
        ),
        drawingImage: drawing,
      );
      final project = LegacyProjectViewCache().resolve(state.documentState);
      final frame = ResolvedProjectFrame(
        time: TimelineTime.zero,
        drawing: null,
        camera: const ResolvedSingleCameraView(
          CameraView(centerX: 0.54, centerY: 0.48, viewportWidth: 0.75),
        ),
        activeAudio: const [],
        voiceGuide: null,
        markers: const [],
        isFinalFrame: false,
      );
      final previewRecorder = ui.PictureRecorder();
      EditorCanvasPainter(
        state: state,
        project: project,
        previewProgress: 0,
        isPreviewing: true,
        cameraOutputPreview: true,
        resolvedFrame: frame,
        interfaceTextDirection: TextDirection.ltr,
        emptyStateLabel: 'Empty',
        handModeLabel: 'Hand',
        revealModeLabel: 'Reveal',
        ignoreModeLabel: 'Ignore',
        pathsLabel: 'Paths',
        colors: AppPalette.dark,
      ).paint(ui.Canvas(previewRecorder), size);
      final previewPicture = previewRecorder.endRecording();
      final preview = await previewPicture.toImage(96, 54);
      previewPicture.dispose();
      final movie = await const FrameRenderer().renderResolved(
        frame: frame,
        project: project,
        drawing: drawing,
        hand: null,
      );
      final previewBytes = (await preview.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final movieBytes = (await movie.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();

      expect(movieBytes, previewBytes);
      preview.dispose();
      movie.dispose();
      drawing.dispose();
    },
  );

  test('each background choice is an independent undo and redo step', () {
    final cubit = EditorCubit();
    addTearDown(cubit.close);

    cubit.setCanvasBackground(
      const CanvasBackground.preset(CanvasBackgroundPreset.notebook),
    );
    cubit.setCanvasBackground(
      const CanvasBackground.preset(CanvasBackgroundPreset.blueprint),
    );

    expect(
      cubit.state.document.canvas.background,
      const CanvasBackground.preset(CanvasBackgroundPreset.blueprint),
    );
    expect(cubit.history.undoEntries, hasLength(2));

    cubit.undoStroke();
    expect(
      cubit.state.document.canvas.background,
      const CanvasBackground.preset(CanvasBackgroundPreset.notebook),
    );
    cubit.redoStroke();
    expect(
      cubit.state.document.canvas.background,
      const CanvasBackground.preset(CanvasBackgroundPreset.blueprint),
    );
  });

  testWidgets('background panel exposes presets and applies custom hex color', (
    tester,
  ) async {
    CanvasBackground? changed;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: CanvasBackgroundPanel(
              value: const CanvasBackground.transparent(),
              onChanged: (value) => changed = value,
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('canvas-background-notebook')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('canvas-background-linen')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('canvas-background-blueprint')));
    expect(
      changed,
      const CanvasBackground.preset(CanvasBackgroundPreset.blueprint),
    );

    await tester.tap(find.byKey(const ValueKey('canvas-background-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('canvas-background-hex')),
      '12ABEF',
    );
    await tester.tap(
      find.byKey(const ValueKey('apply-canvas-background-color')),
    );
    await tester.pumpAndSettle();

    expect(changed, const CanvasBackground.solid(0xFF12ABEF));
    expect(tester.takeException(), isNull);
  });
}

Future<ui.Image> _renderBackground(
  CanvasBackground background,
  ui.Size size,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  const CanvasBackgroundRenderer().paint(
    canvas: canvas,
    rect: ui.Offset.zero & size,
    background: background,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  picture.dispose();
  return image;
}
