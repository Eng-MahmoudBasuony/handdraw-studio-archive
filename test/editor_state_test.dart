import 'dart:typed_data';

import 'support/legacy_editor_state_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_library_repository.dart';

void main() {
  test(
    'copyWith preserves values and can explicitly clear nullable fields',
    () {
      final original = testEditorState(
        project: HandDrawProject(),
        selectedStrokeIndex: 2,
        selectedSmartSectionId: 'title',
        activeStroke: const [Offset(0.1, 0.2)],
      );

      final updated = original.copyWith(
        statusMessage: 'Updated',
        selectedStrokeIndex: null,
        selectedSmartSectionId: null,
      );

      expect(updated.documentState, same(original.documentState));
      expect(updated.activeStroke, original.activeStroke);
      expect(updated.selectedStrokeIndex, isNull);
      expect(updated.selectedSmartSectionId, isNull);
      expect(updated.statusMessage, 'Updated');
    },
  );

  test('cubit emits a new project without mutating the previous state', () {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    final before = cubit.state;

    cubit.setDuration(12);

    expect(
      before.document.duration.microseconds / Duration.microsecondsPerSecond,
      6,
    );
    expect(cubit.state, isNot(same(before)));
    expect(cubit.state.document, isNot(same(before.document)));
    expect(cubit.project.durationSeconds, 12);
    expect(cubit.project.drawingDurationSeconds, closeTo(10.7, 0.0001));
    expect(cubit.project.startDelaySeconds, 0.4);
    expect(cubit.project.endHoldSeconds, 0.9);
  });

  test('global drawing speed is immutable and does not alter holds', () {
    final cubit = EditorCubit();
    addTearDown(cubit.close);

    cubit.setDrawingSpeed(0.5);

    expect(cubit.project.drawingSpeed, 0.5);
    expect(cubit.project.startDelaySeconds, 0.4);
    expect(cubit.project.endHoldSeconds, 0.9);
  });

  test('global drawing speed reaches the professional 8x ceiling', () {
    final cubit = EditorCubit();
    addTearDown(cubit.close);

    cubit.setDrawingSpeed(20);

    expect(cubit.project.drawingSpeed, maximumProjectDrawingSpeed);
    expect(cubit.project.drawingSpeed, 8);
    expect(cubit.project.startDelaySeconds, 0.4);
    expect(cubit.project.endHoldSeconds, 0.9);
  });

  test('section dialog saves the resolved duration as a 1x baseline', () {
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          drawingSpeed: 5.35,
          startDelaySeconds: 0,
          endHoldSeconds: 0,
          strokes: [
            DrawingStroke(
              id: 'fast-section',
              name: 'Fast section',
              sectionId: 'fast-section',
              points: const [Offset(0.1, 0.5), Offset(0.7, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);

    cubit.setTimelineSectionDurations(
      sectionId: 'fast-section',
      animationSeconds: 0.21,
      speedMultiplier: 1,
      pauseSeconds: 0,
      transitionSeconds: 0,
      pauseBeforeSeconds: 0,
      pauseBeforeEnabled: false,
      pauseAfterEnabled: false,
      handEntranceAnimation: SectionHandEntranceAnimation.none,
      handEntranceDurationSeconds: 0,
      handExitAnimation: SectionHandExitAnimation.none,
      handExitDurationSeconds: 0,
      keepHandVisibleAfterDrawing: false,
    );

    expect(
      cubit.sectionTiming('section:fast-section').animationDurationSeconds,
      closeTo(0.21 * 5.35, 0.000001),
    );
    expect(
      resolveProjectTimeline(cubit.project).breakdown.drawingSeconds,
      closeTo(0.21, 0.000001),
    );
  });

  test('fit to duration is undoable and preserves travel speed', () {
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          penTravelSpeed: 1.5,
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
    final target = projectTimelineDuration(
      cubit.project.copyWith(drawingSpeed: 2),
    );

    final result = cubit.fitToDuration(target);
    expect(result.isSuccess, isTrue);
    expect(cubit.project.drawingSpeed, closeTo(2, 1e-6));
    expect(cubit.project.penTravelSpeed, 1.5);

    cubit.undoStroke();
    expect(cubit.project.drawingSpeed, 1);
    expect(cubit.project.penTravelSpeed, 1.5);
    cubit.redoStroke();
    expect(cubit.project.drawingSpeed, closeTo(2, 1e-6));
  });

  test('project and stroke collections are read-only', () {
    final project = HandDrawProject(
      strokes: [
        DrawingStroke(
          id: 'one',
          name: 'One',
          points: const [Offset.zero, Offset(1, 1)],
        ),
      ],
    );

    expect(
      () => project.strokes.add(
        DrawingStroke(
          id: 'two',
          name: 'Two',
          points: const [Offset.zero, Offset(1, 1)],
        ),
      ),
      throwsUnsupportedError,
    );
    expect(
      () => project.strokes.first.points.add(const Offset(0.5, 0.5)),
      throwsUnsupportedError,
    );
    expect(
      () => project.sectionTimings['stroke:one'] = const SectionTiming(),
      throwsUnsupportedError,
    );
  });

  test('drag reordering preserves stroke data and follows selection', () {
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'first',
              name: 'First',
              points: const [Offset.zero, Offset(0.5, 0.5)],
            ),
            DrawingStroke(
              id: 'second',
              name: 'Second',
              points: const [Offset(0.5, 0.5), Offset(1, 1)],
              reversed: true,
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);

    cubit.reorderStroke(0, 1);

    expect(cubit.project.strokes.map((stroke) => stroke.id), [
      'second',
      'first',
    ]);
    expect(cubit.project.strokes.first.reversed, isTrue);
    expect(cubit.selectedStrokeIndex, 1);
  });

  test('new projects use real paper pencil as the default writing sound', () {
    final project = HandDrawProject();
    expect(project.writingSoundPreset, WritingSoundPreset.recordedPencilPaper);
  });

  test('editor starts with the wheat technical pen as the default hand', () {
    final state = EditorState.initial();
    expect(state.selectedHandPresetId, BuiltInHands.defaultPresetId);
    expect(state.selectedHandPreset, BuiltInHands.wheatTechnicalPenRight);
    expect(
      state.document.handConfiguration.presetId,
      BuiltInHands.wheatTechnicalPenRight.id,
    );
    expect(
      state.document.handConfiguration.penTip,
      const DocumentPoint(0.114583, 0.485677),
    );
    final cubit = EditorCubit(initialState: state);
    addTearDown(cubit.close);
    expect(cubit.project.penTip, BuiltInHands.wheatTechnicalPenRight.penTip);
  });

  test(
    'reset defaults uses the active hand calibration for every preset',
    () async {
      for (final preset in BuiltInHands.all) {
        final cubit = EditorCubit(
          initialState: testEditorState(
            project: HandDrawProject(
              handPresetId: preset.id,
              handScale: .63,
              handRotationDegrees: 37,
              handFlipX: !preset.flipX,
              // Reproduces the cross-preset Technical Pen anchor from the bug.
              penTip: BuiltInHands.wheatTechnicalPenRight.penTip,
            ),
            selectedHandPresetId: preset.id,
          ),
        );

        cubit.resetDefaultSettings();

        expect(cubit.project.handPresetId, preset.id, reason: preset.name);
        expect(cubit.project.penTip, preset.penTip, reason: preset.name);
        expect(
          cubit.project.handScale,
          preset.defaultScale,
          reason: preset.name,
        );
        expect(
          cubit.project.handRotationDegrees,
          preset.defaultRotationDegrees,
          reason: preset.name,
        );
        expect(cubit.project.handFlipX, preset.flipX, reason: preset.name);
        await cubit.close();
      }
    },
  );

  test(
    'inspector project and hand controls update immutable project state',
    () {
      final cubit = EditorCubit();
      addTearDown(cubit.close);

      cubit.setStartDelay(1.25);
      cubit.setEndHold(2.5);
      cubit.setHandFlipX(true);

      expect(cubit.project.startDelaySeconds, 1.25);
      expect(cubit.project.endHoldSeconds, 2.5);
      expect(cubit.project.handFlipX, isTrue);
    },
  );

  test(
    'selected hand settings remain defaults after changing project',
    () async {
      final repository = _RecordingHandLibraryRepository();
      final cubit = EditorCubit(
        handLibraryRepository: repository,
        initialState: testEditorState(
          project: HandDrawProject(
            handPresetId: BuiltInHands.markerRight.id,
            strokes: [
              DrawingStroke(
                id: 'line',
                name: 'Line',
                sectionId: 'line',
                points: const [Offset(.1, .5), Offset(.9, .5)],
              ),
            ],
          ),
          selectedHandPresetId: BuiltInHands.markerRight.id,
        ),
      );

      cubit.setHandScale(0.58);
      cubit.setHandRotation(17);
      cubit.setHandFlipX(true);
      cubit.setKeepHandVisibleAfterDrawing(true);
      cubit.newProject();

      expect(cubit.project.handPresetId, BuiltInHands.markerRight.id);
      expect(cubit.project.handScale, 0.58);
      expect(cubit.project.handRotationDegrees, 17);
      expect(cubit.project.handFlipX, isTrue);
      expect(cubit.keepHandVisibleAfterDrawing, isTrue);

      await cubit.close();
      final saved = repository.savedSnapshot!;
      expect(saved.selectedPresetId, BuiltInHands.markerRight.id);
      expect(saved.resolvedApplicationDefaults.scale, 0.58);
      expect(saved.resolvedApplicationDefaults.rotationDegrees, 17);
      expect(saved.resolvedApplicationDefaults.flipX, isTrue);
      expect(
        saved.resolvedApplicationDefaults.keepHandVisibleAfterDrawing,
        isTrue,
      );
    },
  );

  test('advanced timing edits support command-style undo and redo', () {
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
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

    cubit.beginSectionTimingEdit();
    cubit.setSectionPauseAfter('stroke:package-a', 2);
    cubit.commitSectionTimingEdit();
    expect(
      cubit.project.sectionTimings['stroke:package-a']!.pauseAfterSeconds,
      2,
    );

    cubit.undoStroke();
    expect(cubit.project.sectionTimings, isEmpty);
    cubit.redoStroke();
    expect(
      cubit.project.sectionTimings['stroke:package-a']!.pauseAfterSeconds,
      2,
    );
  });

  test('voice cues reject impossible starts and support undo and redo', () {
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          voiceGuide: VoiceGuide(
            path: '/tmp/voice.wav',
            name: 'voice.wav',
            durationSeconds: 20,
            waveform: const [0.2, 0.8],
          ),
          strokes: [
            DrawingStroke(
              id: 'a',
              name: 'A',
              sectionId: 'a',
              points: const [Offset(0.1, 0.3), Offset(0.8, 0.3)],
            ),
            DrawingStroke(
              id: 'b',
              name: 'B',
              sectionId: 'b',
              points: const [Offset(0.1, 0.7), Offset(0.8, 0.7)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);
    final secondKey = buildTimelineSections(cubit.project.strokes)[1].key;

    expect(cubit.setSectionVoiceCue(secondKey, 0.1), isFalse);
    expect(cubit.sectionTiming(secondKey).voiceCueSeconds, isNull);

    expect(cubit.setSectionVoiceCue(secondKey, 5), isTrue);
    expect(cubit.sectionTiming(secondKey).voiceCueSeconds, 5);
    cubit.undoStroke();
    expect(cubit.sectionTiming(secondKey).voiceCueSeconds, isNull);
    cubit.redoStroke();
    expect(cubit.sectionTiming(secondKey).voiceCueSeconds, 5);
  });

  test('pause points support add, reverse, undo, redo, and delete', () {
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'line',
              name: 'Line',
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
            ),
          ],
        ),
      ),
    );
    addTearDown(cubit.close);

    cubit.addStrokePausePoint(
      0,
      progress: 0.3,
      durationSeconds: 0.8,
      keepHandVisible: true,
    );
    final pauseId = cubit.project.strokes.single.pausePoints.single.id;
    expect(cubit.project.strokes.single.pausePoints.single.progress, 0.3);

    cubit.reverseStroke(0);
    expect(cubit.project.strokes.single.reversed, isTrue);
    expect(
      cubit.project.strokes.single.pausePoints.single.progress,
      closeTo(0.7, 0.0001),
    );

    cubit.undoStroke();
    expect(cubit.project.strokes.single.reversed, isFalse);
    expect(cubit.project.strokes.single.pausePoints.single.progress, 0.3);
    cubit.redoStroke();
    expect(cubit.project.strokes.single.reversed, isTrue);

    cubit.deleteStrokePausePoint(0, pauseId);
    expect(cubit.project.strokes.single.pausePoints, isEmpty);
    cubit.undoStroke();
    expect(cubit.project.strokes.single.pausePoints.single.id, pauseId);
  });
}

final class _RecordingHandLibraryRepository implements HandLibraryRepository {
  HandLibrarySnapshot? savedSnapshot;

  @override
  Future<HandLibrarySnapshot> load() async => const HandLibrarySnapshot(
    presets: BuiltInHands.all,
    selectedPresetId: BuiltInHands.defaultPresetId,
  );

  @override
  Future<HandLibrarySnapshot> importCustom({
    required HandLibrarySnapshot current,
    required String sourcePath,
    required Uint8List bytes,
  }) => throw UnimplementedError();

  @override
  Future<void> save(HandLibrarySnapshot snapshot) async {
    savedSnapshot = snapshot;
  }
}
