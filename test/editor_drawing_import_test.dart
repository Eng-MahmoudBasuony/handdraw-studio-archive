import 'support/legacy_editor_state_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart' hide Image;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_animation_guidance.dart';
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/raster_alpha_bounds_scanner.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_path_facade.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_session_coordinator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/editor/infrastructure/memory_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/koni_project_container_store.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_artwork_import.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_audio_service.dart';

void main() {
  test(
    'drawing import keeps the selected hand and its calibrated nib together',
    () async {
      final drawing = await _solidImage(const Color(0xFF2474E8));
      final cubit = EditorCubit(
        fileService: _FakeEditorFileService(
          () async => ImportedEditorAsset(
            path: '/tmp/manual-reveal-import.png',
            encoded: 'manual-reveal-import',
            image: drawing,
          ),
        ),
        initialState: testEditorState(
          project: HandDrawProject(
            handPresetId: BuiltInHands.defaultPresetId,
            penTip: BuiltInHands.wheatTechnicalPenRight.penTip,
          ),
          selectedHandPresetId: BuiltInHands.markerRight.id,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        drawing.dispose();
      });

      expect(await cubit.importDrawing(), DrawingImportResult.imported);
      expect(cubit.project.handPresetId, BuiltInHands.markerRight.id);
      expect(cubit.project.penTip, BuiltInHands.markerRight.penTip);
      expect(cubit.calibrationPenTip, BuiltInHands.markerRight.penTip);

      cubit.setTool(EditorTool.drawPath);
      expect(cubit.project.handPresetId, BuiltInHands.markerRight.id);
      expect(cubit.project.penTip, BuiltInHands.markerRight.penTip);
    },
  );

  test(
    'manual draw repairs an already-open cross-wired hand configuration',
    () {
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            handPresetId: BuiltInHands.defaultPresetId,
            penTip: BuiltInHands.wheatTechnicalPenRight.penTip,
          ),
          selectedHandPresetId: BuiltInHands.markerRight.id,
        ),
      );
      addTearDown(cubit.close);

      expect(cubit.calibrationPenTip, BuiltInHands.markerRight.penTip);
      cubit.setTool(EditorTool.drawPath);

      expect(cubit.project.handPresetId, BuiltInHands.markerRight.id);
      expect(cubit.project.penTip, BuiltInHands.markerRight.penTip);
    },
  );

  test('camera preview keeps imported static artwork visible', () async {
    final image = await _solidImage(const Color(0xFF2474E8));
    final state = testEditorState(
      project: HandDrawProject(
        drawingImagePath: '/tmp/static-camera.png',
        strokes: const [],
      ),
      drawingImage: image,
    );
    addTearDown(image.dispose);

    final renderedPixel = await _renderCanvasCenter(
      state,
      isPreviewing: true,
      cameraOutputPreview: true,
      resolvedFrame: ResolvedProjectFrame(
        time: TimelineTime.zero,
        drawing: null,
        camera: const ResolvedSingleCameraView(CameraView.identity()),
        activeAudio: const [],
        voiceGuide: null,
        markers: const [],
        isFinalFrame: false,
      ),
    );

    expect((renderedPixel.r * 255).round(), closeTo(0x24, 1));
    expect((renderedPixel.g * 255).round(), closeTo(0x74, 1));
    expect((renderedPixel.b * 255).round(), closeTo(0xE8, 1));
    expect((renderedPixel.a * 255).round(), 0xFF);
  });

  test(
    'camera preview shows only the background outside all artwork',
    () async {
      final image = await _solidImage(const Color(0xFF2474E8));
      final state = testEditorState(
        project: HandDrawProject(
          drawingImagePath: '/tmp/static-camera.png',
          strokes: const [],
        ),
        drawingImage: image,
      );
      addTearDown(image.dispose);

      final renderedPixel = await _renderCanvasCenter(
        state,
        isPreviewing: true,
        cameraOutputPreview: true,
        resolvedFrame: ResolvedProjectFrame(
          time: TimelineTime.zero,
          drawing: null,
          camera: const ResolvedSingleCameraView(
            CameraView(centerX: 4, centerY: 4, viewportWidth: .25),
          ),
          activeAudio: const [],
          voiceGuide: null,
          markers: const [],
          isFinalFrame: false,
        ),
      );

      expect(renderedPixel, const Color(0xFF111A2B));
    },
  );

  test(
    'clear removes artwork analysis and a scene camera clip atomically',
    () async {
      final image = await _solidImage(const Color(0xFF334455));
      final project = HandDrawProject(
        drawingImagePath: '/tmp/placed.png',
        strokes: [
          DrawingStroke(
            id: 'stroke-a',
            name: 'Artwork A',
            points: const [Offset(.1, .1), Offset(.9, .9)],
            sectionId: 'section-a',
          ),
        ],
        timelineSectionOrder: const ['section-a'],
        sceneGroups: [
          DrawingSceneGroup(
            id: 'scene-a',
            name: 'Scene A',
            sectionIds: const ['section-a'],
          ),
        ],
      );
      final baseState = testEditorState(project: project, drawingImage: image);
      final artworkHash = baseState.document.assets
          .singleWhere((asset) => asset.id == baseState.document.artworkAssetId)
          .contentHash;
      final cubit = EditorCubit(
        initialState: baseState.copyWith(
          documentState: EditorDocumentState(
            document: baseState.document.copyWith(
              pathProcessingMetadata: ProjectPathProcessingMetadata(
                engineId: 'handdraw-smart-path',
                algorithmVersion: 1,
                sourceAssetHash: artworkHash,
                suspectedFrameDetection: true,
                suspectedFrameConfidenceThreshold: 0.96,
              ),
            ),
          ),
        ),
      );
      addTearDown(() async {
        await cubit.close();
        image.dispose();
      });
      const bounds = DocumentRect(left: 0, top: 0, right: 1920, bottom: 1080);
      expect(
        cubit.setArtworkPlacement(
          const ProjectArtworkPlacement(
            encodedBounds: bounds,
            visibleBounds: bounds,
            destination: bounds,
          ),
        ),
        isTrue,
      );
      expect(cubit.ensureSceneCameraClip(SceneId('scene-a')), isTrue);
      expect(
        cubit.state.document.cameraTrack!.shots.single.ownerSceneId,
        SceneId('scene-a'),
      );

      expect(cubit.clearCanvas(), isTrue);
      expect(cubit.state.document.artworkAssetId, isNull);
      expect(cubit.state.document.artworkPlacement, isNull);
      expect(cubit.state.document.cameraTrack, isNull);
      expect(cubit.state.document.pathProcessingMetadata, isNull);
      expect(cubit.state.document.timeline.camera.enabled, isFalse);
      expect(cubit.state.document.strokes, isEmpty);
      expect(cubit.state.document.sections, isEmpty);

      cubit.restoreClearedCanvas();
      expect(cubit.state.document.artworkAssetId, isNotNull);
      expect(cubit.state.document.pathProcessingMetadata, isNotNull);
      expect(
        cubit.state.document.cameraTrack!.shots.single.ownerSceneId,
        SceneId('scene-a'),
      );
      expect(cubit.state.document.strokes, hasLength(1));
    },
  );

  testWidgets(
    'completed preview cannot hide a drawing imported after undo and clear',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final firstImage = await _solidImage(const Color(0xFF112233));
      final replacementImage = await _solidImage(const Color(0xFF33CCFF));
      final cubit = EditorCubit(
        fileService: _FakeEditorFileService(
          () async => ImportedEditorAsset(
            path: '/tmp/replacement-after-preview.png',
            encoded: 'replacement-after-preview',
            image: replacementImage,
          ),
        ),
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/original.png',
            drawingImageBase64: 'original',
          ),
          drawingImage: firstImage,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        firstImage.dispose();
        replacementImage.dispose();
      });
      cubit.setTool(EditorTool.drawPath);
      cubit.beginStroke(
        const Offset(10, 50),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
      cubit.updateStroke(
        const Offset(90, 50),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
      cubit.endStroke();

      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(
            cubit: cubit,
            writingAudioService: _CompletedPreviewAudioService(),
          ),
        ),
      );

      // Finish Preview and verify that its final timeline frame is retained.
      await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
      await tester.pump();
      // PlaybackClock, not the audio backend, owns completion.
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('canvas-preview-toggle')),
        findsOneWidget,
      );
      expect(_canvasPainter(tester).isPreviewing, isTrue);
      final completedPainter = _canvasPainter(tester);
      final completedFrame =
          completedPainter.resolvedFrameListenable?.value ??
          completedPainter.resolvedFrame;
      expect(completedFrame?.isFinalFrame, isTrue);

      // Match the reported sequence exactly: Command+Z to the last path,
      // Clear Canvas, then import another image.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(cubit.project.strokes, isEmpty);
      expect(_canvasPainter(tester).isPreviewing, isFalse);

      expect(cubit.clearCanvas(), isTrue);
      await tester.pump();
      expect(cubit.drawingImage, isNull);

      expect(await cubit.importDrawing(), DrawingImportResult.imported);
      await tester.pump();
      expect(cubit.drawingImage, same(replacementImage));
      final painter = _canvasPainter(tester);
      expect(painter.isPreviewing, isFalse);
      expect(painter.state.drawingImage, same(replacementImage));

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replaying a completed preview retains its visible snapshot until replacement',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final image = await _solidImage(const Color(0xFF294866));
      final staging = _DelayedSessionStagingStore();
      final cubit = EditorCubit(
        sessionCoordinator: EditorSessionCoordinator(
          staging: staging,
          containerStore: const KoniProjectContainerStore(),
          fingerprints: const CanonicalDocumentFingerprintCalculator(),
          projectIds: SecureRandomIdGenerator(),
        ),
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/replay.png',
            drawingImageBase64: 'replay',
            strokes: [
              DrawingStroke(
                id: 'replay-stroke',
                name: 'Replay stroke',
                points: [Offset(0.1, 0.5), Offset(0.9, 0.5)],
              ),
            ],
          ),
          drawingImage: image,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        image.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: EditorScreen(
            cubit: cubit,
            writingAudioService: _CompletedPreviewAudioService(),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('canvas-preview-toggle')),
        findsOneWidget,
      );
      final retainedImage = _canvasPainter(tester).state.drawingImage!;
      expect(retainedImage.debugDisposed, isFalse);

      final replacementGate = staging.delayNextSession();
      await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
      await tester.pump();

      expect(retainedImage.debugDisposed, isFalse);
      expect(tester.takeException(), isNull);

      replacementGate.complete();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('canvas-preview-stop')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  test(
    'undo all paths, clear, then import commits a fresh canvas session',
    () async {
      final firstImage = await _solidImage(const Color(0xFF112233));
      final importedImage = await _solidImage(const Color(0xFF33CCFF));
      final fileService = _FakeEditorFileService(
        () async => ImportedEditorAsset(
          path: '/tmp/replacement.png',
          encoded: 'replacement-bytes',
          image: importedImage,
        ),
      );
      final cubit = EditorCubit(
        fileService: fileService,
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/original.png',
            drawingImageBase64: 'original-bytes',
          ),
          drawingImage: firstImage,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        firstImage.dispose();
        importedImage.dispose();
      });
      cubit.setTool(EditorTool.drawPath);
      cubit.beginStroke(
        const Offset(10, 20),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
      cubit.updateStroke(
        const Offset(80, 20),
        const Rect.fromLTWH(0, 0, 100, 100),
      );
      cubit.endStroke();

      // Match the product flow exactly: undo all paths and leave redo history
      // populated before clearing the canvas and importing a replacement.
      cubit.undoStroke();
      expect(cubit.project.strokes, isEmpty);
      expect(cubit.clearCanvas(), isTrue);
      final clearedRevision = cubit.state.canvasRevision;

      final result = await cubit.importDrawing();

      expect(result, DrawingImportResult.imported);
      expect(cubit.drawingImage, same(importedImage));
      expect(
        cubit.state.document.assets.single.originalFileName,
        'replacement.png',
      );
      expect(cubit.state.drawingAnalysisEncoded, 'replacement-bytes');
      expect(cubit.project.strokes, isEmpty);
      expect(cubit.project.sectionTimings, isEmpty);
      expect(cubit.state.isDrawingImporting, isFalse);
      expect(cubit.state.canvasRevision, clearedRevision + 1);

      final renderedPixel = await _renderCanvasCenter(cubit.state);
      expect((renderedPixel.r * 255).round(), closeTo(0x33, 1));
      expect((renderedPixel.g * 255).round(), closeTo(0xCC, 1));
      expect((renderedPixel.b * 255).round(), closeTo(0xFF, 1));
      expect((renderedPixel.a * 255).round(), 0xFF);

      // A stale snackbar action or old keyboard history must not resurrect the
      // drawing and paths that belonged to the cleared canvas.
      cubit.restoreClearedCanvas();
      cubit.undoStroke();
      cubit.redoStroke();
      expect(cubit.drawingImage, same(importedImage));
      expect(
        cubit.state.document.assets.single.originalFileName,
        'replacement.png',
      );
      expect(cubit.project.strokes, isEmpty);
      expect(cubit.state.canvasRevision, clearedRevision + 1);
    },
  );

  test('import clears ordering drafts owned by the previous artwork', () async {
    final previousImage = await _solidImage(const Color(0xFF112233));
    final importedImage = await _solidImage(const Color(0xFF33CCFF));
    final initial =
        testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/previous.png',
            drawingImageBase64: 'previous',
          ),
          drawingImage: previousImage,
        ).copyWith(
          suggestionOrderCustomized: true,
          sceneDrafts: [
            EditorSceneDraft(
              id: 'previous-scene',
              name: 'Previous scene',
              sectionIds: const ['previous-section'],
            ),
          ],
          collapsedTimelineSceneIds: const {'previous-scene'},
        );
    final cubit = EditorCubit(
      fileService: _FakeEditorFileService(
        () async => ImportedEditorAsset(
          path: '/tmp/replacement.png',
          encoded: 'replacement',
          image: importedImage,
        ),
      ),
      initialState: initial,
    );
    addTearDown(() async {
      await cubit.close();
      previousImage.dispose();
      importedImage.dispose();
    });

    expect(await cubit.importDrawing(), DrawingImportResult.imported);

    expect(cubit.state.suggestionOrderCustomized, isFalse);
    expect(cubit.state.sceneDrafts, isEmpty);
    expect(cubit.state.collapsedTimelineSceneIds, isEmpty);
  });

  test(
    'SVG import stays neutral until Auto Path then applies immediately',
    () async {
      final importedImage = await _solidImage(const Color(0xFF33CCFF));
      final cubit = EditorCubit(
        fileService: _FakeEditorFileService(
          () async => ImportedEditorAsset(
            path: '/tmp/lesson.svg',
            encoded: 'rasterized-svg-preview',
            image: importedImage,
            sourceKind: ArtworkSourceKind.svg,
            vectorPaths: [
              SvgImportedPath(
                id: 'lesson-arrow',
                geometry: StrokePathGeometry(
                  start: const Offset(0.1, 0.5),
                  segments: const [
                    StrokeCubicSegment(
                      control1: Offset(0.3, 0.2),
                      control2: Offset(0.7, 0.8),
                      end: Offset(0.9, 0.5),
                    ),
                  ],
                ),
                animationGeometry: null,
                clipBounds: const Rect.fromLTWH(0.08, 0.18, 0.84, 0.64),
                recommendedRevealWidth: 0.02,
                isFilled: false,
                isText: false,
              ),
            ],
          ),
        ),
      );
      addTearDown(() async {
        await cubit.close();
        importedImage.dispose();
      });

      expect(await cubit.importDrawing(), DrawingImportResult.imported);

      expect(cubit.project.strokes, isEmpty);
      expect(cubit.project.drawingSourceKind, ArtworkSourceKind.svg);
      expect(cubit.tool, EditorTool.select);
      expect(cubit.statusMessage, contains('without animation'));

      await cubit.analyzeSmartPaths();

      expect(cubit.project.strokes, hasLength(1));
      expect(cubit.smartSections, isEmpty);
      expect(cubit.autoPathResult?.sectionCount, 1);
      expect(cubit.autoPathResult?.pathCount, 1);
      expect(cubit.autoPathResult?.nativeVectorCount, 1);
      final stroke = cubit.project.strokes.single;
      expect(stroke.name, 'lesson-arrow');
      expect(stroke.geometry, isNotNull);
      expect(stroke.isTextShape, isFalse);
      expect(stroke.revealWidth, closeTo(21.6, 0.0001));
      expect(cubit.statusMessage, contains('native SVG path'));
    },
  );

  test('raster Auto Path applies immediately through the same flow', () async {
    final image = await _solidImage(const Color(0xFF33CCFF));
    const section = SmartPathSection(
      id: 'raster-shape',
      kind: SmartSectionKind.shape,
      bounds: Rect.fromLTWH(0.1, 0.2, 0.8, 0.3),
      label: 'Raster shape',
      paths: [
        SmartGeneratedPath(points: [Offset(0.1, 0.35), Offset(0.9, 0.35)]),
      ],
      recommendedRevealWidth: 0.02,
      mode: SmartSectionMode.handDraw,
    );
    final cubit = EditorCubit(
      smartPathEngine: const _FixedSmartPathEngine(
        SmartPathAnalysis(sections: [section]),
      ),
      initialState: testEditorState(
        project: HandDrawProject(
          drawingImagePath: '/tmp/diagram.png',
          drawingImageBase64: base64Encode(const [1]),
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() async {
      await cubit.close();
      image.dispose();
    });

    await cubit.analyzeSmartPaths();

    expect(cubit.smartSections, isEmpty);
    expect(cubit.project.strokes, isNotEmpty);
    expect(cubit.autoPathResult?.sectionCount, 1);
    expect(cubit.autoPathResult?.handSectionCount, 1);
    expect(cubit.autoPathResult?.artworkSectionCount, 1);
    expect(cubit.autoPathResult?.nativeVectorCount, 0);
  });

  test('SVG filled shapes exclude native text until its own reveal', () async {
    final importedImage = await _solidImage(const Color(0xFF33CCFF));
    final textBounds = const Rect.fromLTWH(0.35, 0.42, 0.3, 0.16);
    final cubit = EditorCubit(
      fileService: _FakeEditorFileService(
        () async => ImportedEditorAsset(
          path: '/tmp/card.svg',
          encoded: 'rasterized-svg-preview',
          image: importedImage,
          sourceKind: ArtworkSourceKind.svg,
          vectorPaths: [
            SvgImportedPath(
              id: 'card',
              geometry: StrokePathGeometry(
                start: const Offset(0.2, 0.3),
                segments: const [
                  StrokeLineSegment(end: Offset(0.8, 0.3)),
                  StrokeLineSegment(end: Offset(0.8, 0.7)),
                  StrokeLineSegment(end: Offset(0.2, 0.7)),
                ],
                closed: true,
              ),
              animationGeometry: StrokePathGeometry(
                start: const Offset(0.2, 0.5),
                segments: const [StrokeLineSegment(end: Offset(0.8, 0.5))],
              ),
              clipBounds: const Rect.fromLTWH(0.2, 0.3, 0.6, 0.4),
              recommendedRevealWidth: 0.4,
              isFilled: true,
              isText: false,
            ),
            SvgImportedPath(
              id: 'label',
              geometry: StrokePathGeometry(
                start: const Offset(0.35, 0.5),
                segments: const [StrokeLineSegment(end: Offset(0.65, 0.5))],
              ),
              animationGeometry: null,
              clipBounds: textBounds,
              recommendedRevealWidth: 0.16,
              isFilled: false,
              isText: true,
            ),
          ],
        ),
      ),
    );
    addTearDown(() async {
      await cubit.close();
      importedImage.dispose();
    });

    expect(await cubit.importDrawing(), DrawingImportResult.imported);

    expect(cubit.project.strokes, isEmpty);
    await cubit.analyzeSmartPaths(autoApply: false);
    expect(cubit.project.strokes, isEmpty);
    await cubit.applySmartPathSuggestions();

    final card = cubit.project.strokes.firstWhere(
      (stroke) => stroke.name == 'card',
    );
    final label = cubit.project.strokes.firstWhere(
      (stroke) => stroke.name == 'label',
    );
    expect(card.animationGeometry, isNotNull);
    expect(card.exclusionBounds.single, textBounds.inflate(0.001));
    expect(label.isTextShape, isTrue);
    expect(label.revealStyle, RevealMaskStyle.directionalWipe);
  });

  test(
    'applying a precise SVG text trace replaces only its legacy baseline',
    () async {
      final image = await _solidImage(const Color(0x00000000));
      final nativeText = SvgImportedPath(
        id: 'label',
        geometry: StrokePathGeometry(
          start: const Offset(0.2, 0.5),
          segments: const [StrokeLineSegment(end: Offset(0.8, 0.5))],
        ),
        animationGeometry: null,
        clipBounds: const Rect.fromLTWH(0.18, 0.35, 0.64, 0.3),
        recommendedRevealWidth: 0.08,
        isFilled: false,
        isText: true,
      );
      const section = SmartPathSection(
        id: 'svg-edit:svg-label-0',
        kind: SmartSectionKind.text,
        bounds: Rect.fromLTWH(0.18, 0.35, 0.64, 0.3),
        label: 'label',
        paths: [
          SmartGeneratedPath(
            points: [
              Offset(0.22, 0.58),
              Offset(0.25, 0.39),
              Offset(0.29, 0.58),
            ],
          ),
          SmartGeneratedPath(
            points: [
              Offset(0.34, 0.40),
              Offset(0.34, 0.58),
              Offset(0.42, 0.58),
            ],
          ),
        ],
        recommendedRevealWidth: 0.025,
        mode: SmartSectionMode.handDraw,
        hasPreciseTrace: true,
      );
      final cubit = EditorCubit(
        artworkPathFacade: _FixedArtworkPathFacade(
          ArtworkPathResult(
            analysis: const SmartPathAnalysis(sections: [section]),
            nativePaths: [nativeText],
          ),
        ),
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImageBase64: base64Encode(const [1]),
            drawingSourceKind: ArtworkSourceKind.svg,
            drawingSourceBase64: base64Encode(const [1]),
          ),
          drawingImage: image,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        image.dispose();
      });

      await cubit.analyzeSmartPaths(autoApply: false);
      await cubit.applySmartPathSuggestions();

      final writing = cubit.project.strokes
          .where((stroke) => !stroke.revealOnly)
          .toList(growable: false);
      expect(writing, hasLength(2));
      expect(cubit.project.strokes, hasLength(3));
      expect(
        writing.every(
          (stroke) => stroke.clipBounds == section.bounds.inflate(0.002),
        ),
        isTrue,
        reason:
            'Precise SVG text must keep the generated glyph clip instead of '
            'restoring the broader legacy text box.',
      );
      expect(cubit.project.strokes.every((stroke) => stroke.isTextShape), true);
      expect(
        writing.every(
          (stroke) =>
              stroke.orderedPoints.map((point) => point.dy).toSet().length > 1,
        ),
        true,
      );
      expect(
        cubit.project.strokes.every(
          (stroke) => stroke.sectionId == 'svg:label',
        ),
        true,
      );
    },
  );

  test(
    'applying a precise thin fill trace keeps vector fill reveal semantics',
    () async {
      final image = await _solidImage(const Color(0x00000000));
      final nativeFill = SvgImportedPath(
        id: 'bracket',
        geometry: StrokePathGeometry(
          start: const Offset(0.1, 0.1),
          segments: const [
            StrokeLineSegment(end: Offset(0.8, 0.1)),
            StrokeLineSegment(end: Offset(0.8, 0.24)),
            StrokeLineSegment(end: Offset(0.24, 0.24)),
            StrokeLineSegment(end: Offset(0.24, 0.8)),
            StrokeLineSegment(end: Offset(0.1, 0.8)),
          ],
          closed: true,
        ),
        animationGeometry: StrokePathGeometry(
          start: const Offset(0.1, 0.45),
          segments: const [StrokeLineSegment(end: Offset(0.8, 0.45))],
        ),
        clipBounds: const Rect.fromLTWH(0.09, 0.09, 0.72, 0.72),
        recommendedRevealWidth: 0.14,
        isFilled: true,
        isText: false,
        fillColorValue: 0xFF2874ED,
      );
      const section = SmartPathSection(
        id: 'svg-edit:svg-bracket-0',
        kind: SmartSectionKind.shape,
        bounds: Rect.fromLTWH(0.1, 0.1, 0.7, 0.7),
        label: 'bracket',
        paths: [
          SmartGeneratedPath(
            points: [
              Offset(0.17, 0.72),
              Offset(0.17, 0.17),
              Offset(0.72, 0.17),
            ],
          ),
        ],
        recommendedRevealWidth: 0.14,
        mode: SmartSectionMode.handDraw,
        hasPreciseTrace: true,
      );
      final cubit = EditorCubit(
        artworkPathFacade: _FixedArtworkPathFacade(
          ArtworkPathResult(
            analysis: const SmartPathAnalysis(sections: [section]),
            nativePaths: [nativeFill],
          ),
        ),
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImageBase64: base64Encode(const [1]),
            drawingSourceKind: ArtworkSourceKind.svg,
            drawingSourceBase64: base64Encode(const [1]),
          ),
          drawingImage: image,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        image.dispose();
      });

      await cubit.analyzeSmartPaths(autoApply: false);
      await cubit.applySmartPathSuggestions();

      final strokes = cubit.project.strokes;
      expect(strokes, isNotEmpty);
      expect(strokes.every((stroke) => stroke.isFilledShape), isTrue);
      expect(
        strokes.every((stroke) => stroke.revealStyle == RevealMaskStyle.brush),
        isTrue,
      );
      expect(
        strokes.every((stroke) => stroke.fillColorValue == 0xFF2874ED),
        true,
      );
      expect(
        strokes
            .expand((stroke) => stroke.orderedPoints)
            .map((point) => point.dy)
            .toSet()
            .length,
        greaterThan(1),
      );
    },
  );

  test('saved SVG source rebuilds native paths after reopening', () async {
    final image = await _solidImage(const Color(0xFF33CCFF));
    final source = utf8.encode('''
      <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
        <path id="native-line" fill="none" stroke="#111"
          d="M 10 50 L 90 50" />
      </svg>
    ''');
    final cubit = EditorCubit(
      smartPathEngine: const _FixedSmartPathEngine(
        SmartPathAnalysis(sections: []),
      ),
      initialState: testEditorState(
        project: HandDrawProject(
          drawingImagePath: '/tmp/reopened.svg',
          drawingImageBase64: base64Encode(const [1]),
          drawingSourceKind: ArtworkSourceKind.svg,
          drawingSourceBase64: base64Encode(source),
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() async {
      await cubit.close();
      image.dispose();
    });

    await cubit.analyzeSmartPaths(autoApply: false);

    expect(cubit.project.strokes, isEmpty);
    expect(cubit.smartSections, hasLength(1));
    expect(cubit.smartSections.single.label, 'native-line');
    await cubit.applySmartPathSuggestions();
    expect(cubit.project.strokes.single.geometry, isNotNull);
  });

  test('a cleared canvas wins over an older import still decoding', () async {
    final originalImage = await _solidImage(const Color(0xFF223344));
    final staleImage = await _solidImage(const Color(0xFFFFAA00));
    final pendingAsset = Completer<ImportedEditorAsset?>();
    final cubit = EditorCubit(
      fileService: _FakeEditorFileService(() => pendingAsset.future),
      initialState: testEditorState(
        project: HandDrawProject(
          drawingImagePath: '/tmp/original.png',
          drawingImageBase64: 'original-bytes',
        ),
        drawingImage: originalImage,
      ),
    );
    addTearDown(() async {
      await cubit.close();
      originalImage.dispose();
    });

    final import = cubit.importDrawing();
    expect(cubit.state.isDrawingImporting, isTrue);
    expect(cubit.clearCanvas(), isTrue);
    pendingAsset.complete(
      ImportedEditorAsset(
        path: '/tmp/stale.png',
        encoded: 'stale-bytes',
        image: staleImage,
      ),
    );

    expect(await import, DrawingImportResult.superseded);
    expect(cubit.drawingImage, isNull);
    expect(cubit.project.drawingImagePath, isNull);
    expect(cubit.state.isDrawingImporting, isFalse);
  });

  test(
    'repeated import requests keep one picker and preserve its selection',
    () async {
      final selectedImage = await _solidImage(const Color(0xFF55CCAA));
      final pendingAsset = Completer<ImportedEditorAsset?>();
      var pickerCalls = 0;
      final cubit = EditorCubit(
        fileService: _FakeEditorFileService(() {
          pickerCalls++;
          return pendingAsset.future;
        }),
      );
      addTearDown(() async {
        await cubit.close();
        selectedImage.dispose();
      });

      final firstImport = cubit.importDrawing();
      expect(cubit.state.isDrawingImporting, isTrue);

      expect(
        await cubit.importDrawing(),
        DrawingImportResult.alreadyInProgress,
      );
      expect(pickerCalls, 1);
      expect(cubit.state.isDrawingImporting, isTrue);

      pendingAsset.complete(
        ImportedEditorAsset(
          path: '/tmp/only-picker-selection.png',
          encoded: 'only-picker-selection',
          image: selectedImage,
        ),
      );

      expect(await firstImport, DrawingImportResult.imported);
      expect(cubit.drawingImage, same(selectedImage));
      expect(
        cubit.state.document.assets.single.originalFileName,
        'only-picker-selection.png',
      );
      expect(cubit.state.isDrawingImporting, isFalse);
    },
  );

  test(
    'an old Auto Path analysis cannot mutate a replacement canvas',
    () async {
      final originalImage = await _solidImage(const Color(0xFF334455));
      final importedImage = await _solidImage(const Color(0xFF44DDEE));
      final analysisCompleter = Completer<SmartPathAnalysis>();
      final cubit = EditorCubit(
        smartPathEngine: _DelayedSmartPathEngine(analysisCompleter),
        fileService: _FakeEditorFileService(
          () async => ImportedEditorAsset(
            path: '/tmp/fresh.png',
            encoded: 'fresh-bytes',
            image: importedImage,
          ),
        ),
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/original.png',
            drawingImageBase64: 'b3JpZ2luYWw=',
          ),
          drawingImage: originalImage,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        originalImage.dispose();
        importedImage.dispose();
      });

      final staleAnalysis = cubit.analyzeSmartPaths(autoApply: false);
      expect(cubit.state.isAnalyzingSmartPaths, isTrue);
      expect(cubit.clearCanvas(), isTrue);
      expect(await cubit.importDrawing(), DrawingImportResult.imported);

      analysisCompleter.complete(const SmartPathAnalysis(sections: []));
      await staleAnalysis;

      expect(cubit.drawingImage, same(importedImage));
      expect(cubit.state.document.assets.single.originalFileName, 'fresh.png');
      expect(cubit.smartSections, isEmpty);
      expect(cubit.state.isAnalyzingSmartPaths, isFalse);
    },
  );

  test(
    'failed import keeps the current canvas and reports the error',
    () async {
      final image = await _solidImage(const Color(0xFF445566));
      final cubit = EditorCubit(
        fileService: _FakeEditorFileService(
          () async => throw const FormatException('invalid image'),
        ),
        initialState: testEditorState(
          project: HandDrawProject(drawingImagePath: '/tmp/current.png'),
          drawingImage: image,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        image.dispose();
      });

      expect(await cubit.importDrawing(), DrawingImportResult.failed);
      expect(cubit.drawingImage, same(image));
      expect(cubit.project.drawingImagePath, '/tmp/current.png');
      expect(cubit.statusMessage, contains('Could not import drawing'));
      expect(cubit.state.isDrawingImporting, isFalse);
    },
  );

  test('canceling the picker restores the previous editor status', () async {
    final cubit = EditorCubit(
      fileService: const _FakeEditorFileService(_cancelDrawingImport),
      initialState: EditorState.initial().copyWith(
        statusMessage: 'Ready before picker',
      ),
    );
    addTearDown(cubit.close);

    expect(await cubit.importDrawing(), DrawingImportResult.canceled);
    expect(cubit.statusMessage, 'Ready before picker');
    expect(cubit.state.isDrawingImporting, isFalse);
  });

  test('import stores the background-image animation guidance', () async {
    final image = await _solidImage(const Color(0xFF2474E8));
    final cubit = EditorCubit(
      fileService: _FakeEditorFileService(
        () async => ImportedEditorAsset(
          path: '/tmp/full-background.png',
          encoded: 'full-background',
          image: image,
          rasterAlphaBounds: const RasterAlphaBoundsResult(
            contentHash: 'sha256:test-background',
            status: RasterAlphaBoundsStatus.opaque,
            bounds: RasterPixelBounds(0, 0, 16, 16),
            pixelProfile: RasterPixelProfile(
              visiblePixelCount: 256,
              nearWhiteNeutralPixelCount: 0,
              colorfulPixelCount: 256,
            ),
          ),
        ),
      ),
    );
    addTearDown(() async {
      await cubit.close();
      image.dispose();
    });

    expect(await cubit.importDrawing(), DrawingImportResult.imported);
    expect(
      cubit.state.artworkAnimationGuidance,
      ArtworkAnimationGuidance.autoRevealRecommended,
    );
  });
}

EditorCanvasPainter _canvasPainter(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is EditorCanvasPainter,
    ),
  );
  return paint.painter! as EditorCanvasPainter;
}

Future<ImportedEditorAsset?> _cancelDrawingImport() async => null;

class _FakeEditorFileService extends EditorFileService {
  const _FakeEditorFileService(this.onPickDrawing);

  final Future<ImportedEditorAsset?> Function() onPickDrawing;

  @override
  Future<ImportedEditorAsset?> pickDrawing({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) => onPickDrawing();
}

class _DelayedSmartPathEngine extends SmartPathEngine {
  const _DelayedSmartPathEngine(this.result);

  final Completer<SmartPathAnalysis> result;

  @override
  Future<SmartPathAnalysis> analyze({
    required Image image,
    required Uint8List encodedImage,
    SmartPathProgressCallback? onProgress,
    SmartPathCancellationToken? cancellationToken,
    Rect coordinateBounds = const Rect.fromLTWH(0, 0, 1, 1),
  }) => result.future;
}

class _FixedSmartPathEngine extends SmartPathEngine {
  const _FixedSmartPathEngine(this.analysis);

  final SmartPathAnalysis analysis;

  @override
  Future<SmartPathAnalysis> analyze({
    required Image image,
    required Uint8List encodedImage,
    SmartPathProgressCallback? onProgress,
    SmartPathCancellationToken? cancellationToken,
    Rect coordinateBounds = const Rect.fromLTWH(0, 0, 1, 1),
  }) async => analysis;
}

class _FixedArtworkPathFacade implements ArtworkPathFacade {
  const _FixedArtworkPathFacade(this.result);

  final ArtworkPathResult result;

  @override
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request) async => result;
}

class _CompletedPreviewAudioService extends WritingAudioService {
  @override
  Future<void> play(
    HandDrawProject project, {
    VoiceGuide? voiceGuide,
    double positionSeconds = 0,
    double? previewDurationSeconds,
    double volume = 1,
  }) async {}

  @override
  Future<double> position() async => 99;

  @override
  Future<void> stop() async {}
}

class _DelayedSessionStagingStore implements EditorAssetStagingStore {
  final MemoryEditorAssetStagingStore _delegate =
      MemoryEditorAssetStagingStore();
  Completer<void>? _nextSessionGate;

  Completer<void> delayNextSession() {
    final gate = Completer<void>();
    _nextSessionGate = gate;
    return gate;
  }

  @override
  Future<void> createSession(EditorSessionId sessionId) async {
    final gate = _nextSessionGate;
    _nextSessionGate = null;
    if (gate != null) await gate.future;
    await _delegate.createSession(sessionId);
  }

  @override
  Future<void> stageEmbedded(StageEmbeddedAssetRequest request) =>
      _delegate.stageEmbedded(request);

  @override
  Future<void> registerExternal(RegisterExternalAssetRequest request) =>
      _delegate.registerExternal(request);

  @override
  Future<StagedAssetLease> acquire({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  }) => _delegate.acquire(sessionId: sessionId, assetId: assetId, kind: kind);

  @override
  Future<StagedAssetLease> acquireVerifiedSnapshot({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
    AssetSnapshotCancellation cancellation = const NeverCancelAssetSnapshot(),
  }) => _delegate.acquireVerifiedSnapshot(
    sessionId: sessionId,
    assetId: assetId,
    kind: kind,
    cancellation: cancellation,
  );

  @override
  void retain({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  }) => _delegate.retain(sessionId: sessionId, assetId: assetId, kind: kind);

  @override
  void releaseReference({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  }) => _delegate.releaseReference(
    sessionId: sessionId,
    assetId: assetId,
    kind: kind,
  );

  @override
  Future<void> disposeSession(EditorSessionId sessionId) =>
      _delegate.disposeSession(sessionId);

  @override
  Future<int> cleanupStaleSessions() => _delegate.cleanupStaleSessions();
}

Future<Image> _solidImage(Color color) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(16, 16);
  picture.dispose();
  return image;
}

Future<Color> _renderCanvasCenter(
  EditorState state, {
  bool isPreviewing = false,
  bool cameraOutputPreview = false,
  ResolvedProjectFrame? resolvedFrame,
}) async {
  const size = Size(320, 180);
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder);
  EditorCanvasPainter(
    state: state,
    project: testLegacyProject(state),
    previewProgress: 0,
    isPreviewing: isPreviewing,
    cameraOutputPreview: cameraOutputPreview,
    resolvedFrame: resolvedFrame,
    interfaceTextDirection: TextDirection.ltr,
    emptyStateLabel: 'Import a drawing to start',
    handModeLabel: 'Hand',
    revealModeLabel: 'Reveal',
    ignoreModeLabel: 'Ignore',
    pathsLabel: 'Paths',
    colors: AppPalette.dark,
  ).paint(canvas, size);
  final picture = recorder.endRecording();
  final rendered = await picture.toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  picture.dispose();
  final bytes = await rendered.toByteData(format: ImageByteFormat.rawRgba);
  rendered.dispose();
  final offset =
      ((size.height ~/ 2) * size.width.toInt() + size.width ~/ 2) * 4;
  final rgba = bytes!.buffer.asUint8List();
  return Color.fromARGB(
    rgba[offset + 3],
    rgba[offset],
    rgba[offset + 1],
    rgba[offset + 2],
  );
}
