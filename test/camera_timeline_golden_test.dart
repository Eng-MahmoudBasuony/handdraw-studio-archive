import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_timeline_dock.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  testWidgets('empty Camera Track golden', (tester) async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(TimelineTime.zero);
    cubit.deleteCameraShots({
      cubit.state.document.cameraTrack!.shots.single.id,
    });
    await _pump(tester, cubit);
    await expectLater(
      _boundary,
      matchesGoldenFile('goldens/camera_track_empty.png'),
    );
  });

  testWidgets('normal clips keyframes and transition regions golden', (
    tester,
  ) async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(TimelineTime.zero);
    cubit.addCameraShotAt(
      TimelineTime.fromDuration(const Duration(seconds: 2)),
    );
    final shot = cubit.state.document.cameraTrack!.shots.last;
    cubit.addCameraKeyframe(
      shot.id,
      TimelineTime.fromDuration(const Duration(seconds: 1)),
      const CameraView(centerX: .7, centerY: .5, viewportWidth: .6),
      transition: CameraTransition(
        type: CameraTransitionType.fade,
        duration: TimelineDuration.fromDuration(
          const Duration(milliseconds: 500),
        ),
        easing: CameraEasing.easeInOut,
      ),
    );
    await _pump(tester, cubit);
    await expectLater(
      _boundary,
      matchesGoldenFile('goldens/camera_track_clips.png'),
    );
  });

  testWidgets('selected multi auto manual and locked golden', (tester) async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(TimelineTime.zero);
    cubit.addCameraShotAt(
      TimelineTime.fromDuration(const Duration(seconds: 2)),
    );
    final shots = cubit.state.document.cameraTrack!.shots;
    cubit.setCameraShotAuthorship(shots.first.id, CameraAuthorship.auto);
    cubit.setCameraShotsLocked({shots.last.id}, true);
    await _pump(tester, cubit);
    final painter = find.byKey(const ValueKey('camera-clips-painter'));
    final topLeft = tester.getTopLeft(painter);
    await tester.tapAt(topLeft + const Offset(160, 20));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.tapAt(topLeft + const Offset(610, 20));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump(const Duration(milliseconds: 60));
    await expectLater(
      _boundary,
      matchesGoldenFile('goldens/camera_track_selection_states.png'),
    );
  });

  testWidgets('disabled Camera Track golden', (tester) async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(TimelineTime.zero);
    cubit.setCameraTrackEnabled(false);
    await _pump(tester, cubit);
    await expectLater(
      _boundary,
      matchesGoldenFile('goldens/camera_track_disabled.png'),
    );
  });

  testWidgets('invalid transient overlap golden', (tester) async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(TimelineTime.zero);
    cubit.addCameraShotAt(
      TimelineTime.fromDuration(const Duration(seconds: 3)),
    );
    await _pump(tester, cubit);
    final rect = tester.getRect(
      find.byKey(const ValueKey('camera-clips-painter')),
    );
    final gesture = await tester.startGesture(
      Offset(rect.left + 180, rect.center.dy),
    );
    await gesture.moveBy(const Offset(400, 0));
    await tester.pump();
    await expectLater(
      _boundary,
      matchesGoldenFile('goldens/camera_track_invalid_transient.png'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 60));
  });

  testWidgets('Arabic RTL shell keeps timeline LTR golden', (tester) async {
    final cubit = EditorCubit();
    addTearDown(cubit.close);
    cubit.addCameraShotAt(TimelineTime.zero);
    await _pump(tester, cubit, locale: const Locale('ar'));
    await expectLater(
      _boundary,
      matchesGoldenFile('goldens/camera_track_arabic_ltr.png'),
    );
  });
}

Finder get _boundary => find.byKey(const ValueKey('camera-golden-boundary'));

Future<void> _pump(
  WidgetTester tester,
  EditorCubit cubit, {
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 320));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('camera-golden-boundary'),
          child: EditorTimelineDock(
            cubit: cubit,
            previewProgress: 0,
            isPreviewing: false,
            onSeek: (_) {},
            onPreviewStroke: (_) {},
            onTimingChangeStart: () {},
            onTimingChangeEnd: () {},
            playheadTime: TimelineTime.zero,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 60));
}
