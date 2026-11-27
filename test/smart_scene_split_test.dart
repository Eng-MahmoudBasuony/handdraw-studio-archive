import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:image/image.dart' as raster;

import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_path_facade.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/scene_split/application/scene_split_cubit.dart';
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/region_auto_path_analyzer.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/scene_region_reveal_planner.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/smart_scene_splitter.dart';
import 'package:handdraw_studio/features/scene_split/presentation/smart_scene_split_dialog.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  testWidgets('manual image parts opens directly in continuous lasso mode', (
    tester,
  ) async {
    final encoded = _transparentFixture();
    final image = (await tester.runAsync(() => _uiImage(encoded)))!;
    final editor = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
        drawingImage: image,
      ),
    );
    addTearDown(editor.close);
    addTearDown(image.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSmartSceneSplitDialog(
              context,
              editor,
              manualImageParts: true,
            ),
            child: const Text('Parts'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Parts'));
    await tester.pump();
    final context = tester.element(
      find.byKey(const ValueKey('smart-scene-split-dialog')),
    );
    final split = context.read<SceneSplitCubit>();
    expect(split.state.isSuggesting, isFalse);
    expect(split.state.regions, isEmpty);
    expect(split.state.tool, SceneSplitTool.lasso);
    for (var i = 0; i < 4; i++) {
      final x = .05 + i * .22;
      split.beginGesture(Offset(x, .1));
      split.updateGesture(Offset(x + .15, .1));
      split.updateGesture(Offset(x + .15, .4));
      split.updateGesture(Offset(x, .4));
      split.endGesture();
      expect(split.state.tool, SceneSplitTool.lasso);
    }
    expect(split.state.regions, hasLength(4));
    await tester.pump();
    expect(find.text('Create 4 scenes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(editor.project.strokes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  test('scene reveal planner creates one broad ordered stroke per region', () {
    final regions = [
      SceneRegion(
        id: 'wide',
        name: 'Wide title',
        polygon: rectPolygon(const Rect.fromLTWH(0.05, 0.2, 0.9, 0.3)),
      ),
      SceneRegion(
        id: 'tall',
        name: 'Tall art',
        polygon: rectPolygon(const Rect.fromLTWH(0.2, 0.1, 0.6, 0.8)),
      ),
    ];

    final plan = const SceneRegionRevealPlanner().build(
      regions: regions,
      canvasHeight: 1000,
    );

    expect(plan.entries, hasLength(2));
    expect(plan.strokes.map((stroke) => stroke.sectionId), ['wide', 'tall']);
    expect(plan.strokes.every((stroke) => stroke.revealOnly), isTrue);
    expect(
      plan.strokes.every((stroke) => stroke.clipPolygons.isNotEmpty),
      isTrue,
    );
    expect(plan.entries.first.passCount, 1);
    expect(plan.entries.last.passCount, 1);
    expect(
      plan.strokes.every(
        (stroke) => stroke.revealStyle == RevealMaskStyle.directionalWipe,
      ),
      isTrue,
    );
    expect(plan.entries.first.stroke.points, hasLength(4));
    expect(
      plan.entries.first.stroke.points.first.dx,
      lessThan(plan.entries.first.stroke.points.last.dx),
    );
    expect(
      plan.entries.last.stroke.points.first.dx,
      greaterThan(plan.entries.last.stroke.points.last.dx),
      reason: 'Adjacent content regions should alternate left/right motion.',
    );
    expect(plan.entries.first.animationDurationSeconds, closeTo(1.5685, .001));
    expect(plan.entries.last.animationDurationSeconds, closeTo(1.0456, .001));
    expect(
      plan.entries.first.stroke.points.map((point) => point.dy).toSet(),
      hasLength(greaterThan(1)),
      reason:
          'The hand should drift naturally instead of walking a ruler line.',
    );
    expect(plan.entries.first.stroke.revealWidth, greaterThanOrEqualTo(300));
    expect(plan.strokes.length, regions.length);
  });

  test('legacy broad scene reveals migrate to one monotonic nib pass', () {
    final geometry = buildStrokeGeometry([
      DrawingStroke(
        id: 'scene-reveal-legacy-0',
        name: 'Legacy scene • Broad hand reveal',
        revealOnly: true,
        revealStyle: RevealMaskStyle.brush,
        sectionId: 'legacy-scene',
        clipBounds: const Rect.fromLTWH(0.1, 0.2, 0.8, 0.5),
        points: const [
          Offset(0.1, 0.3),
          Offset(0.9, 0.3),
          Offset(0.9, 0.6),
          Offset(0.1, 0.6),
        ],
      ),
    ], const Rect.fromLTWH(0, 0, 1000, 1000)).single;

    expect(geometry.revealStyle, RevealMaskStyle.directionalWipe);
    expect(geometry.rightToLeft, isFalse);
    expect(geometry.timingStart.dx, lessThan(geometry.timingEnd.dx));
    expect(geometry.timingStart.dy, closeTo(geometry.timingEnd.dy, 20));
  });

  test(
    'alpha-first splitter proposes stable separated scene regions',
    () async {
      final encoded = _transparentFixture();
      final regions = await const SmartSceneSplitter(
        maximumDimension: 240,
      ).propose(encoded);

      expect(regions, hasLength(2));
      expect(
        regions.first.bounds.center.dx,
        lessThan(regions.last.bounds.center.dx),
      );
      expect(regions.every((region) => region.automatic), isTrue);
      expect(regions.every((region) => region.fragments.isNotEmpty), isTrue);
    },
  );

  test('background proposal cancellation stops its isolate worker', () async {
    final operation = const SmartSceneSplitter(
      maximumDimension: 240,
      useBackgroundIsolate: true,
    ).start(_transparentFixture());
    final cancelled = expectLater(
      operation.result,
      throwsA(isA<SmartSceneProposalCancelled>()),
    );

    await operation.cancel();

    await cancelled;
    await operation.stopped.timeout(const Duration(seconds: 2));
    expect(operation.isCancelled, isTrue);
  });

  test('automatic mask excludes transparent gaps between fragments', () {
    final region = SceneRegion(
      id: 'automatic',
      name: 'Scene 1',
      polygon: rectPolygon(const Rect.fromLTWH(0.1, 0.1, 0.8, 0.2)),
      fragments: const [
        Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
        Rect.fromLTWH(0.7, 0.1, 0.2, 0.2),
      ],
      automatic: true,
    );

    expect(region.maskPolygons, hasLength(2));
    expect(region.contains(const Offset(0.2, 0.2)), isTrue);
    expect(region.contains(const Offset(0.5, 0.2)), isFalse);
  });

  test('lasso, merge, split, reorder and undo stay in a reversible draft', () {
    final cubit = SceneSplitCubit(Uint8List(0));
    addTearDown(cubit.close);

    cubit.setTool(SceneSplitTool.lasso);
    cubit.beginGesture(const Offset(0.05, 0.05));
    cubit.updateGesture(const Offset(0.40, 0.05));
    cubit.updateGesture(const Offset(0.40, 0.40));
    cubit.updateGesture(const Offset(0.05, 0.40));
    cubit.endGesture();
    cubit.setTool(SceneSplitTool.lasso);
    cubit.beginGesture(const Offset(0.55, 0.05));
    cubit.updateGesture(const Offset(0.90, 0.05));
    cubit.updateGesture(const Offset(0.90, 0.40));
    cubit.updateGesture(const Offset(0.55, 0.40));
    cubit.endGesture();

    expect(cubit.state.regions, hasLength(2));
    cubit.select(cubit.state.regions.first.id);
    cubit.select(cubit.state.regions.last.id, additive: true);
    cubit.mergeSelected();
    expect(cubit.state.regions, hasLength(1));

    cubit.setTool(SceneSplitTool.split);
    cubit.beginGesture(const Offset(0.5, 0.0));
    cubit.updateGesture(const Offset(0.5, 0.45));
    cubit.endGesture();
    expect(cubit.state.regions, hasLength(2));
    final originalSecond = cubit.state.regions.last.id;
    cubit.reorder(1, 0);
    expect(cubit.state.regions.first.id, originalSecond);
    cubit.undo();
    expect(cubit.state.regions.last.id, originalSecond);
  });

  test('manual start clears every region and undo restores the draft', () {
    final cubit = SceneSplitCubit(Uint8List(0));
    addTearDown(cubit.close);
    cubit.setTool(SceneSplitTool.lasso);
    cubit.beginGesture(const Offset(0.05, 0.05));
    cubit.updateGesture(const Offset(0.40, 0.05));
    cubit.updateGesture(const Offset(0.40, 0.40));
    cubit.updateGesture(const Offset(0.05, 0.40));
    cubit.endGesture();
    final regionId = cubit.state.regions.single.id;
    expect(cubit.state.canUndo, isTrue);

    cubit.clearForManualLasso();

    expect(cubit.state.regions, isEmpty);
    expect(cubit.state.selectedIds, isEmpty);
    expect(cubit.state.tool, SceneSplitTool.lasso);
    expect(cubit.state.message, contains('Lasso'));
    expect(cubit.state.canUndo, isTrue);

    cubit.undo();
    expect(cubit.state.regions.single.id, regionId);
    expect(cubit.state.tool, SceneSplitTool.select);
    expect(cubit.state.canUndo, isTrue);
  });

  test('manual start invalidates an in-flight automatic suggestion', () async {
    final pending = Completer<List<SceneRegion>>();
    final splitter = _DelayedSceneSplitter(pending.future);
    final cubit = SceneSplitCubit(Uint8List(0), splitter);
    addTearDown(cubit.close);

    final suggestion = cubit.suggest();
    expect(cubit.state.isSuggesting, isTrue);
    cubit.clearForManualLasso();
    expect(cubit.state.isSuggesting, isFalse);
    expect(cubit.state.tool, SceneSplitTool.lasso);
    await splitter.cancelled.future;
    await splitter.operation!.stopped;
    pending.complete([
      SceneRegion(
        id: 'late-auto',
        name: 'Late',
        polygon: rectPolygon(const Rect.fromLTWH(0.1, 0.1, 0.4, 0.4)),
      ),
    ]);
    await suggestion;

    expect(cubit.state.regions, isEmpty);
    expect(cubit.state.tool, SceneSplitTool.lasso);
  });

  test('closing the split Cubit stops an active suggestion worker', () async {
    final pending = Completer<List<SceneRegion>>();
    final splitter = _DelayedSceneSplitter(pending.future);
    final cubit = SceneSplitCubit(Uint8List(0), splitter);

    final suggestion = cubit.suggest();
    expect(cubit.state.isSuggesting, isTrue);

    await cubit.close();

    await splitter.cancelled.future;
    await splitter.operation!.stopped;
    await suggestion;
    expect(splitter.operation!.isCancelled, isTrue);
    pending.complete(const []);
  });

  test('merge and diagonal split preserve precise non-rectangular masks', () {
    final cubit = SceneSplitCubit(Uint8List(0));
    addTearDown(cubit.close);
    void lasso(List<Offset> points) {
      cubit.setTool(SceneSplitTool.lasso);
      cubit.beginGesture(points.first);
      for (final point in points.skip(1)) {
        cubit.updateGesture(point);
      }
      cubit.endGesture();
    }

    lasso(const [Offset(0.05, 0.05), Offset(0.35, 0.05), Offset(0.05, 0.35)]);
    lasso(const [Offset(0.65, 0.65), Offset(0.95, 0.65), Offset(0.95, 0.95)]);
    cubit.select(cubit.state.regions.first.id);
    cubit.select(cubit.state.regions.last.id, additive: true);
    cubit.mergeSelected();

    final merged = cubit.state.regions.single;
    expect(merged.maskPolygons, hasLength(2));
    expect(merged.contains(const Offset(0.1, 0.1)), isTrue);
    expect(merged.contains(const Offset(0.9, 0.9)), isTrue);
    expect(merged.contains(const Offset(0.5, 0.5)), isFalse);

    cubit.setTool(SceneSplitTool.split);
    cubit.beginGesture(const Offset(0, 0.2));
    cubit.updateGesture(const Offset(1, 0.8));
    cubit.endGesture();
    expect(cubit.state.regions, hasLength(2));
    expect(
      cubit.state.regions.expand((region) => region.maskPolygons),
      everyElement(hasLength(greaterThanOrEqualTo(3))),
    );
  });

  test('splitting a concave lasso does not bridge its empty notch', () {
    final cubit = SceneSplitCubit(Uint8List(0));
    addTearDown(cubit.close);
    cubit.setTool(SceneSplitTool.lasso);
    const points = [
      Offset(0.1, 0.1),
      Offset(0.9, 0.1),
      Offset(0.9, 0.9),
      Offset(0.65, 0.9),
      Offset(0.65, 0.35),
      Offset(0.35, 0.35),
      Offset(0.35, 0.9),
      Offset(0.1, 0.9),
    ];
    cubit.beginGesture(points.first);
    for (final point in points.skip(1)) {
      cubit.updateGesture(point);
    }
    cubit.endGesture();
    cubit.setTool(SceneSplitTool.split);
    cubit.beginGesture(const Offset(0, 0.6));
    cubit.updateGesture(const Offset(1, 0.6));
    cubit.endGesture();

    expect(cubit.state.regions, hasLength(2));
    expect(
      cubit.state.regions.any(
        (region) => region.contains(const Offset(0.5, 0.7)),
      ),
      isFalse,
    );
  });

  test(
    'region Auto Path maps crop-local points back to original artwork',
    () async {
      final source = await _uiImage(_transparentFixture());
      addTearDown(source.dispose);
      final region = SceneRegion(
        id: 'scene-a',
        name: 'Scene 1',
        polygon: rectPolygon(const Rect.fromLTWH(0.1, 0.25, 0.8, 0.2)),
      );
      final result = await const RegionAutoPathAnalyzer().analyze(
        source: source,
        regions: [region],
        facade: const _FakeArtworkPathFacade(),
      );

      expect(result, hasLength(1));
      expect(result.single.id, startsWith('scene-a::'));
      expect(result.single.label, startsWith('Scene 1'));
      expect(result.single.paths.single.points.first.dx, closeTo(0.1, 0.02));
      expect(result.single.paths.single.points.first.dy, closeTo(0.25, 0.02));
      expect(result.single.paths.single.points.last.dx, closeTo(0.9, 0.02));
      expect(result.single.paths.single.points.last.dy, closeTo(0.45, 0.02));
      expect(
        result.single.recommendedRevealWidth,
        closeTo(0.01, 0.001),
        reason: 'Reveal width is normalized against crop height.',
      );
    },
  );

  test(
    'multiple scene regions share one expensive Auto Path analysis',
    () async {
      final source = await _uiImage(_transparentFixture());
      addTearDown(source.dispose);
      final regions = [
        SceneRegion(
          id: 'left-scene',
          name: 'Scene 1',
          polygon: rectPolygon(const Rect.fromLTWH(0.05, 0.1, 0.35, 0.8)),
        ),
        SceneRegion(
          id: 'right-scene',
          name: 'Scene 2',
          polygon: rectPolygon(const Rect.fromLTWH(0.60, 0.1, 0.35, 0.8)),
        ),
      ];
      final facade = _CountingMultiRegionFacade(regions);
      final progressCounts = <int>[];

      final result = await const RegionAutoPathAnalyzer().analyze(
        source: source,
        regions: regions,
        facade: facade,
        onProgress: (_, count, _) => progressCounts.add(count),
      );

      expect(facade.calls, 1);
      expect(progressCounts, isNotEmpty);
      expect(progressCounts.toSet(), {1});
      expect(result.map((section) => section.id.split('::').first), [
        'left-scene',
        'right-scene',
      ]);
      expect(
        result.every((section) => section.id.contains('fallback')),
        isFalse,
      );
      expect(result.every((section) => section.paths.length == 1), isTrue);
      expect(
        facade.unionGapWasTransparent,
        isTrue,
        reason: 'The shared analysis must not reintroduce deleted gap pixels.',
      );
    },
  );

  test('region analysis preserves mixed modes and bidi direction', () async {
    final source = await _uiImage(_transparentFixture());
    addTearDown(source.dispose);
    final region = SceneRegion(
      id: 'mixed',
      name: 'Scene 1',
      polygon: rectPolygon(const Rect.fromLTWH(0, 0, 1, 1)),
    );
    final result = await const RegionAutoPathAnalyzer().analyze(
      source: source,
      regions: [region],
      facade: const _MixedArtworkPathFacade(),
    );

    expect(result, hasLength(2));
    expect(result.map((section) => section.mode), {
      SmartSectionMode.handDraw,
      SmartSectionMode.revealText,
    });
    expect(result.first.rightToLeft, isFalse);
    expect(result.last.rightToLeft, isTrue);
    expect(result.every((section) => section.id.startsWith('mixed::')), isTrue);
  });

  test(
    'confirmed regions become ordered ProjectSections in one apply flow',
    () async {
      final encoded = _transparentFixture();
      final image = await _uiImage(encoded);
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
          drawingImage: image,
        ),
        regionAutoPathAnalyzer: const _FakeRegionAutoPathAnalyzer(),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });
      final regions = [
        SceneRegion(
          id: 'region-a',
          name: 'Scene 1',
          polygon: rectPolygon(const Rect.fromLTWH(0.05, 0.1, 0.3, 0.6)),
        ),
        SceneRegion(
          id: 'region-b',
          name: 'Scene 2',
          polygon: rectPolygon(const Rect.fromLTWH(0.55, 0.1, 0.35, 0.6)),
        ),
      ];

      expect(await cubit.analyzeSmartPathsByRegions(regions), isTrue);
      expect(cubit.state.document.sectionOrder.map((id) => id.value), [
        'region-a',
        'region-b',
      ]);
      expect(cubit.state.document.sections.map((section) => section.name), [
        'Scene 1',
        'Scene 2',
      ]);
      expect(
        cubit.state.document.strokes
            .map((stroke) => stroke.sectionId.value)
            .toSet(),
        {'region-a', 'region-b'},
      );
      expect(cubit.state.autoPathResult?.sectionCount, 2);
    },
  );

  test(
    'ordered scene reveal skips Auto Path and applies reference hand timing',
    () async {
      final encoded = _transparentFixture();
      final image = await _uiImage(encoded);
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            drawingSourceBase64: base64Encode(encoded),
            drawingSpeed: 5.35,
            handScale: 0.24,
          ),
          drawingImage: image,
        ),
        regionAutoPathAnalyzer: const _ThrowingRegionAutoPathAnalyzer(),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });
      final regions = [
        SceneRegion(
          id: 'scene-a',
          name: 'Scene A',
          polygon: rectPolygon(const Rect.fromLTWH(0.05, 0.1, 0.4, 0.4)),
        ),
        SceneRegion(
          id: 'scene-b',
          name: 'Scene B',
          polygon: rectPolygon(const Rect.fromLTWH(0.55, 0.1, 0.4, 0.4)),
        ),
      ];

      expect(await cubit.applyOrderedSceneReveals(regions), isTrue);

      expect(cubit.state.document.strokes, hasLength(2));
      expect(
        cubit.state.document.strokes.map((stroke) => stroke.sectionId.value),
        ['scene-a', 'scene-b'],
      );
      expect(
        cubit.state.document.strokes.every((stroke) => stroke.revealOnly),
        isTrue,
      );
      expect(
        cubit.project.strokes.every(
          (stroke) => stroke.revealStyle == RevealMaskStyle.directionalWipe,
        ),
        isTrue,
      );
      expect(cubit.state.autoPathResult?.pathCount, 2);
      expect(cubit.project.handScale, 0.24);
      final firstTiming = cubit.state.document.sections.first.timing;
      expect(firstTiming.animationDuration?.microseconds, 697095);
      expect(
        projectTimelineSectionMetrics(
          cubit.project,
        )['scene-a']?.animationSeconds,
        closeTo(0.697095 / 5.35, 0.000001),
        reason:
            'The resolved clip must apply the Inspector overall speed to the '
            'saved 1× reference duration.',
      );
      expect(
        firstTiming.handEntranceAnimation,
        SectionHandEntranceAnimation.none,
      );
      expect(firstTiming.handExitAnimation, SectionHandExitAnimation.none);
      expect(firstTiming.transitionAfter.microseconds, 83333);
      final lastTiming = cubit.state.document.sections.last.timing;
      expect(lastTiming.handExitAnimation, SectionHandExitAnimation.moveOut);
      expect(lastTiming.handExitDuration.microseconds, 420000);
      expect(lastTiming.transitionAfter.isZero, isTrue);
      expect(
        cubit.state.document.motionConfiguration.endHold.microseconds,
        3990000,
      );
    },
  );

  test(
    'scene split keeps authored scenes sequential and natural within each one',
    () async {
      final encoded = _transparentFixture();
      final image = await _uiImage(encoded);
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
          drawingImage: image,
        ),
        regionAutoPathAnalyzer: const _ReverseInternalOrderRegionAnalyzer(),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });
      final regions = [
        SceneRegion(
          id: 'scene-1',
          name: 'Scene 1',
          polygon: rectPolygon(const Rect.fromLTWH(0.05, 0.05, 0.4, 0.9)),
        ),
        SceneRegion(
          id: 'scene-2',
          name: 'Scene 2',
          polygon: rectPolygon(const Rect.fromLTWH(0.55, 0.05, 0.4, 0.9)),
        ),
      ];

      expect(await cubit.analyzeSmartPathsByRegions(regions), isTrue);

      final strokes = cubit.project.strokes;
      expect(strokes.map((stroke) => stroke.sectionId).toList(), [
        'scene-1',
        'scene-1',
        'scene-2',
        'scene-2',
      ]);
      final centers = [
        for (final stroke in strokes)
          (stroke.orderedPoints.first.dy + stroke.orderedPoints.last.dy) * 0.5,
      ];
      expect(centers[0], lessThan(centers[1]));
      expect(centers[2], lessThan(centers[3]));

      final spans = projectTimelineSectionSpans(cubit.project);
      expect(spans.map((span) => span.sectionId), ['scene-1', 'scene-2']);
      expect(
        spans.first.endSeconds,
        lessThanOrEqualTo(spans.last.startSeconds),
      );
    },
  );

  test('cancelling region analysis never applies a partial result', () async {
    final encoded = _transparentFixture();
    final image = await _uiImage(encoded);
    final analyzer = _DelayedRegionAutoPathAnalyzer();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
        drawingImage: image,
      ),
      regionAutoPathAnalyzer: analyzer,
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });
    final region = SceneRegion(
      id: 'cancelled-region',
      name: 'Scene 1',
      polygon: rectPolygon(const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8)),
    );

    final pending = cubit.analyzeSmartPathsByRegions([region]);
    await analyzer.started.future;
    cubit.cancelSmartSceneAnalysis();
    analyzer.release.complete();

    expect(await pending, isFalse);
    expect(cubit.state.document.sections, isEmpty);
    expect(cubit.state.document.strokes, isEmpty);
  });

  testWidgets('smart scene progress exposes cancel after the dialog closes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final encoded = _transparentFixture();
    final image = (await tester.runAsync(() => _uiImage(encoded)))!;
    final analyzer = _DelayedRegionAutoPathAnalyzer();
    final editor = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
        drawingImage: image,
      ),
      regionAutoPathAnalyzer: analyzer,
    );
    addTearDown(() {
      editor.close();
      image.dispose();
    });
    final pending = editor.analyzeSmartPathsByRegions([
      SceneRegion(
        id: 'cancel-from-progress',
        name: 'Scene 1',
        polygon: rectPolygon(const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8)),
      ),
    ]);
    await tester.runAsync(() => analyzer.started.future);

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: editor)));
    expect(
      find.byKey(const ValueKey('cancel-smart-scene-analysis')),
      findsOneWidget,
    );
    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('smart-scene-split-dialog')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('cancel-smart-scene-analysis')));
    await tester.pump();
    expect(editor.state.isAnalyzingSmartPaths, isFalse);
    analyzer.release.complete();
    expect(await tester.runAsync(() => pending), isFalse);
  });

  test('closing the editor invalidates a pending region analysis', () async {
    final encoded = _transparentFixture();
    final image = await _uiImage(encoded);
    final analyzer = _DelayedRegionAutoPathAnalyzer();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
        drawingImage: image,
      ),
      regionAutoPathAnalyzer: analyzer,
    );
    final region = SceneRegion(
      id: 'closed-region',
      name: 'Scene 1',
      polygon: rectPolygon(const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8)),
    );

    final pending = cubit.analyzeSmartPathsByRegions([region]);
    await analyzer.started.future;
    await cubit.close();
    analyzer.release.complete();

    expect(await pending, isFalse);
    image.dispose();
  });

  test('a cancelled stale failure cannot stop a newer analysis', () async {
    final encoded = _transparentFixture();
    final image = await _uiImage(encoded);
    final analyzer = _RacingRegionAutoPathAnalyzer();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
        drawingImage: image,
      ),
      regionAutoPathAnalyzer: analyzer,
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });
    final region = SceneRegion(
      id: 'current-region',
      name: 'Scene 1',
      polygon: rectPolygon(const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8)),
    );

    final stale = cubit.analyzeSmartPathsByRegions([region]);
    await analyzer.firstStarted.future;
    cubit.cancelSmartSceneAnalysis();
    final current = cubit.analyzeSmartPathsByRegions([region]);
    await analyzer.secondStarted.future;
    analyzer.failFirst.complete();

    expect(await stale, isFalse);
    expect(cubit.state.isAnalyzingSmartPaths, isTrue);
    analyzer.finishSecond.complete();
    expect(await current, isTrue);
    expect(cubit.state.document.sections, hasLength(1));
  });

  test(
    'mixed sub-sections still become one timeline block per region',
    () async {
      final encoded = _transparentFixture();
      final image = await _uiImage(encoded);
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
          drawingImage: image,
        ),
        regionAutoPathAnalyzer: const _MixedRegionAutoPathAnalyzer(),
      );
      addTearDown(() {
        cubit.close();
        image.dispose();
      });
      final region = SceneRegion(
        id: 'one-region',
        name: 'Scene 1',
        polygon: rectPolygon(const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8)),
      );

      expect(await cubit.analyzeSmartPathsByRegions([region]), isTrue);
      expect(cubit.state.document.sections, hasLength(1));
      expect(cubit.state.document.sections.single.id.value, 'one-region');
      expect(
        cubit.state.document.strokes
            .map((stroke) => stroke.sectionId.value)
            .toSet(),
        {'one-region'},
      );
      final documentStrokes = cubit.state.document.strokes;
      expect(documentStrokes.length, greaterThan(1));
      expect(
        identical(
          documentStrokes.first.clipPolygons,
          documentStrokes.last.clipPolygons,
        ),
        isTrue,
        reason: 'One immutable scene mask must be shared by all scene strokes.',
      );
      final drawingStrokes = cubit.project.strokes;
      expect(
        identical(
          drawingStrokes.first.clipPolygons,
          drawingStrokes.last.clipPolygons,
        ),
        isTrue,
        reason: 'The shared mask must survive the renderer compatibility view.',
      );
    },
  );

  test('scene mask is carried into the shared Preview and MOV timeline', () {
    final snapshot = buildTimelineSnapshot(
      strokes: [
        DrawingStroke(
          id: 'masked',
          name: 'Masked',
          sectionId: 'scene',
          points: const [Offset(0.1, 0.1), Offset(0.9, 0.9)],
          clipPolygons: const [
            [Offset(0.1, 0.1), Offset(0.9, 0.1), Offset(0.1, 0.9)],
          ],
        ),
      ],
      artworkRect: const Rect.fromLTWH(0, 0, 100, 100),
      progress: 1,
    );

    final clip = snapshot.revealedPaths.single.clipPath!;
    expect(clip.contains(const Offset(20, 20)), isTrue);
    expect(clip.contains(const Offset(80, 80)), isFalse);
  });

  test('strokes in one scene reuse a canonical clip path for batching', () {
    const polygon = [Offset(0.1, 0.1), Offset(0.9, 0.1), Offset(0.1, 0.9)];
    final snapshot = buildTimelineSnapshot(
      strokes: [
        DrawingStroke(
          id: 'a',
          name: 'A',
          sectionId: 'scene',
          points: const [Offset(0.1, 0.1), Offset(0.4, 0.4)],
          clipPolygons: const [polygon],
        ),
        DrawingStroke(
          id: 'b',
          name: 'B',
          sectionId: 'scene',
          points: const [Offset(0.5, 0.5), Offset(0.8, 0.8)],
          clipPolygons: const [polygon],
        ),
      ],
      artworkRect: const Rect.fromLTWH(0, 0, 100, 100),
      progress: 1,
    );

    expect(snapshot.revealedPaths, hasLength(2));
    expect(
      identical(
        snapshot.revealedPaths.first.clipPath,
        snapshot.revealedPaths.last.clipPath,
      ),
      isTrue,
    );
  });

  testWidgets('Scene Planner exposes Smart Scene Split before Auto Path', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final encoded = _transparentFixture();
    final image = (await tester.runAsync(() => _uiImage(encoded)))!;
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
        drawingImage: image,
      ),
    );
    addTearDown(() {
      cubit.close();
      image.dispose();
    });

    await tester.pumpWidget(MaterialApp(home: EditorScreen(cubit: cubit)));
    await tester.pump();
    final open = find.byKey(const ValueKey('open-smart-scene-split'));
    expect(open, findsOneWidget);
    expect(find.text('Split into scenes'), findsOneWidget);
    await tester.tap(open);
    await tester.pump();
    expect(
      find.byKey(const ValueKey('smart-scene-split-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('lasso-scene-region')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('clear-scene-regions-for-lasso')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('merge-scene-regions')), findsOneWidget);
    expect(find.byKey(const ValueKey('split-scene-region')), findsOneWidget);
    final dialogContext = tester.element(
      find.byKey(const ValueKey('smart-scene-split-dialog')),
    );
    final split = BlocProvider.of<SceneSplitCubit>(dialogContext);
    await tester.runAsync(() async {
      while (split.state.isSuggesting) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();
    expect(
      find.byKey(const ValueKey('smart-scene-region-scrollbar')),
      findsOneWidget,
    );

    for (var index = 0; index < 8; index++) {
      final left = 0.02 + index * 0.1;
      split.setTool(SceneSplitTool.lasso);
      split.beginGesture(Offset(left, 0.55));
      split.updateGesture(Offset(left + 0.07, 0.55));
      split.updateGesture(Offset(left + 0.07, 0.75));
      split.updateGesture(Offset(left, 0.75));
      split.endGesture();
    }
    await tester.pump();
    final scrollbar = tester.widget<Scrollbar>(
      find.byKey(const ValueKey('smart-scene-region-scrollbar')),
    );
    final controller = scrollbar.controller!;
    expect(scrollbar.thumbVisibility, isTrue);
    expect(scrollbar.interactive, isTrue);
    expect(controller.position.maxScrollExtent, greaterThan(0));

    final strip = find.byKey(const ValueKey('smart-scene-region-strip'));
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(strip),
        scrollDelta: const Offset(0, 90),
      ),
    );
    await tester.pump();
    expect(controller.offset, greaterThan(0));

    final previousRegionIds = split.state.regions
        .map((region) => region.id)
        .toList(growable: false);
    await tester.tap(
      find.byKey(const ValueKey('clear-scene-regions-for-lasso')),
    );
    await tester.pump();
    expect(split.state.regions, isEmpty);
    expect(split.state.tool, SceneSplitTool.lasso);
    split.undo();
    expect(split.state.regions.map((region) => region.id), previousRegionIds);
    Navigator.of(dialogContext).pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual Lasso stays accessible and scrollable in narrow RTL', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final encoded = _transparentFixture();
    final image = (await tester.runAsync(() => _uiImage(encoded)))!;
    final editor = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
        drawingImage: image,
      ),
    );
    addTearDown(() {
      editor.close();
      image.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-rtl-smart-split'),
            onPressed: () => showSmartSceneSplitDialog(context, editor),
            child: const Text('فتح'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-rtl-smart-split')));
    await tester.pump();
    final dialog = find.byKey(const ValueKey('smart-scene-split-dialog'));
    final dialogContext = tester.element(dialog);
    final split = BlocProvider.of<SceneSplitCubit>(dialogContext);
    await tester.runAsync(() async {
      while (split.state.isSuggesting) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });

    for (var index = 0; index < 9; index++) {
      final left = 0.01 + index * 0.095;
      split.setTool(SceneSplitTool.lasso);
      split.beginGesture(Offset(left, 0.52));
      split.updateGesture(Offset(left + 0.06, 0.52));
      split.updateGesture(Offset(left + 0.06, 0.72));
      split.updateGesture(Offset(left, 0.72));
      split.endGesture();
    }
    split.setTool(SceneSplitTool.lasso);
    await tester.pump();

    final contentSummary = tester.widget<Semantics>(
      find.byKey(const ValueKey('smart-scene-content-summary')),
    );
    expect(
      contentSummary.properties.label,
      '${split.state.regions.length} منطقة مشهد',
    );
    expect(
      contentSummary.properties.hint,
      'استخدم شريط الأدوات لاكتشاف المناطق أو تحديدها أو رسمها أو دمجها أو فصلها أو حذفها.',
    );
    expect(
      find.byWidgetPredicate((widget) {
        final key = widget.key;
        return widget is Semantics &&
            key is ValueKey<String> &&
            key.value.startsWith('scene-region-card-');
      }),
      findsNothing,
    );
    final scrollbar = tester.widget<Scrollbar>(
      find.byKey(const ValueKey('smart-scene-region-scrollbar')),
    );
    final controller = scrollbar.controller!;
    expect(controller.position.maxScrollExtent, greaterThan(0));
    final before = controller.offset;
    final delta = before < controller.position.maxScrollExtent / 2
        ? 90.0
        : -90.0;
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(
          find.byKey(const ValueKey('smart-scene-region-strip')),
        ),
        scrollDelta: Offset(0, delta),
      ),
    );
    await tester.pump();
    expect(controller.offset, isNot(closeTo(before, 0.1)));

    split.clearForManualLasso();
    await tester.pump();
    expect(
      find.text('تم مسح الاقتراحات. ارسم المشاهد يدويًا باستخدام اللاسو.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    Navigator.of(dialogContext).pop();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets(
    '16-scene confirm removes the semantics-free overlay before analysis',
    (tester) async {
      tester.view.physicalSize = const Size(800, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final encoded = _transparentFixture();
      final image = (await tester.runAsync(() => _uiImage(encoded)))!;
      final editor = _GatedSceneCloseEditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(drawingSourceBase64: base64Encode(encoded)),
          drawingImage: image,
        ),
      );
      addTearDown(() {
        editor.close();
        image.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              Directionality(textDirection: TextDirection.rtl, child: child!),
          home: Builder(
            builder: (context) => TextButton(
              key: const ValueKey('open-semantics-close-regression'),
              onPressed: () => showSmartSceneSplitDialog(context, editor),
              child: const Text('فتح'),
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey('open-semantics-close-regression')),
      );
      await tester.pump();
      final dialog = find.byKey(const ValueKey('smart-scene-split-dialog'));
      final dialogContext = tester.element(dialog);
      final split = BlocProvider.of<SceneSplitCubit>(dialogContext);
      await tester.runAsync(() async {
        while (split.state.isSuggesting) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pump(const Duration(milliseconds: 200));
      split.clearForManualLasso();
      for (var index = 0; index < 16; index++) {
        final column = index % 4;
        final row = index ~/ 4;
        final left = 0.02 + column * 0.24;
        final top = 0.02 + row * 0.22;
        split.setTool(SceneSplitTool.lasso);
        split.beginGesture(Offset(left, top));
        split.updateGesture(Offset(left + 0.16, top));
        split.updateGesture(Offset(left + 0.16, top + 0.14));
        split.updateGesture(Offset(left, top + 0.14));
        split.endGesture();
      }
      await tester.pump();
      expect(split.state.regions, hasLength(16));
      final confirm = find.byKey(const ValueKey('confirm-smart-scene-split'));
      expect(find.text('إنشاء 16 مشهد'), findsOneWidget);
      final confirmSemantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('confirm-smart-scene-split-semantics')),
      );
      expect(confirmSemantics.properties.label, 'إنشاء 16 مشهد');
      expect(confirmSemantics.properties.onTap, isNotNull);
      expect(
        find.byKey(const ValueKey('smart-scene-content-summary')),
        findsOneWidget,
      );
      Finder sceneCards() => find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> &&
            key.value.startsWith('scene-region-card-');
      });

      // The horizontal list lazily builds only the visible cards. Its visual
      // children remain mounted during the reverse transition, but their
      // descendant semantics are excluded behind the single stable summary.
      expect(sceneCards(), findsWidgets);

      await tester.tap(confirm);
      await tester.pump();
      await tester.pump();
      expect(editor.started.isCompleted, isTrue);
      expect(editor.confirmedRegions, hasLength(16));
      expect(dialog, findsNothing);
      expect(
        find.byKey(const ValueKey('smart-scene-split-overlay')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      editor.release.complete();
      await tester.pump();
      semantics.dispose();
    },
  );
}

Uint8List _transparentFixture() {
  final image = raster.Image(width: 240, height: 120, numChannels: 4);
  raster.fill(image, color: raster.ColorRgba8(0, 0, 0, 0));
  raster.fillRect(
    image,
    x1: 15,
    y1: 20,
    x2: 80,
    y2: 90,
    color: raster.ColorRgba8(20, 80, 220, 255),
  );
  raster.fillRect(
    image,
    x1: 160,
    y1: 25,
    x2: 225,
    y2: 95,
    color: raster.ColorRgba8(220, 70, 40, 255),
  );
  return Uint8List.fromList(raster.encodePng(image));
}

Future<ui.Image> _uiImage(Uint8List encoded) async {
  final codec = await ui.instantiateImageCodec(encoded);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

final class _DelayedSceneSplitter extends SmartSceneSplitter {
  _DelayedSceneSplitter(this.result);

  final Future<List<SceneRegion>> result;
  final Completer<void> cancelled = Completer<void>();
  SmartSceneProposalHandle? operation;

  @override
  SmartSceneProposalHandle start(Uint8List encoded) =>
      operation = SmartSceneProposalHandle.fromFuture(
        result,
        onCancel: () {
          if (!cancelled.isCompleted) cancelled.complete();
        },
      );
}

class _FakeArtworkPathFacade implements ArtworkPathFacade {
  const _FakeArtworkPathFacade();

  @override
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request) async {
    final output = request.coordinateBounds;
    return ArtworkPathResult(
      analysis: SmartPathAnalysis(
        sections: [
          SmartPathSection(
            id: 'local',
            kind: SmartSectionKind.shape,
            bounds: output,
            label: 'Local',
            paths: [
              SmartGeneratedPath(points: [output.topLeft, output.bottomRight]),
            ],
            recommendedRevealWidth: 0.05 * output.height,
            mode: SmartSectionMode.handDraw,
          ),
        ],
      ),
    );
  }
}

class _CountingMultiRegionFacade implements ArtworkPathFacade {
  _CountingMultiRegionFacade(this.regions);

  final List<SceneRegion> regions;
  int calls = 0;
  bool unionGapWasTransparent = false;

  @override
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request) async {
    calls++;
    final decoded = raster.decodePng(request.previewBytes)!;
    unionGapWasTransparent =
        decoded.getPixel(decoded.width ~/ 2, decoded.height ~/ 2).a.toInt() ==
        0;
    request.onProgress?.call(
      const SmartPathProgress(
        stage: SmartPathProgressStage.tracingShapes,
        fraction: 0.5,
      ),
    );
    return ArtworkPathResult(
      analysis: SmartPathAnalysis(
        sections: [
          SmartPathSection(
            id: 'shared-analysis',
            kind: SmartSectionKind.shape,
            bounds: request.coordinateBounds,
            label: 'Shared',
            paths: [
              for (final region in regions)
                SmartGeneratedPath(
                  points: [
                    region.bounds.centerLeft + const Offset(0.01, 0),
                    region.bounds.centerRight - const Offset(0.01, 0),
                  ],
                ),
            ],
            recommendedRevealWidth: 0.01,
            mode: SmartSectionMode.handDraw,
          ),
        ],
      ),
    );
  }
}

class _MixedArtworkPathFacade implements ArtworkPathFacade {
  const _MixedArtworkPathFacade();

  @override
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request) async {
    final output = request.coordinateBounds;
    Offset point(double x, double y) =>
        Offset(output.left + x * output.width, output.top + y * output.height);
    Rect rect(double x, double y, double width, double height) => Rect.fromLTWH(
      output.left + x * output.width,
      output.top + y * output.height,
      width * output.width,
      height * output.height,
    );
    return ArtworkPathResult(
      analysis: SmartPathAnalysis(
        sections: [
          SmartPathSection(
            id: 'shape',
            kind: SmartSectionKind.shape,
            bounds: rect(0, 0, 0.5, 1),
            label: 'Shape',
            paths: [
              SmartGeneratedPath(points: [point(0, 0.5), point(0.5, 0.5)]),
            ],
            recommendedRevealWidth: 0.03 * output.height,
            mode: SmartSectionMode.handDraw,
          ),
          SmartPathSection(
            id: 'arabic',
            kind: SmartSectionKind.text,
            bounds: rect(0.5, 0, 0.5, 1),
            label: 'Arabic',
            paths: [],
            recommendedRevealWidth: 0.04 * output.height,
            mode: SmartSectionMode.revealText,
            rightToLeft: true,
          ),
          SmartPathSection(
            id: 'noise',
            kind: SmartSectionKind.shape,
            bounds: output,
            label: 'Noise',
            paths: [],
            recommendedRevealWidth: 0.01 * output.height,
            mode: SmartSectionMode.ignore,
          ),
        ],
      ),
    );
  }
}

class _FakeRegionAutoPathAnalyzer extends RegionAutoPathAnalyzer {
  const _FakeRegionAutoPathAnalyzer();

  @override
  Future<List<SmartPathSection>> analyze({
    required ui.Image source,
    required List<SceneRegion> regions,
    required ArtworkPathFacade facade,
    RegionAnalysisProgress? onProgress,
    bool Function()? isCancelled,
    SmartPathCancellationToken? cancellationToken,
  }) async => [
    for (var index = 0; index < regions.length; index++)
      SmartPathSection(
        id: regions[index].id,
        kind: SmartSectionKind.shape,
        bounds: regions[index].bounds,
        label: regions[index].name,
        paths: [
          SmartGeneratedPath(
            points: [
              regions[index].bounds.topLeft,
              regions[index].bounds.bottomRight,
            ],
          ),
        ],
        recommendedRevealWidth: 0.01,
        mode: SmartSectionMode.handDraw,
      ),
  ];
}

class _ThrowingRegionAutoPathAnalyzer extends RegionAutoPathAnalyzer {
  const _ThrowingRegionAutoPathAnalyzer();

  @override
  Future<List<SmartPathSection>> analyze({
    required ui.Image source,
    required List<SceneRegion> regions,
    required ArtworkPathFacade facade,
    RegionAnalysisProgress? onProgress,
    bool Function()? isCancelled,
    SmartPathCancellationToken? cancellationToken,
  }) => throw StateError('Auto Path must not run for scene reveal.');
}

class _ReverseInternalOrderRegionAnalyzer extends RegionAutoPathAnalyzer {
  const _ReverseInternalOrderRegionAnalyzer();

  @override
  Future<List<SmartPathSection>> analyze({
    required ui.Image source,
    required List<SceneRegion> regions,
    required ArtworkPathFacade facade,
    RegionAnalysisProgress? onProgress,
    bool Function()? isCancelled,
    SmartPathCancellationToken? cancellationToken,
  }) async => [
    for (final region in regions) ...[
      _section(region, 'lower', 0.75),
      _section(region, 'upper', 0.25),
    ],
  ];

  static SmartPathSection _section(
    SceneRegion region,
    String name,
    double verticalFraction,
  ) {
    final y = region.bounds.top + region.bounds.height * verticalFraction;
    final left = region.bounds.left + region.bounds.width * 0.15;
    final right = region.bounds.right - region.bounds.width * 0.15;
    return SmartPathSection(
      id: '${region.id}::$name',
      kind: SmartSectionKind.shape,
      bounds: Rect.fromLTRB(left, y - 0.02, right, y + 0.02),
      label: '${region.name} $name',
      paths: [
        SmartGeneratedPath(points: [Offset(left, y), Offset(right, y)]),
      ],
      recommendedRevealWidth: 0.01,
      mode: SmartSectionMode.handDraw,
    );
  }
}

class _DelayedRegionAutoPathAnalyzer extends RegionAutoPathAnalyzer {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<SmartPathSection>> analyze({
    required ui.Image source,
    required List<SceneRegion> regions,
    required ArtworkPathFacade facade,
    RegionAnalysisProgress? onProgress,
    bool Function()? isCancelled,
    SmartPathCancellationToken? cancellationToken,
  }) async {
    started.complete();
    await release.future;
    return [
      SmartPathSection(
        id: '${regions.single.id}::partial',
        kind: SmartSectionKind.shape,
        bounds: regions.single.bounds,
        label: regions.single.name,
        paths: [
          SmartGeneratedPath(
            points: [
              regions.single.bounds.topLeft,
              regions.single.bounds.bottomRight,
            ],
          ),
        ],
        recommendedRevealWidth: 0.01,
        mode: SmartSectionMode.handDraw,
      ),
    ];
  }
}

class _GatedSceneCloseEditorCubit extends EditorCubit {
  _GatedSceneCloseEditorCubit({required super.initialState});

  final started = Completer<void>();
  final release = Completer<void>();
  List<SceneRegion> confirmedRegions = const [];

  @override
  Future<bool> applyOrderedSceneReveals(List<SceneRegion> regions) async {
    confirmedRegions = List.unmodifiable(regions);
    started.complete();
    await release.future;
    return true;
  }
}

class _RacingRegionAutoPathAnalyzer extends RegionAutoPathAnalyzer {
  final firstStarted = Completer<void>();
  final secondStarted = Completer<void>();
  final failFirst = Completer<void>();
  final finishSecond = Completer<void>();
  var _calls = 0;

  @override
  Future<List<SmartPathSection>> analyze({
    required ui.Image source,
    required List<SceneRegion> regions,
    required ArtworkPathFacade facade,
    RegionAnalysisProgress? onProgress,
    bool Function()? isCancelled,
    SmartPathCancellationToken? cancellationToken,
  }) async {
    final call = _calls++;
    if (call == 0) {
      firstStarted.complete();
      await failFirst.future;
      throw StateError('stale analysis failed');
    }
    secondStarted.complete();
    await finishSecond.future;
    return [
      SmartPathSection(
        id: '${regions.single.id}::shape',
        kind: SmartSectionKind.shape,
        bounds: regions.single.bounds,
        label: regions.single.name,
        paths: [
          SmartGeneratedPath(
            points: [
              regions.single.bounds.topLeft,
              regions.single.bounds.bottomRight,
            ],
          ),
        ],
        recommendedRevealWidth: 0.01,
        mode: SmartSectionMode.handDraw,
      ),
    ];
  }
}

class _MixedRegionAutoPathAnalyzer extends RegionAutoPathAnalyzer {
  const _MixedRegionAutoPathAnalyzer();

  @override
  Future<List<SmartPathSection>> analyze({
    required ui.Image source,
    required List<SceneRegion> regions,
    required ArtworkPathFacade facade,
    RegionAnalysisProgress? onProgress,
    bool Function()? isCancelled,
    SmartPathCancellationToken? cancellationToken,
  }) async => [
    SmartPathSection(
      id: '${regions.single.id}::shape',
      kind: SmartSectionKind.shape,
      bounds: regions.single.bounds,
      label: 'Shape',
      paths: [
        SmartGeneratedPath(
          points: [regions.single.bounds.topLeft, regions.single.bounds.center],
        ),
      ],
      recommendedRevealWidth: 0.01,
      mode: SmartSectionMode.handDraw,
    ),
    SmartPathSection(
      id: '${regions.single.id}::text',
      kind: SmartSectionKind.text,
      bounds: regions.single.bounds,
      label: 'Text',
      paths: const [],
      recommendedRevealWidth: 0.02,
      mode: SmartSectionMode.revealText,
      rightToLeft: true,
    ),
  ];
}
