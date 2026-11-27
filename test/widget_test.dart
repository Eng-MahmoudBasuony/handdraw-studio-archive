import 'dart:convert';
import 'support/legacy_editor_state_fixture.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/app_info/domain/app_build_info.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_animation_guidance.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/editor/domain/auto_path_result_summary.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_audio_service.dart';
import 'package:handdraw_studio/main.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_timeline_dock.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_library_repository.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';

void main() {
  testWidgets('shows the HandDraw Studio editor', (tester) async {
    _setWindowSize(tester, const Size(1366, 900));
    await tester.pumpWidget(const HandDrawStudioApp());

    expect(find.text('HandDraw Studio'), findsOneWidget);
    expect(find.text('Drawing'), findsWidgets);
    expect(find.text('Draw Path'), findsNothing);
    expect(find.text('Auto Reveal'), findsNothing);
    expect(find.text('Animate image'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('canvas-player-controls')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('camera-view-control-dock')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('camera-editor-view-gesture-surface')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('editor-preview')), findsNothing);
  });

  testWidgets('uses a docked one-row workspace on wide windows', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1800, 1000));
    await tester.pumpWidget(const HandDrawStudioApp());

    expect(find.byKey(const ValueKey('editor-layout-wide')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-toolbar-one-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-inspector-docked')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows Auto Path stage, percentage, and estimated time left', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(),
        isAnalyzingSmartPaths: true,
        smartPathProgress: const SmartPathProgress(
          stage: SmartPathProgressStage.tracingShapes,
          fraction: 0.5,
        ),
        smartPathAnalysisElapsed: const Duration(seconds: 4),
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    expect(
      find.byKey(const ValueKey('smart-path-analysis-progress')),
      findsOneWidget,
    );
    expect(find.text('Tracing artwork paths'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('4s elapsed • about 4s left'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not show a misleading ETA during path validation', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(),
        isAnalyzingSmartPaths: true,
        smartPathProgress: const SmartPathProgress(
          stage: SmartPathProgressStage.validatingPaths,
          fraction: 0.94,
        ),
        smartPathAnalysisElapsed: const Duration(seconds: 12),
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    expect(find.text('Checking path coverage'), findsOneWidget);
    expect(find.text('94%'), findsOneWidget);
    expect(find.text('12s elapsed • estimating time left'), findsOneWidget);
    expect(find.textContaining('about'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('workspace preserves the selected portrait video ratio', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1500, 1000));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(canvasWidth: 1080, canvasHeight: 1920),
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    final frame = tester.getRect(
      find.byKey(const ValueKey('project-video-aspect-ratio')),
    );
    expect(frame.width / frame.height, closeTo(1080 / 1920, .001));
    expect(frame.height, greaterThan(frame.width));
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses a clean two-row toolbar on compact desktop windows', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    await tester.pumpWidget(const HandDrawStudioApp());

    expect(find.byKey(const ValueKey('editor-layout-compact')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-toolbar-two-row')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-inspector-docked')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('inspector groups every settings area into section cards', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 1000));
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    expect(
      find.byKey(const ValueKey('inspector-section-project-summary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inspector-section-project-timing')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('inspector-section-project-export')),
      findsOneWidget,
    );

    await _openInspectorTab(tester, 'HAND');
    expect(
      find.byKey(const ValueKey('inspector-section-hand-settings')),
      findsOneWidget,
    );

    await _openInspectorTab(tester, 'Audio');
    expect(
      find.byKey(const ValueKey('inspector-section-writing-sound')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inspector-section-voice-guide')),
      findsOneWidget,
    );

    await _openInspectorTab(tester, 'Animation');
    expect(
      find.byKey(const ValueKey('inspector-section-animation-timing')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inspector-section-strokes')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'empty project makes unavailable editor actions visibly disabled',
    (tester) async {
      _setWindowSize(tester, const Size(1366, 1000));
      final cubit = EditorCubit();
      addTearDown(cubit.close);
      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('canvas-preview-toggle')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('editor-export')))
            .onPressed,
        isNull,
      );

      final exportCard = find.byKey(
        const ValueKey('inspector-section-project-export'),
      );
      await tester.scrollUntilVisible(
        exportCard,
        260,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('editor-inspector-scroll-view')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: exportCard,
          matching: find.byKey(const ValueKey('inspector-disabled-notice')),
        ),
        findsOneWidget,
      );
      final exportDropdowns = tester
          .widgetList<DropdownButtonFormField<dynamic>>(
            find.descendant(
              of: exportCard,
              matching: find.byWidgetPredicate(
                (widget) => widget is DropdownButtonFormField,
              ),
            ),
          );
      expect(exportDropdowns, hasLength(4));
      expect(
        exportDropdowns.every((dropdown) => dropdown.onChanged == null),
        isTrue,
      );

      await _openInspectorTab(tester, 'Animation');
      final timingCard = find.byKey(
        const ValueKey('inspector-section-animation-timing'),
      );
      expect(
        find.descendant(
          of: timingCard,
          matching: find.byKey(const ValueKey('inspector-disabled-notice')),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<Slider>(
              find.descendant(of: timingCard, matching: find.byType(Slider)),
            )
            .every((slider) => slider.onChanged == null),
        isTrue,
      );

      expect(find.byKey(const ValueKey('toolbar-select-tool')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('animate-image')))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('toolbar-add-camera-shot')),
            )
            .onPressed,
        isNull,
      );

      await _openInspectorTab(tester, 'HAND');
      final handCard = find.byKey(
        const ValueKey('inspector-section-hand-settings'),
      );
      expect(
        find.descendant(
          of: handCard,
          matching: find.byKey(const ValueKey('inspector-disabled-notice')),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widgetList<Slider>(
              find.descendant(of: handCard, matching: find.byType(Slider)),
            )
            .every((slider) => slider.onChanged == null),
        isTrue,
      );
      expect(
        tester
            .widgetList<FilledButton>(
              find.descendant(
                of: handCard,
                matching: find.byType(FilledButton),
              ),
            )
            .single
            .onPressed,
        isNotNull,
        reason: 'Choosing a hand remains the useful next action.',
      );

      await _openInspectorTab(tester, 'Audio');
      final writingSoundCard = find.byKey(
        const ValueKey('inspector-section-writing-sound'),
      );
      expect(
        find.descendant(
          of: writingSoundCard,
          matching: find.byKey(const ValueKey('inspector-disabled-notice')),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'one animation entry replaces old tools and preserves project edits',
    (tester) async {
      _setWindowSize(tester, const Size(1366, 900));
      final image = await _solidImage();
      final encoded = await tester.runAsync(
        () async => base64Encode(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        ),
      );
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/existing.png',
            revealWidth: 72,
            strokes: [
              DrawingStroke(
                id: 'authored',
                name: 'Authored',
                reversed: true,
                points: const [Offset(.1, .2), Offset(.7, .2)],
              ),
            ],
          ),
          drawingImage: image,
        ).copyWith(drawingAnalysisEncoded: encoded),
      );
      final before = cubit.project.toJson();
      addTearDown(() async {
        await cubit.close();
        image.dispose();
      });
      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
      expect(find.byKey(const ValueKey('toolbar-select-tool')), findsNothing);
      expect(
        find.byKey(const ValueKey('manual-reveal-width-control')),
        findsNothing,
      );
      expect(find.text('Auto Path'), findsNothing);
      expect(find.text('Auto Reveal'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('animate-image')));
      await tester.pumpAndSettle();
      expect(find.text('Animate image'), findsWidgets);
      expect(find.byKey(const ValueKey('animation-effect')), findsOneWidget);
      expect(find.text('Prepare'), findsNothing);
      expect(
        find.byKey(const ValueKey('canvas-player-controls')),
        findsOneWidget,
      );
      await _openInspectorTab(tester, 'HAND');
      expect(cubit.project.toJson(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'full-background artwork uses the same animation entry without legacy prompts',
    (tester) async {
      _setWindowSize(tester, const Size(1366, 900));
      final image = await _solidImage();
      final encoded = await tester.runAsync(
        () async => base64Encode(
          (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!.buffer.asUint8List(),
        ),
      );
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(drawingImagePath: '/tmp/background.png'),
          drawingImage: image,
          artworkAnimationGuidance:
              ArtworkAnimationGuidance.autoRevealRecommended,
        ).copyWith(drawingAnalysisEncoded: encoded),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });
      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

      expect(find.text('Auto Path'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('animate-image')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('animation-effect')), findsOneWidget);
      expect(
        find.text('Auto Path isn’t suitable for this image'),
        findsNothing,
      );
      expect(cubit.state.isAnalyzingSmartPaths, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ready project enables preview export and contextual settings', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 1000));
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        drawingImage: image,
        project: HandDrawProject(
          drawingImagePath: '/tmp/ready.png',
          strokes: [
            DrawingStroke(
              id: 'ready-path',
              name: 'Ready path',
              points: const [Offset(0.2, 0.5), Offset(0.8, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('canvas-preview-toggle')),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('editor-export')))
          .onPressed,
      isNotNull,
    );
    final addCamera = find.byKey(const ValueKey('toolbar-add-camera-shot'));
    expect(tester.widget<FilledButton>(addCamera).onPressed, isNotNull);
    await tester.tap(addCamera);
    await tester.pumpAndSettle();
    expect(cubit.state.document.cameraTrack?.shots, hasLength(1));
    expect(
      find.byKey(const ValueKey('camera-editor-view-gesture-surface')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inspector-section-project-timing')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom export preset exposes validated pixel dimensions', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 1000));
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        drawingImage: image,
        project: HandDrawProject(
          drawingImagePath: '/tmp/custom-export.png',
          exportPresetId: ExportPresetId.custom,
          strokes: [
            DrawingStroke(
              id: 'custom-export-path',
              name: 'Custom export path',
              points: const [Offset(0.2, 0.5), Offset(0.8, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    final widthField = find.byKey(const ValueKey('custom-export-width'));
    await tester.scrollUntilVisible(
      widthField,
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('editor-inspector-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.enterText(widthField, '2560');
    await tester.enterText(
      find.byKey(const ValueKey('custom-export-height')),
      '1440',
    );
    expect(find.text('px'), findsNWidgets(2));
    await tester.tap(
      find.byKey(const ValueKey('apply-custom-export-resolution')),
    );
    await tester.pumpAndSettle();

    expect(cubit.project.canvasWidth, 2560);
    expect(cubit.project.canvasHeight, 1440);
    expect(cubit.project.exportPresetId, ExportPresetId.custom);
    expect(tester.takeException(), isNull);
  });

  testWidgets('project artwork controls stay compact and preserve precision', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        drawingImage: image,
        project: HandDrawProject(drawingImagePath: '/tmp/artwork.png'),
      ),
    );
    cubit.setArtworkPlacement(
      const ProjectArtworkPlacement(
        encodedBounds: DocumentRect(left: 0, top: 0, right: 1920, bottom: 1080),
        visibleBounds: DocumentRect(
          left: 120,
          top: 80,
          right: 1800,
          bottom: 1000,
        ),
        destination: DocumentRect(left: 0, top: 0, right: 1920, bottom: 1080),
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    expect(
      find.byKey(const ValueKey('artwork-intent-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inspector-section-project-timing')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('inspector-section-project-summary')),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('artwork-X-0.00')), findsNothing);

    await tester.tap(find.text('Position and size'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('artwork-X-0.00')), findsOneWidget);
    expect(find.byKey(const ValueKey('artwork-W-1920.00')), findsOneWidget);

    await tester.tap(find.text('Element'));
    await tester.pumpAndSettle();
    expect(cubit.artworkPlacement!.importIntent, ArtworkImportIntent.element);

    final exportCard = find.byKey(
      const ValueKey('inspector-section-project-export'),
    );
    await tester.scrollUntilVisible(
      exportCard,
      260,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('editor-inspector-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(exportCard, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale stroke selection cannot crash an empty inspector', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final cubit = EditorCubit(
      initialState: EditorState.initial().copyWith(selectedStrokeIndex: 0),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.pump();

    expect(cubit.project.strokes, isEmpty);
    expect(cubit.selectedStroke, isNull);
    expect(
      find.byKey(const ValueKey('editor-inspector-docked')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selecting an auto path section opens Animation guidance every time',
    (tester) async {
      _setWindowSize(tester, const Size(1366, 900));
      final image = await _solidImage();
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(drawingImagePath: '/tmp/section.png'),
          drawingImage: image,
          smartSections: const [
            SmartPathSection(
              id: 'center-section',
              kind: SmartSectionKind.shape,
              bounds: Rect.fromLTWH(0.35, 0.35, 0.3, 0.3),
              label: 'Artwork 1',
              paths: [
                SmartGeneratedPath(
                  points: [Offset(0.4, 0.5), Offset(0.6, 0.5)],
                ),
              ],
              recommendedRevealWidth: 54,
              mode: SmartSectionMode.handDraw,
            ),
          ],
        ),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });

      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
      expect(
        find.byKey(const ValueKey('inspector-section-project-summary')),
        findsOneWidget,
      );

      // Auto Path analysis selects its first result programmatically.
      cubit.selectSmartSection('center-section');
      await tester.pumpAndSettle();
      expect(cubit.state.selectedSmartSectionId, 'center-section');
      expect(
        find.byKey(const ValueKey('inspector-section-animation-timing')),
        findsOneWidget,
      );

      await _openInspectorTab(tester, 'PROJECT');
      expect(
        find.byKey(const ValueKey('inspector-section-project-summary')),
        findsOneWidget,
      );

      await tester.tapAt(tester.getCenter(find.byType(EditorCanvas)));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('inspector-section-animation-timing')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Scene Planner enters enclosure mode without toolbar overflow', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingImagePath: '/tmp/scene.png'),
        drawingImage: image,
        smartSections: const [
          SmartPathSection(
            id: 'scene-section',
            kind: SmartSectionKind.shape,
            bounds: Rect.fromLTWH(0.2, 0.2, 0.3, 0.3),
            label: 'Scene artwork',
            paths: [
              SmartGeneratedPath(points: [Offset(0.2, 0.2), Offset(0.5, 0.5)]),
            ],
            recommendedRevealWidth: 0.01,
            mode: SmartSectionMode.handDraw,
          ),
        ],
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    await _openInspectorTab(tester, 'Animation');
    final button = find.byKey(const ValueKey('draw-scene-group'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(cubit.tool, EditorTool.sceneGroup);
    expect(find.text('Smart Timeline'), findsWidgets);
    expect(
      find.byKey(const ValueKey('auto-arrange-timeline-dock')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('editor-timeline-dock')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'bottom timeline stays horizontal and responsive on narrow canvas',
    (tester) async {
      _setWindowSize(tester, const Size(700, 680));
      final image = await _solidImage();
      final sections = [
        for (var index = 0; index < 8; index++)
          SmartPathSection(
            id: 'clip-$index',
            kind: SmartSectionKind.shape,
            bounds: Rect.fromLTWH(index * 0.1, 0.2, 0.08, 0.12),
            label: 'Clip $index',
            paths: [
              SmartGeneratedPath(
                points: [
                  Offset(index * 0.1, 0.2),
                  Offset(index * 0.1 + 0.07, 0.3),
                ],
              ),
            ],
            recommendedRevealWidth: 0.01,
            mode: SmartSectionMode.handDraw,
          ),
      ];
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/timeline.png',
            timelineSectionOrder: [for (final section in sections) section.id],
          ),
          drawingImage: image,
          smartSections: sections,
        ),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });

      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('editor-timeline-dock')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('timeline-ruler')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('timeline-thumbnail-clip-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('timeline-time-clip-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('timeline-thumbnail-clip-7')),
        findsOneWidget,
      );

      final firstClip = find.byKey(const ValueKey('timeline-thumbnail-clip-0'));
      final thirdClip = find.byKey(const ValueKey('timeline-thumbnail-clip-2'));
      await tester.dragFrom(
        tester.getCenter(firstClip),
        tester.getCenter(thirdClip) - tester.getCenter(firstClip),
      );
      await tester.pumpAndSettle();
      expect(cubit.timelineSectionOrder.take(3), [
        'clip-1',
        'clip-2',
        'clip-0',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canvas and timeline selection stay synchronized and reveal the clip',
    (tester) async {
      _setWindowSize(tester, const Size(1600, 900));
      final image = await _solidImage();
      final strokes = [
        for (var index = 0; index < 12; index++)
          DrawingStroke(
            id: 'sync-$index',
            name: 'Sync $index',
            points: [
              Offset(0.2, 0.1 + index * 0.07),
              Offset(0.8, 0.1 + index * 0.07),
            ],
          ),
      ];
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(strokes: strokes),
          drawingImage: image,
        ),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });

      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
      await tester.pumpAndSettle();
      final zoomIn = find.byKey(const ValueKey('timeline-zoom-in'));
      for (var index = 0; index < 18; index++) {
        await tester.tap(zoomIn);
        await tester.pump();
      }
      final scrollSurface = find.byKey(
        const ValueKey('timeline-scroll-surface'),
      );
      final timelineScroller = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: scrollSurface,
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(timelineScroller.controller!.offset, 0);

      final canvas = find.byType(EditorCanvas);
      final canvasRect = tester.getRect(canvas);
      final artworkRect = artworkRectFor(image, canvasRect.size);
      final lastStrokePoint = Offset(
        artworkRect.left + artworkRect.width * 0.5,
        artworkRect.top + artworkRect.height * (0.1 + 11 * 0.07),
      );
      await tester.tapAt(canvasRect.topLeft + lastStrokePoint);
      await tester.pumpAndSettle();

      expect(cubit.selectedStrokeIndex, 11);
      expect(timelineScroller.controller!.offset, greaterThan(0));
      final selectedClip = find.byKey(
        const ValueKey('timeline-thumbnail-stroke:sync-11'),
      );
      expect(
        tester.getRect(selectedClip).center.dx,
        inInclusiveRange(
          tester.getRect(scrollSurface).left,
          tester.getRect(scrollSurface).right,
        ),
      );

      timelineScroller.controller!.jumpTo(0);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('timeline-thumbnail-stroke:sync-0')),
      );
      await tester.pumpAndSettle();

      expect(cubit.selectedStrokeIndex, 0);
      final canvasPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: canvas,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint && widget.painter is EditorCanvasPainter,
          ),
        ),
      );
      expect(
        (canvasPaint.painter! as EditorCanvasPainter).state.selectedStrokeIndex,
        0,
      );
      final canvasWidget = tester.widget<EditorCanvas>(canvas);
      final resolvedFrame = canvasWidget.resolvedFrameListenable!.value!;
      expect(resolvedFrame.drawing!.sectionId!.value, 'stroke:sync-0');
      final firstRange = cubit.timelineSectionRanges['stroke:sync-0']!;
      expect(
        ((firstRange.endSeconds * Duration.microsecondsPerSecond).round() -
                resolvedFrame.time.microseconds)
            .abs(),
        lessThanOrEqualTo(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('moves the inspector into a drawer on narrow windows', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(800, 700));
    await tester.pumpWidget(const HandDrawStudioApp());

    expect(find.byKey(const ValueKey('editor-layout-narrow')), findsOneWidget);
    expect(find.byKey(const ValueKey('editor-inspector-docked')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('open-inspector')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('editor-inspector-drawer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inspector-section-project-summary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inspector-section-project-timing')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Auto Path result is informational and has no Apply step', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'auto-result',
              name: 'Auto result',
              points: const [Offset(0.1, 0.2), Offset(0.8, 0.2)],
              sectionId: 'section-1',
            ),
          ],
        ),
        autoPathResult: const AutoPathResultSummary(
          sectionCount: 4,
          pathCount: 6,
          handSectionCount: 3,
          revealSectionCount: 1,
          textSectionCount: 1,
          artworkSectionCount: 3,
          nativeVectorCount: 2,
        ),
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await _openInspectorTab(tester, 'Animation');

    expect(
      find.byKey(const ValueKey('inspector-section-smart-path')),
      findsOneWidget,
    );
    expect(find.text('Applied'), findsOneWidget);
    expect(find.text('Apply Paths'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Native vectors 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suspected frame review can restore or exclude before apply', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingImagePath: '/tmp/frame.png'),
        smartSections: const [
          SmartPathSection(
            id: 'frame',
            kind: SmartSectionKind.shape,
            bounds: Rect.fromLTRB(0.01, 0.01, 0.99, 0.99),
            label: 'Artwork 1',
            paths: [
              SmartGeneratedPath(
                points: [
                  Offset(0.01, 0.01),
                  Offset(0.99, 0.01),
                  Offset(0.99, 0.99),
                  Offset(0.01, 0.99),
                ],
              ),
            ],
            recommendedRevealWidth: 0.01,
            mode: SmartSectionMode.ignore,
            artifactHint: SmartSectionArtifactHint.suspectedFrame,
            artifactConfidence: 0.99,
          ),
        ],
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await _openInspectorTab(tester, 'Animation');

    expect(
      find.byKey(const ValueKey('inspector-section-smart-path-review')),
      findsOneWidget,
    );
    expect(find.text('Experimental'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('apply-smart-path-review')),
      findsOneWidget,
    );
    final toggle = find.byKey(const ValueKey('toggle-suspected-frame-frame'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
    expect(cubit.smartSections.single.mode, SmartSectionMode.handDraw);
    expect(find.text('Exclude'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps controls reachable without overflow at minimum width', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(520, 640));
    await tester.pumpWidget(const HandDrawStudioApp());

    expect(find.byKey(const ValueKey('editor-layout-narrow')), findsOneWidget);
    expect(find.byTooltip('Project actions'), findsOneWidget);
    expect(find.byTooltip('Export MOV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens About and the complete release notes from app info', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    await tester.pumpWidget(const HandDrawStudioApp());

    await tester.tap(find.byKey(const ValueKey('app-info-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About HandDraw Studio'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'About must not overflow');

    expect(find.byKey(const ValueKey('about-dialog-content')), findsOneWidget);
    expect(
      find.text(
        'Version ${AppBuildInfo.version} • Build ${AppBuildInfo.buildNumber}',
      ),
      findsOneWidget,
    );
    expect(find.text('Mahmoud Basuony'), findsOneWidget);
    expect(find.byKey(const ValueKey('copy-system-info')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('about-dialog-content')),
      const Offset(0, -480),
    );
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Scrolled About must not overflow',
    );
    expect(find.text('Open-source licenses'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'What’s New'));
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'Release Notes must not overflow',
    );

    expect(find.byKey(const ValueKey('release-notes-list')), findsOneWidget);
    expect(find.text('Version ${AppBuildInfo.version}'), findsOneWidget);
    expect(find.text('CURRENT'), findsOneWidget);
    expect(find.text('Faster full-quality MOV export'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps About reachable from the narrow project menu', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(520, 640));
    await tester.pumpWidget(const HandDrawStudioApp());

    await tester.tap(find.byTooltip('Project actions'));
    await tester.pumpAndSettle();
    expect(find.text('What’s New'), findsOneWidget);
    expect(find.text('About HandDraw Studio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens a responsive hand library with calibrated defaults', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final hand = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(),
        handImage: hand,
      ),
    );
    addTearDown(() async {
      await cubit.close();
      hand.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    await tester.tap(find.byTooltip('Image & hand'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hands'));
    await tester.pumpAndSettle();

    expect(find.text('Hand Library'), findsOneWidget);
    expect(find.text('Marker — Right'), findsOneWidget);
    expect(find.text('Marker — Left'), findsOneWidget);
    expect(find.text('Marker — Compact'), findsOneWidget);
    expect(find.text('Dark Marker — Right'), findsOneWidget);
    expect(find.text('Fine Liner — Right'), findsOneWidget);
    expect(find.text('Blue Marker — Right'), findsOneWidget);
    await tester.drag(find.byType(GridView), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.text('Front Black Marker — Right'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GridView),
        matching: find.text('Technical Pen — Wheat'),
      ),
      findsOneWidget,
    );
    expect(find.text('Import Custom Hand'), findsOneWidget);
    expect(cubit.state.handPresets, hasLength(8));
    expect(find.text('Hand size in video'), findsOneWidget);
    final sizeSlider = find.byKey(const ValueKey('hand-library-video-size'));
    expect(sizeSlider, findsOneWidget);
    tester.widget<Slider>(sizeSlider).onChanged!(.55);
    await tester.pumpAndSettle();
    expect(cubit.project.handScale, .55);
    expect(tester.widget<Slider>(sizeSlider).value, .55);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('hand-library-video-size-value')),
          )
          .data,
      '55%',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens every writing sound without hidden ListTile ink', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 1000));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          writingSoundEnabled: true,
          strokes: [
            DrawingStroke(
              id: 'sound-path',
              name: 'Sound path',
              points: const [Offset(0.2, 0.5), Offset(0.8, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    await _openInspectorTab(tester, 'Audio');

    final soundPicker = find.byType(
      DropdownButtonFormField<WritingSoundPreset>,
    );
    await tester.ensureVisible(soundPicker);
    await tester.tap(soundPicker);
    await tester.pumpAndSettle();

    for (final preset in WritingSoundPreset.values) {
      expect(find.text(preset.label), findsWidgets);
    }
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('writing-sound-preview-button')),
    );
    expect(
      find.byKey(const ValueKey('writing-sound-preview-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('writing-sound-preview-progress')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup sound preference is available in the Audio inspector', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    await tester.pumpWidget(const HandDrawStudioApp());
    await _openInspectorTab(tester, 'Audio');

    final toggle = find.byKey(const ValueKey('startup-sound-toggle'));
    await tester.scrollUntilVisible(
      toggle,
      240,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('editor-inspector-scroll-view')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(toggle, findsOneWidget);
    expect(find.text('Play startup sound'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    final switchWidget = tester.widget<Switch>(
      find.descendant(of: toggle, matching: find.byType(Switch)),
    );
    expect(switchWidget.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('advanced timing stays compact and exposes section controls', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 1000));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'package-a-line',
              name: 'PACKAGE A',
              sectionId: 'package-a',
              points: const [Offset(0.1, 0.4), Offset(0.8, 0.4)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    await _openInspectorTab(tester, 'Animation');

    await tester.ensureVisible(find.text('Advanced Timing'));
    await tester.tap(find.text('Advanced Timing'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1. PACKAGE A'));
    await tester.tap(find.text('1. PACKAGE A'));
    await tester.pumpAndSettle();

    expect(find.text('Pause before'), findsOneWidget);
    expect(find.text('Pause after'), findsOneWidget);
    expect(find.text('Drawing speed'), findsOneWidget);
    expect(find.text('Keep hand visible while paused'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hand inspector exposes final hand visibility and defaults to hidden',
    (tester) async {
      _setWindowSize(tester, const Size(1366, 900));
      final hand = await _solidImage();
      final cubit = EditorCubit(
        handLibraryRepository: _MemoryHandLibraryRepository(),
        initialState: testEditorState(
          project: HandDrawProject(
            strokes: [
              DrawingStroke(
                id: 'final-hand-toggle',
                name: 'Final hand toggle',
                sectionId: 'final',
                points: const [Offset(.1, .5), Offset(.9, .5)],
              ),
            ],
          ),
          handImage: hand,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        hand.dispose();
      });
      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

      await _openInspectorTab(tester, 'HAND');
      final toggle = find.byKey(
        const ValueKey('keep-hand-visible-after-drawing'),
      );
      await tester.ensureVisible(toggle);
      expect(toggle, findsOneWidget);
      expect(cubit.keepHandVisibleAfterDrawing, isFalse);

      await tester.tap(toggle);
      await tester.pump();
      expect(cubit.keepHandVisibleAfterDrawing, isTrue);
      expect(
        cubit
            .project
            .sectionTimings['section:final']!
            .keepHandVisibleAfterDrawing,
        isTrue,
      );

      await tester.tap(toggle);
      await tester.pump();
      expect(cubit.keepHandVisibleAfterDrawing, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overall speed preset changes motion without stretching holds', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 1000));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'speed-line',
              name: 'Speed line',
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    await _openInspectorTab(tester, 'Animation');
    await tester.ensureVisible(find.text('Overall drawing speed'));
    expect(find.text('4×'), findsOneWidget);
    final speedSlider = tester.widget<Slider>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Slider && widget.max == maximumProjectDrawingSpeed,
      ),
    );
    expect(speedSlider.max, 8);
    expect(speedSlider.divisions, 155);
    await tester.tap(find.text('0.5×'));
    await tester.pumpAndSettle();

    expect(cubit.project.drawingSpeed, 0.5);
    expect(cubit.project.startDelaySeconds, 0.4);
    expect(cubit.project.endHoldSeconds, 0.9);
    expect(projectTimelineDuration(cubit.project), closeTo(10.7, 0.0001));
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline clip widths match their resolved time spans', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          startDelaySeconds: 0,
          endHoldSeconds: 0,
          strokes: [
            DrawingStroke(
              id: 'short',
              name: 'Short',
              sectionId: 'short',
              points: const [Offset(0.05, 0.2), Offset(0.15, 0.2)],
            ),
            DrawingStroke(
              id: 'long',
              name: 'Long',
              sectionId: 'long',
              points: const [Offset(0.2, 0.7), Offset(0.95, 0.7)],
            ),
          ],
          timelineSectionOrder: const ['short', 'long'],
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.pumpAndSettle();

    final shortRange = cubit.timelineSectionRanges['short']!;
    final longRange = cubit.timelineSectionRanges['long']!;
    final shortWidth = tester
        .getSize(find.byKey(const ValueKey('timeline-node-section:short')))
        .width;
    final longWidth = tester
        .getSize(find.byKey(const ValueKey('timeline-node-section:long')))
        .width;

    expect(
      longWidth / shortWidth,
      closeTo(longRange.durationSeconds / shortRange.durationSeconds, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('fractional timeline clip widths never overflow their lane', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1437, 920));
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          startDelaySeconds: 0,
          endHoldSeconds: 0,
          drawingSpeed: 0.5,
          strokes: [
            DrawingStroke(
              id: 'fractional-title',
              name: 'Title',
              sectionId: 'title',
              points: const [Offset(0.16, 0.3), Offset(0.71, 0.3)],
            ),
            DrawingStroke(
              id: 'fractional-artwork',
              name: 'Artwork',
              sectionId: 'artwork',
              points: const [Offset(0.3, 0.5), Offset(0.7, 0.5)],
            ),
            DrawingStroke(
              id: 'fractional-subtitle',
              name: 'Subtitle',
              sectionId: 'subtitle',
              points: const [Offset(0.23, 0.7), Offset(0.78, 0.7)],
            ),
          ],
          timelineSectionOrder: const ['title', 'artwork', 'subtitle'],
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('timeline-node-section:title')), findsOne);
    expect(
      find.byKey(const ValueKey('timeline-node-section:artwork')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('timeline-node-section:subtitle')),
      findsOne,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact clips all stay selectable and timeline zoom reaches 12x',
    (tester) async {
      _setWindowSize(tester, const Size(1600, 900));
      final image = await _solidImage();
      final ids = List.generate(12, (index) => 'compact-$index');
      final sections = [
        for (var index = 0; index < ids.length; index++)
          SmartPathSection(
            id: ids[index],
            kind: SmartSectionKind.shape,
            bounds: Rect.fromLTWH(index / 12, 0.2, 0.06, 0.2),
            label: 'Compact $index',
            paths: [
              SmartGeneratedPath(
                points: [
                  Offset(index / 12, 0.2),
                  Offset(index / 12 + 0.05, 0.4),
                ],
              ),
            ],
            recommendedRevealWidth: 0.01,
            mode: SmartSectionMode.handDraw,
          ),
      ];
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(timelineSectionOrder: ids),
          drawingImage: image,
          smartSections: sections,
        ),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });

      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
      await tester.pumpAndSettle();
      final firstNode = find.byKey(
        const ValueKey('timeline-node-section:compact-0'),
      );
      final initialWidth = tester.getSize(firstNode).width;
      expect(initialWidth, lessThan(104));
      for (final id in ids) {
        expect(find.byKey(ValueKey('timeline-select-$id')), findsOneWidget);
      }

      await tester.tap(find.byKey(const ValueKey('timeline-select-compact-0')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('timeline-select-compact-11')),
      );
      await tester.pump();
      expect(cubit.selectedTimelineSectionIds, {'compact-0', 'compact-11'});

      final zoomIn = find.byKey(const ValueKey('timeline-zoom-in'));
      for (var index = 0; index < 22; index++) {
        await tester.tap(zoomIn);
        await tester.pump();
      }
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('timeline-zoom-slider')))
            .value,
        12,
      );
      expect(tester.getSize(firstNode).width, greaterThan(initialWidth * 5));

      final timelineScroller = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byKey(const ValueKey('timeline-scroll-surface')),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(timelineScroller.controller!.offset, 0);
      final scrollSurface = tester.getRect(
        find.byKey(const ValueKey('timeline-scroll-surface')),
      );
      final panGesture = await tester.startGesture(
        Offset(scrollSurface.center.dx, scrollSurface.top + 12),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await panGesture.moveBy(const Offset(-420, 0));
      await panGesture.up();
      await tester.pumpAndSettle();
      expect(
        timelineScroller.controller!.offset,
        greaterThan(200),
        reason: 'Middle-dragging timeline space must pan horizontally.',
      );
      timelineScroller.controller!.jumpTo(0);
      await tester.pump();

      cubit.createTimelineGroupFromSelection();
      await tester.pumpAndSettle();
      final scene = cubit.timelineSceneGroups.single;
      final sceneSelection = find.byKey(
        ValueKey('timeline-select-scene:${scene.id}'),
      );
      expect(sceneSelection, findsOneWidget);
      expect(cubit.selectedTimelineSectionIds, isEmpty);
      await tester.tap(sceneSelection);
      await tester.pump();
      expect(cubit.selectedTimelineSectionIds, {'compact-0', 'compact-11'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'timeline shows an insertion line and moves selected clips in order',
    (tester) async {
      _setWindowSize(tester, const Size(1600, 900));
      final image = await _solidImage();
      DrawingStroke stroke(String id, double y) => DrawingStroke(
        id: id,
        name: id.toUpperCase(),
        sectionId: id,
        points: [Offset(0.1, y), Offset(0.6, y)],
      );
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            startDelaySeconds: 0,
            endHoldSeconds: 0,
            strokes: [
              stroke('a', 0.2),
              stroke('b', 0.4),
              stroke('c', 0.6),
              stroke('d', 0.8),
            ],
            timelineSectionOrder: const ['a', 'b', 'c', 'd'],
          ),
          drawingImage: image,
        ),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });

      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('timeline-select-a')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('timeline-select-c')));
      await tester.pump();

      expect(cubit.selectedTimelineSectionIds, {'a', 'c'});
      final source = find.byKey(const ValueKey('timeline-drag-section:a'));
      final target = find.byKey(const ValueKey('timeline-node-section:d'));
      final targetRect = tester.getRect(target);
      final gesture = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(targetRect.right - 4, targetRect.center.dy));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('timeline-insertion-after:section:d')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('timeline-multi-drag-count')),
        findsOneWidget,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      expect(cubit.timelineSectionOrder, ['b', 'd', 'a', 'c']);
      expect(cubit.selectedTimelineSectionIds, {'a', 'c'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('timeline section dialog edits the shared motion schedule', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1600, 900));
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          drawingSpeed: 5.35,
          startDelaySeconds: 0,
          endHoldSeconds: 0,
          strokes: [
            DrawingStroke(
              id: 'a',
              name: 'A',
              sectionId: 'a',
              points: const [Offset(0.1, 0.2), Offset(0.5, 0.2)],
            ),
            DrawingStroke(
              id: 'b',
              name: 'B',
              sectionId: 'b',
              points: const [Offset(0.6, 0.7), Offset(0.9, 0.7)],
            ),
          ],
          timelineSectionOrder: const ['a', 'b'],
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-thumbnail-a')));
    await tester.pump();
    expect(find.byKey(const ValueKey('timeline-view-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('timeline-delete-a')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('timeline-view-a')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('timeline-section-properties-dialog')),
      findsOneWidget,
    );
    expect(find.text('Animate'), findsOneWidget);
    expect(find.text('Pause at section start'), findsWidgets);
    expect(find.text('Pause at section end'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('section-start-stage')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('section-end-stage')));
    await tester.tap(find.byKey(const ValueKey('section-end-stage')));
    await tester.pumpAndSettle();
    expect(find.text('Hand entrance animation'), findsOneWidget);
    expect(find.text('Transition'), findsOneWidget);
    expect(find.text('Draw Path'), findsWidgets);
    expect(find.text('Appearance method'), findsOneWidget);
    expect(find.text('Mask Reveal'), findsWidgets);

    double displayedAnimationSeconds() {
      final values = tester
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('section-animate-duration')),
              matching: find.byType(Text),
            ),
          )
          .map((text) => text.data)
          .whereType<String>();
      return double.parse(
        values
            .singleWhere((value) => RegExp(r'^\d+\.\d{2} s$').hasMatch(value))
            .split(' ')
            .first,
      );
    }

    final dialogInitialAnimation = displayedAnimationSeconds();
    final initialSectionSpeed = double.parse(
      tester
          .widget<Text>(find.byKey(const ValueKey('section-speed-value')))
          .data!
          .replaceFirst('×', ''),
    );
    final targetSectionSpeed = initialSectionSpeed == 2 ? 1.0 : 2.0;

    await tester.ensureVisible(
      find.byKey(ValueKey('section-speed-${targetSectionSpeed}x')),
    );
    await tester.tap(
      find.byKey(ValueKey('section-speed-${targetSectionSpeed}x')),
    );
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('section-speed-value')))
          .data,
      '${targetSectionSpeed.toInt()}×',
    );
    final expectedPresetDuration =
        dialogInitialAnimation * initialSectionSpeed / targetSectionSpeed;
    expect(displayedAnimationSeconds(), closeTo(expectedPresetDuration, .011));
    Future<void> increase(String key) async {
      final stepper = find.byKey(ValueKey(key));
      await tester.ensureVisible(stepper);
      await tester.tap(
        find.descendant(of: stepper, matching: find.byType(IconButton)).last,
      );
      await tester.pump();
    }

    await tester.ensureVisible(
      find.byKey(const ValueKey('section-start-pause-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('section-start-pause-toggle')));
    await tester.pump();
    await tester.ensureVisible(find.text('Fade in'));
    await tester.tap(find.text('Fade in'));
    await tester.pump();
    await increase('section-animate-duration');
    await tester.ensureVisible(
      find.byKey(const ValueKey('section-end-pause-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('section-end-pause-toggle')));
    await tester.pump();
    await increase('section-pause-duration');
    await tester.ensureVisible(find.text('Move out'));
    await tester.tap(find.text('Move out'));
    await tester.pump();
    await increase('section-transition-duration');
    await tester.ensureVisible(
      find.byKey(const ValueKey('section-keep-hand-visible-after-drawing')),
    );
    await tester.tap(
      find.byKey(const ValueKey('section-keep-hand-visible-after-drawing')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-section-properties')));
    await tester.pumpAndSettle();

    final timing = cubit.project.sectionTimings['section:a']!;
    expect(
      timing.animationDurationSeconds,
      closeTo(
        (expectedPresetDuration + 0.1) *
            cubit.project.drawingSpeed *
            timing.speedMultiplier,
        0.011,
      ),
    );
    expect(
      timing.speedMultiplier,
      closeTo(
        dialogInitialAnimation *
            initialSectionSpeed /
            (expectedPresetDuration + 0.1),
        0.011,
      ),
    );
    expect(timing.pauseBeforeEnabled, isTrue);
    expect(timing.pauseBeforeSeconds, 0);
    expect(timing.pauseAfterEnabled, isTrue);
    expect(timing.pauseAfterSeconds, closeTo(0.05, 0.0001));
    expect(timing.transitionAfterSeconds, closeTo(0.1, 0.0001));
    expect(timing.handEntranceAnimation, SectionHandEntranceAnimation.fadeIn);
    expect(timing.handEntranceDurationSeconds, closeTo(.1, .0001));
    expect(timing.handExitAnimation, SectionHandExitAnimation.moveOut);
    expect(timing.handExitDurationSeconds, closeTo(.1, .0001));
    expect(timing.keepHandVisibleAfterDrawing, isTrue);
    final resolved = projectTimelineSectionMetrics(cubit.project)['a']!;
    expect(
      resolved.animationSeconds,
      closeTo(expectedPresetDuration + 0.1, 0.011),
    );
    expect(resolved.pauseBeforeSeconds, 0);
    expect(resolved.handEntranceSeconds, closeTo(.1, .0001));
    expect(resolved.pauseAfterSeconds, closeTo(0.05, 0.0001));
    expect(resolved.handExitSeconds, 0);
    expect(
      resolved.transitionAfterSeconds,
      closeTo(timing.transitionAfterSeconds!, 0.0001),
    );
    final thumbnailRect = tester.getRect(
      find.byKey(const ValueKey('timeline-thumbnail-a')),
    );
    final drawWindowRect = tester.getRect(
      find.byKey(const ValueKey('timeline-draw-window:a')),
    );
    final pauseBeforeRect = tester.getRect(
      find.byKey(const ValueKey('timeline-pause-before:a')),
    );
    final pauseAfterRect = tester.getRect(
      find.byKey(const ValueKey('timeline-pause-after:a')),
    );
    for (final marker in [drawWindowRect, pauseBeforeRect, pauseAfterRect]) {
      expect(marker.left, greaterThanOrEqualTo(thumbnailRect.left));
      expect(marker.right, lessThanOrEqualTo(thumbnailRect.right));
    }
    expect(pauseBeforeRect.width, greaterThanOrEqualTo(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline delete action removes the selected section safely', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1600, 900));
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'a',
              name: 'A',
              sectionId: 'a',
              points: const [Offset(0.1, 0.2), Offset(0.5, 0.2)],
            ),
            DrawingStroke(
              id: 'b',
              name: 'B',
              sectionId: 'b',
              points: const [Offset(0.6, 0.7), Offset(0.9, 0.7)],
            ),
          ],
          timelineSectionOrder: const ['a', 'b'],
          sectionTimings: const {
            'section:a': SectionTiming(pauseAfterSeconds: 1),
          },
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('timeline-thumbnail-a')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('timeline-delete-a')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-delete-timeline-section')),
    );
    await tester.pumpAndSettle();

    expect(cubit.timelineSectionOrder, ['b']);
    expect(cubit.project.strokes.map((stroke) => stroke.sectionId), ['b']);
    expect(cubit.project.sectionTimings, isEmpty);
    expect(find.byKey(const ValueKey('timeline-node-section:a')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replaying updates progress before the previous end time', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          drawingImagePath: '/tmp/replay.png',
          startDelaySeconds: 0,
          endHoldSeconds: 0,
          strokes: [
            DrawingStroke(
              id: 'line',
              name: 'Line',
              points: const [Offset(.1, .5), Offset(.9, .5)],
            ),
          ],
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: EditorScreen(
          cubit: cubit,
          writingAudioService: _RecordingPreviewAudioService(),
        ),
      ),
    );
    final play = find.byKey(const ValueKey('canvas-preview-toggle'));
    double progress() => tester
        .widget<Slider>(find.byKey(const ValueKey('canvas-preview-progress')))
        .value;
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(progress(), 1);
    await tester.tap(play);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    expect(progress(), greaterThan(0));
    expect(progress(), lessThan(1));
    await tester.pump(const Duration(seconds: 8));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused preview keeps its captured timing after edits', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final image = await _solidImage();
    final audio = _RecordingPreviewAudioService();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          drawingImagePath: '/tmp/timing.png',
          startDelaySeconds: 0,
          endHoldSeconds: 0,
          strokes: [
            DrawingStroke(
              id: 'line',
              name: 'Line',
              sectionId: 'line',
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            ),
          ],
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: EditorScreen(cubit: cubit, writingAudioService: audio),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump();
    final pausedCanvasGestures = tester.widgetList<GestureDetector>(
      find.descendant(
        of: find.byType(EditorCanvas),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(
      pausedCanvasGestures.any((gesture) => gesture.onPanStart != null),
      isTrue,
      reason:
          'A paused preview frame must allow canvas/artwork interaction; '
          'only actively advancing playback is read-only.',
    );
    await _openInspectorTab(tester, 'Animation');
    final speedSlider = find
        .descendant(
          of: find.byKey(const ValueKey('inspector-section-animation-timing')),
          matching: find.byType(Slider),
        )
        .first;
    await tester.drag(speedSlider, const Offset(-180, 0));
    await tester.pumpAndSettle();

    expect(audio.previewDurations, hasLength(2));
    expect(audio.previewDurations.last, audio.previewDurations.first);
    expect(audio.pauseCalls, greaterThanOrEqualTo(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fit to duration solves drawing speed from the inspector', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 1000));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'fit-line',
              name: 'Fit line',
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    await _openInspectorTab(tester, 'Animation');
    final fitButton = find.byKey(const ValueKey('fit-to-duration-button'));
    await tester.ensureVisible(fitButton);
    await tester.tap(fitButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('fit-duration-field')),
      '3.65',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(cubit.project.drawingSpeed, closeTo(2, 1e-6));
    expect(projectTimelineDuration(cubit.project), closeTo(3.65, 1e-6));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'large projects use the timeline without a duplicate inspector list',
    (tester) async {
      _setWindowSize(tester, const Size(1600, 900));
      final strokes = List.generate(
        160,
        (index) => DrawingStroke(
          id: 'stress-$index',
          name: 'Artwork ${index + 1}',
          points: [
            Offset(0.1, 0.1 + (index % 8) * 0.08),
            Offset(0.9, 0.1 + (index % 8) * 0.08),
          ],
        ),
      );
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(strokes: strokes),
        ),
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

      await _openInspectorTab(tester, 'Animation');
      expect(
        find.byKey(const ValueKey('inspector-section-strokes')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('timeline-select-stroke:stress-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('timeline-select-stroke:stress-159')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stroke selection reflects on canvas and supports isolated preview',
    (tester) async {
      _setWindowSize(tester, const Size(1600, 900));
      final image = await _solidImage();
      final cubit = EditorCubit(
        initialState: testEditorState(
          drawingImage: image,
          project: HandDrawProject(
            strokes: [
              DrawingStroke(
                id: 'focus-path',
                name: 'Focus path',
                points: const [Offset(0.2, 0.4), Offset(0.8, 0.4)],
              ),
            ],
          ),
        ),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });
      await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('timeline-thumbnail-stroke:focus-path')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('timeline-view-stroke:focus-path')),
      );
      await tester.pumpAndSettle();
      expect(cubit.selectedStrokeIndex, 0);
      await tester.tap(find.text('Draw Path').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-reverse-path')));
      await tester.pump();
      expect(cubit.project.strokes.single.reversed, isTrue);
      await tester.tap(find.text('Appearance method'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-appearance-reveal')));
      await tester.pump();
      expect(cubit.project.strokes.single.revealOnly, isTrue);
      await tester.tap(find.text('Draw Path').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('section-preview-path')));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        tester
            .widget<EditorCanvas>(find.byType(EditorCanvas))
            .previewStrokeIndex,
        0,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('adds and edits an in-stroke pause from timeline View', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1600, 900));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'pause-path',
              name: 'Pause path',
              points: const [Offset(0.2, 0.4), Offset(0.8, 0.4)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('timeline-thumbnail-stroke:pause-path')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('timeline-view-stroke:pause-path')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draw Path').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('section-add-pause-point')));
    await tester.pumpAndSettle();
    expect(find.text('Add pause point'), findsWidgets);
    final positionPicker = find.byKey(
      const ValueKey('pause-path-position-picker'),
    );
    final pickerRect = tester.getRect(positionPicker);
    await tester.tapAt(
      Offset(pickerRect.left + pickerRect.width * 0.75, pickerRect.center.dy),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('save-pause-point')));
    await tester.pumpAndSettle();

    expect(cubit.project.strokes.single.pausePoints, hasLength(1));
    expect(
      cubit.project.strokes.single.pausePoints.single.progress,
      greaterThan(0.65),
    );
    expect(
      cubit.project.strokes.single.pausePoints.single.durationSeconds,
      closeTo(0.8, 0.0001),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('command Z undoes and command shift Z redoes a stroke', (
    tester,
  ) async {
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingImagePath: '/tmp/keyboard.png'),
        drawingImage: image,
      ),
    );
    addTearDown(() async {
      await cubit.close();
      image.dispose();
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

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(cubit.project.strokes, isEmpty);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    expect(cubit.project.strokes, hasLength(1));
  });

  testWidgets('history buttons and dirty marker follow unified history', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1800, 900));
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    const fingerprints = CanonicalDocumentFingerprintCalculator();
    final cleanFingerprint = fingerprints
        .calculate(cubit.state.document)
        .persistence
        .value;
    cubit.history.markSaved(
      cubit.history.captureSaveSnapshot(cleanFingerprint),
    );

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('editor-undo')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('editor-redo')))
          .onPressed,
      isNull,
    );
    expect(find.text('${cubit.state.document.title} •'), findsNothing);

    cubit.setDuration(7);
    await tester.pump();
    expect(cubit.isDirty, isTrue);
    expect(find.text('${cubit.state.document.title} •'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('editor-undo')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('editor-redo')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('editor-undo')));
    await tester.pump();
    expect(cubit.isDirty, isFalse);
    expect(find.text('${cubit.state.document.title} •'), findsNothing);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('editor-undo')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('editor-redo')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('clear canvas stops preview and removes the imported drawing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final image = await _solidImage();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          drawingImagePath: '/tmp/old-drawing.png',
          drawingImageBase64: 'old-drawing',
          strokes: [
            DrawingStroke(
              id: 'preview-stroke',
              name: 'Preview stroke',
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            ),
          ],
        ),
        drawingImage: image,
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byIcon(Icons.pause), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsWidgets);

    await tester.tap(find.byTooltip('Clear Canvas'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear Canvas').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-clear-canvas')));
    await tester.pump();

    expect(cubit.drawingImage, isNull);
    expect(cubit.project.drawingImagePath, isNull);
    expect(cubit.project.strokes, isEmpty);
    expect(find.byKey(const ValueKey('canvas-preview-toggle')), findsOneWidget);
    expect(
      find.text('Canvas cleared. Hand and global settings were kept.'),
      findsWidgets,
    );
  });

  testWidgets('Voice Guide bar stays responsive and exposes sync controls', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(800, 700));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          voiceGuide: VoiceGuide(
            path: '/tmp/guide.m4a',
            name: 'lesson voice.m4a',
            durationSeconds: 14,
            waveform: List.generate(80, (index) => (index % 10) / 10),
          ),
          strokes: [
            DrawingStroke(
              id: 'package-a',
              name: 'PACKAGE A',
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    expect(find.byKey(const ValueKey('voice-guide-bar')), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('voice-guide-bar')),
        matching: find.byKey(const ValueKey('editor-timeline-dock')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('timeline-audio-waveform')),
      findsOneWidget,
    );
    expect(find.text('lesson voice.m4a'), findsOneWidget);
    expect(find.byTooltip('Voice Guide actions'), findsOneWidget);
    final scrubber = find.byKey(const ValueKey('voice-guide-scrubber'));
    final scrubRect = tester.getRect(scrubber);
    final gesture = await tester.startGesture(
      Offset(scrubRect.left + scrubRect.width * 0.25, scrubRect.center.dy),
    );
    await gesture.moveTo(
      Offset(scrubRect.left + scrubRect.width * 0.75, scrubRect.center.dy),
    );
    await gesture.up();
    await tester.pump();
    expect(find.text('0:10.50'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'timeline-node-played:',
            ),
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('canvas-preview-progress')))
          .value,
      0,
    );

    final timeline = tester.widget<EditorTimelineDock>(
      find.byType(EditorTimelineDock),
    );
    timeline.onSeek(.5);
    await tester.pump();
    expect(find.text('0:07.00'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'timeline-node-played:',
            ),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump(const Duration(milliseconds: 80));
    final masterProgress = tester.widget<Slider>(
      find.byKey(const ValueKey('canvas-preview-progress')),
    );
    masterProgress.onChanged!(.5);
    await tester.pump();
    expect(find.text('0:10.50'), findsNothing);

    final voiceActions = find.byKey(const ValueKey('voice-guide-actions'));
    await tester.ensureVisible(voiceActions);
    await tester.pumpAndSettle();
    await tester.tap(voiceActions);
    await tester.pumpAndSettle();
    final removeAction = find.byKey(
      const ValueKey('voice-guide-remove-action'),
    );
    expect(removeAction, findsOneWidget);
    expect(tester.getSize(removeAction).width, greaterThanOrEqualTo(220));
    await tester.tap(removeAction);
    await tester.pumpAndSettle();
    expect(cubit.voiceGuide, isNull);
    expect(find.byKey(const ValueKey('voice-guide-bar')), findsNothing);

    cubit.undoStroke();
    await tester.pumpAndSettle();
    expect(cubit.voiceGuide?.name, 'lesson voice.m4a');
    expect(find.byKey(const ValueKey('voice-guide-bar')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('master pause resume keeps enabled Voice Guide synchronized', (
    tester,
  ) async {
    _setWindowSize(tester, const Size(1366, 900));
    final audio = _RecordingPreviewAudioService();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          startDelaySeconds: 0,
          voiceGuide: VoiceGuide(
            path: '/tmp/error-hit.wav',
            name: 'error-hit.wav',
            durationSeconds: .55,
            waveform: [0.2, 0.9, 0.3],
          ),
          strokes: [
            DrawingStroke(
              id: 'package-a',
              name: 'PACKAGE A',
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(
      MaterialApp(
        home: EditorScreen(cubit: cubit, writingAudioService: audio),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump(const Duration(milliseconds: 80));
    expect(audio.playPositions, hasLength(1));
    expect(audio.voiceIncluded.single, isTrue);

    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump();
    expect(audio.pauseCalls, 1);
    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump();
    expect(audio.resumeCalls, 1);
    expect(audio.playPositions, hasLength(1));

    await tester.tap(find.byKey(const ValueKey('voice-track-enabled-toggle')));
    await tester.pump(const Duration(milliseconds: 80));
    expect(audio.playPositions, hasLength(2));
    expect(audio.voiceIncluded.last, isFalse);

    await tester.tap(find.byKey(const ValueKey('voice-track-enabled-toggle')));
    await tester.pump(const Duration(milliseconds: 80));
    expect(audio.playPositions, hasLength(3));
    expect(audio.voiceIncluded.last, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Start Section Here remains enabled while preview is paused', (
    tester,
  ) async {
    const exporterChannel = MethodChannel('handdraw_studio/exporter');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(exporterChannel, (call) async {
          if (call.method == 'getPreviewPosition') return 4.25;
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(exporterChannel, null),
    );
    _setWindowSize(tester, const Size(1366, 1000));
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          startDelaySeconds: 0,
          voiceGuide: VoiceGuide(
            path: '/tmp/guide.m4a',
            name: 'guide.m4a',
            durationSeconds: 10,
            waveform: const [0.2, 0.8, 0.4],
          ),
          strokes: [
            DrawingStroke(
              id: 'package-a',
              name: 'PACKAGE A',
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);
    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));

    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsWidgets);
    await _openInspectorTab(tester, 'Animation');
    await tester.ensureVisible(find.text('Advanced Timing'));
    await tester.tap(find.text('Advanced Timing'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('1. PACKAGE A'));
    await tester.tap(find.text('1. PACKAGE A'));
    await tester.pumpAndSettle();
    final startHereButton = find.byKey(
      const ValueKey('start-section-here-button'),
    );
    await tester.ensureVisible(startHereButton);
    expect(
      tester.widget<FilledButton>(startHereButton).onPressed,
      isNotNull,
      reason: 'Voice cues must stay editable while the preview is paused.',
    );
    await tester.tap(startHereButton);
    await tester.pump();

    expect(
      cubit.sectionTiming('stroke:package-a').voiceCueSeconds,
      isNotNull,
      reason: cubit.state.statusMessage,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openInspectorTab(WidgetTester tester, String label) async {
  final tab = find.descendant(
    of: find.byKey(const ValueKey('inspector-tabs')),
    matching: find.text(label),
  );
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

void _setWindowSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<ui.Image> _solidImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 32, 32),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(32, 32);
  picture.dispose();
  return image;
}

class _RecordingPreviewAudioService extends WritingAudioService {
  final List<double> previewDurations = [];
  final List<double> playPositions = [];
  final List<bool> voiceIncluded = [];
  int pauseCalls = 0;
  int resumeCalls = 0;

  @override
  Future<void> play(
    HandDrawProject project, {
    VoiceGuide? voiceGuide,
    double positionSeconds = 0,
    double? previewDurationSeconds,
    double volume = 1,
  }) async {
    previewDurations.add(previewDurationSeconds ?? 0);
    playPositions.add(positionSeconds);
    voiceIncluded.add(voiceGuide != null);
  }

  @override
  Future<void> pause() async => pauseCalls++;

  @override
  Future<void> resume() async => resumeCalls++;

  @override
  Future<double> position() async => 0;

  @override
  Future<void> stop() async {}
}

final class _MemoryHandLibraryRepository implements HandLibraryRepository {
  HandLibrarySnapshot snapshot = const HandLibrarySnapshot(
    presets: BuiltInHands.all,
    selectedPresetId: BuiltInHands.defaultPresetId,
  );

  @override
  Future<HandLibrarySnapshot> load() async => snapshot;

  @override
  Future<HandLibrarySnapshot> importCustom({
    required HandLibrarySnapshot current,
    required String sourcePath,
    required Uint8List bytes,
  }) => throw UnimplementedError();

  @override
  Future<void> save(HandLibrarySnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}
