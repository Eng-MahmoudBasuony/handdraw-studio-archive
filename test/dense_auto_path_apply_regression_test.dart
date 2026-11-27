import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  test('dense Auto Path commit yields to the UI event loop', () async {
    final section = _denseSection(8062);
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(),
        smartSections: [section],
      ),
    );
    addTearDown(cubit.close);

    var heartbeatRan = false;
    final watch = Stopwatch()..start();
    var lastHeartbeat = Duration.zero;
    var longestUiGap = Duration.zero;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = watch.elapsed;
      final gap = now - lastHeartbeat;
      if (gap > longestUiGap) longestUiGap = gap;
      lastHeartbeat = now;
      heartbeatRan = true;
    });
    final applied = await cubit.applySmartPathSuggestions();
    heartbeat.cancel();
    final finalGap = watch.elapsed - lastHeartbeat;
    if (finalGap > longestUiGap) longestUiGap = finalGap;

    expect(applied, isTrue);
    expect(heartbeatRan, isTrue);
    expect(cubit.project.strokes, hasLength(section.paths.length));
    expect(
      longestUiGap,
      lessThan(const Duration(milliseconds: 500)),
      reason:
          'No planning, conversion, validation, or commit phase may freeze '
          'the UI for half a second on the 8062-path regression fixture.',
    );
  });

  test('dense Auto Path finalization can be cancelled before commit', () async {
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(),
        smartSections: [_denseSection(2048)],
      ),
    );
    addTearDown(cubit.close);
    var checks = 0;

    final applied = await cubit.applySmartPathSuggestions(
      isCancelled: () => ++checks >= 4,
    );

    expect(applied, isFalse);
    expect(cubit.project.strokes, isEmpty);
    expect(cubit.state.isAnalyzingSmartPaths, isFalse);
  });

  test(
    'discard during a yielded finalization prevents a late commit',
    () async {
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(),
          smartSections: [_denseSection(8062)],
        ),
      );
      addTearDown(cubit.close);
      final baselineDocument = cubit.state.document;
      var discarded = false;

      Timer.run(() {
        discarded = true;
        cubit.clearSmartPathSuggestions();
      });
      final applied = await cubit.applySmartPathSuggestions();

      expect(discarded, isTrue);
      expect(applied, isFalse);
      expect(identical(cubit.state.document, baselineDocument), isTrue);
      expect(cubit.project.strokes, isEmpty);
      expect(cubit.state.smartSections, isEmpty);
      expect(cubit.state.isAnalyzingSmartPaths, isFalse);
      expect(cubit.state.smartPathProgress, isNull);
      expect(cubit.state.smartPathAnalysisElapsed, Duration.zero);
      expect(cubit.state.statusMessage, 'Auto Path suggestions cleared.');
    },
  );

  test(
    'a newer dense Apply cancels the old worker without late commit',
    () async {
      final section = _denseSection(8062);
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(),
          smartSections: [section],
        ),
      );
      addTearDown(cubit.close);

      final oldApply = cubit.applySmartPathSuggestions();
      await _waitForWorkerToStart();
      final newApply = cubit.applySmartPathSuggestions();

      expect(await oldApply, isFalse);
      expect(await newApply, isTrue);
      expect(cubit.project.strokes, hasLength(section.paths.length));
      expect(cubit.state.autoPathResult?.pathCount, section.paths.length);
    },
  );

  test(
    'dense text exclusions stay shared from Editor through legacy and reload',
    () async {
      const textCount = 64;
      const pathCount = 1024;
      final shapeSection = _denseSection(pathCount);
      final textSections = List.generate(textCount, _textSection);
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(),
          smartSections: [...textSections, shapeSection],
        ),
      );
      addTearDown(cubit.close);

      expect(await cubit.applySmartPathSuggestions(), isTrue);

      final documentShapes = cubit.state.document.strokes
          .where((stroke) => stroke.sectionId.value == shapeSection.id)
          .toList(growable: false);
      expect(documentShapes, hasLength(pathCount));
      final documentExclusions = documentShapes.first.exclusionBounds;
      expect(documentExclusions, hasLength(textCount));
      final expectedFirst = _expectedExclusion(textSections.first.bounds);
      expect(documentExclusions.first.left, expectedFirst.left);
      expect(documentExclusions.first.top, expectedFirst.top);
      expect(documentExclusions.first.right, expectedFirst.right);
      expect(documentExclusions.first.bottom, expectedFirst.bottom);
      for (final stroke in documentShapes.skip(1)) {
        expect(identical(stroke.exclusionBounds, documentExclusions), isTrue);
      }

      final legacyShapes = cubit.project.strokes
          .where((stroke) => stroke.sectionId == shapeSection.id)
          .toList(growable: false);
      expect(legacyShapes, hasLength(pathCount));
      final legacyExclusions = legacyShapes.first.exclusionBounds;
      expect(legacyExclusions, hasLength(textCount));
      expect(legacyExclusions.first, expectedFirst);
      for (final stroke in legacyShapes.skip(1)) {
        expect(identical(stroke.exclusionBounds, legacyExclusions), isTrue);
      }

      const codec = DevelopmentProjectManifestCodec();
      final reopened = codec.decode(codec.encode(cubit.state.document));
      final reopenedShapes = reopened.strokes
          .where((stroke) => stroke.sectionId.value == shapeSection.id)
          .toList(growable: false);
      expect(reopenedShapes, hasLength(pathCount));
      final reopenedExclusions = reopenedShapes.first.exclusionBounds;
      expect(
        [
          for (final rect in reopenedExclusions)
            (rect.left, rect.top, rect.right, rect.bottom),
        ],
        [
          for (final rect in documentExclusions)
            (rect.left, rect.top, rect.right, rect.bottom),
        ],
      );
      for (final stroke in reopenedShapes.skip(1)) {
        expect(identical(stroke.exclusionBounds, reopenedExclusions), isTrue);
      }
    },
  );
}

Future<void> _waitForWorkerToStart() async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (debugAutoPathPlannerActiveWorkers > 0) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Auto Path worker did not start.');
}

SmartPathSection _denseSection(int count) => SmartPathSection(
  id: 'dense-scene',
  kind: SmartSectionKind.shape,
  bounds: const Rect.fromLTWH(0, 0, 1, 1),
  label: 'Dense scene',
  paths: List.generate(count, (index) {
    final x = ((index * 7919) % 9973) / 10500 + 0.015;
    final y = ((index * 6151 + 17) % 9967) / 10500 + 0.015;
    final angle = (index * 0.61803398875) % (math.pi * 2);
    final delta = Offset(math.cos(angle), math.sin(angle)) * 0.004;
    final start = Offset(x.clamp(0.01, 0.98), y.clamp(0.01, 0.98));
    final end = Offset(
      (start.dx + delta.dx).clamp(0.001, 0.999),
      (start.dy + delta.dy).clamp(0.001, 0.999),
    );
    return SmartGeneratedPath(points: [start, end]);
  }),
  recommendedRevealWidth: 0.008,
  mode: SmartSectionMode.handDraw,
);

SmartPathSection _textSection(int index) {
  final column = index % 8;
  final row = index ~/ 8;
  final bounds = Rect.fromLTWH(
    0.015 + column * 0.12,
    0.015 + row * 0.115,
    0.075,
    0.05,
  );
  return SmartPathSection(
    id: 'text-$index',
    kind: SmartSectionKind.text,
    bounds: bounds,
    label: 'Text $index',
    paths: [
      SmartGeneratedPath(points: [bounds.centerLeft, bounds.centerRight]),
    ],
    recommendedRevealWidth: 0.006,
    mode: SmartSectionMode.revealText,
  );
}

Rect _expectedExclusion(Rect bounds) =>
    bounds.inflate(0.003).intersect(const Rect.fromLTWH(0, 0, 1, 1));
