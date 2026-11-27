import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/image_animation/presentation/image_animation_panel.dart';
import 'support/legacy_editor_state_fixture.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_pause_point.dart';

EditorCubit fixture(String effect) => EditorCubit(
  initialState: testEditorState(
    project: HandDrawProject(
      imageAnimationEffect: effect,
      durationSeconds: 6,
      startDelaySeconds: .2,
      endHoldSeconds: .5,
      strokes: [
        DrawingStroke(
          id: 'line',
          name: 'line',
          sectionId: 'part',
          revealOnly: effect == 'reveal',
          points: const [Offset(.1, .5), Offset(.9, .5)],
        ),
      ],
      sectionTimings: const {
        'part': SectionTiming(
          animationDurationSeconds: 10,
          handExitAnimation: SectionHandExitAnimation.moveOut,
          handExitDurationSeconds: .3,
        ),
      },
    ),
  ),
);
void main() {
  test(
    'mixed section overrides, travel and stroke pauses retain proportions',
    () async {
      final c = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            strokes: [
              DrawingStroke(
                id: 'a',
                name: 'a',
                sectionId: 'a',
                points: const [Offset(.1, .1), Offset(.2, .2)],
                pausePoints: const [
                  StrokePausePoint(
                    id: 'pause',
                    progress: .5,
                    durationSeconds: .5,
                  ),
                ],
              ),
              DrawingStroke(
                id: 'b',
                name: 'b',
                sectionId: 'b',
                points: const [Offset(.8, .8), Offset(.9, .9)],
              ),
            ],
            sectionTimings: const {
              'a': SectionTiming(
                animationDurationSeconds: 8,
                pauseAfterEnabled: true,
                pauseAfterSeconds: .5,
                transitionAfterSeconds: .2,
              ),
            },
          ),
        ),
      );
      addTearDown(c.close);
      expect(c.setImageAnimationDuration(1), isTrue);
      expect(
        resolveProjectTimeline(c.project).durationSeconds,
        closeTo(1, .00001),
      );
      final preview = await c.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.preview,
      );
      final export = await c.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.export,
      );
      expect(identical(preview.timeline, export.timeline), isTrue);
      expect(export.timeline.duration.microseconds, closeTo(1000000, 10));
      expect(export.timeline.duration.microseconds, lessThanOrEqualTo(1000000));
      expect((export.timeline.duration.microseconds * 30 / 1000000).ceil(), 30);
      await preview.release();
      await export.release();
    },
  );

  for (final effect in ['reveal', 'drawPaint']) {
    test(
      '$effect duration includes explicit stroke timings and hand exit',
      () async {
        final c = fixture(effect);
        addTearDown(c.close);
        final before = c.state.document;
        final original = resolveProjectTimeline(c.project).durationSeconds;
        expect(original, greaterThan(10));
        final applied = c.setImageAnimationDuration(1);
        expect(applied, isTrue, reason: c.state.statusMessage);
        expect(
          resolveProjectTimeline(c.project).durationSeconds,
          closeTo(1, .00001),
        );
        expect(c.project.strokes.single.points, const [
          Offset(.1, .5),
          Offset(.9, .5),
        ]);
        expect(c.setImageAnimationDuration(20), isTrue);
        expect(
          resolveProjectTimeline(c.project).durationSeconds,
          closeTo(20, .0001),
        );
        c.undoStroke();
        expect(
          resolveProjectTimeline(c.project).durationSeconds,
          closeTo(1, .00001),
        );
        c.undoStroke();
        expect(
          c.state.document.motionConfiguration.drawingDuration,
          before.motionConfiguration.drawingDuration,
        );
        expect(
          resolveProjectTimeline(c.project).durationSeconds,
          closeTo(original, .00001),
        );
      },
    );
  }
  testWidgets('typing duration applies without Enter and retains focus', (
    tester,
  ) async {
    final c = fixture('reveal');
    addTearDown(c.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ImageAnimationPanel(
              cubit: c,
              onImportImage: () {},
              isPreviewing: false,
            ),
          ),
        ),
      ),
    );
    final field = find.byKey(const ValueKey('animation-duration'));
    await tester.enterText(field, '1');
    await tester.pump();
    expect(
      resolveProjectTimeline(c.project).durationSeconds,
      closeTo(1, .00001),
    );
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await tester.enterText(field, '12');
    await tester.pump();
    expect(
      resolveProjectTimeline(c.project).durationSeconds,
      closeTo(12, .0001),
    );
  });
}
