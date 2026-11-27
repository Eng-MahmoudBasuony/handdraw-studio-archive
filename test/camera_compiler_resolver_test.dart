import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/compiled_camera_track.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_projection.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_resolver.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_timeline_compiler.dart';
import 'package:handdraw_studio/features/camera/domain/services/simple_camera_view_adapter.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  const compiler = CameraTimelineCompiler();
  const resolver = CameraResolver();
  final key = TimelineDependencyKey(
    projectId: ProjectId('p'),
    documentRevision: 9,
  );

  test('empty and disabled tracks resolve default view', () {
    const outside = CameraView(centerX: -2, centerY: 3, viewportWidth: .001);
    for (final enabled in [true, false]) {
      final compiled = compiler.compile(
        track: ProjectCameraTrack(
          id: CameraTrackId('t'),
          enabled: enabled,
          defaultView: outside,
          shots: const [],
        ),
        dependencyKey: key,
      );
      expect(
        (resolver.resolveAt(compiled, TimelineTime.fromMicroseconds(99))
                as ResolvedSingleCameraView)
            .view,
        outside,
      );
      expect(compiled.contentEnd, TimelineTime.zero);
    }
  });

  test('move uses arrival semantics, hold, easing, and logarithmic zoom', () {
    const from = CameraView(centerX: 0, centerY: 0, viewportWidth: 1);
    const to = CameraView(centerX: 10, centerY: -4, viewportWidth: 4);
    for (final easing in CameraEasing.values) {
      final track = _compile(
        key,
        transition: CameraTransition(
          type: CameraTransitionType.move,
          duration: TimelineDuration.fromMicroseconds(400),
          easing: easing,
        ),
        from: from,
        to: to,
      );
      expect(_single(track, 599), from);
      expect(_single(track, 600), from);
      final middle = _single(track, 800);
      final easedMidpoint = switch (easing) {
        CameraEasing.linear || CameraEasing.easeInOut => .5,
        CameraEasing.easeIn => .25,
        CameraEasing.easeOut => .75,
      };
      expect(
        middle.viewportWidth,
        closeTo(math.exp(math.log(4) * easedMidpoint), 1e-12),
      );
      expect(_single(track, 999), isNot(to));
      expect(_single(track, 1000), to);
      expect(_single(track, 1999), to);
      expect(_single(track, 2000), to);
    }
  });

  test('cut changes exactly at arrival and fade exposes a typed blend', () {
    const from = CameraView.identity();
    const to = CameraView(centerX: 2, centerY: 2, viewportWidth: .5);
    final cut = _compile(
      key,
      transition: const CameraTransition(),
      from: from,
      to: to,
    );
    expect(_single(cut, 999), from);
    expect(_single(cut, 1000), to);
    final fade = _compile(
      key,
      transition: CameraTransition(
        type: CameraTransitionType.fade,
        duration: TimelineDuration.fromMicroseconds(400),
        easing: CameraEasing.linear,
      ),
      from: from,
      to: to,
    );
    final start =
        resolver.resolveAt(fade, TimelineTime.fromMicroseconds(600))
            as ResolvedCameraBlend;
    expect(start.targetOpacity, 0);
    expect(
      (resolver.resolveAt(fade, TimelineTime.fromMicroseconds(800))
              as ResolvedCameraBlend)
          .targetOpacity,
      .5,
    );
    expect(
      (resolver.resolveAt(fade, TimelineTime.fromMicroseconds(999))
              as ResolvedCameraBlend)
          .targetOpacity,
      closeTo(.9975, 1e-12),
    );
    expect(_single(fade, 1000), to);
  });

  test('shot boundaries cut explicitly and gaps/final time hold last view', () {
    const first = CameraView(centerX: 1, centerY: 1, viewportWidth: 1);
    const second = CameraView(centerX: 9, centerY: 9, viewportWidth: 1);
    final compiled = compiler.compile(
      track: ProjectCameraTrack(
        id: CameraTrackId('t'),
        shots: [_shot('a', 100, 200, first), _shot('b', 500, 100, second)],
      ),
      dependencyKey: key,
    );
    expect(
      (resolver.resolveAt(compiled, TimelineTime.fromMicroseconds(99))
              as ResolvedSingleCameraView)
          .view,
      const CameraView.identity(),
    );
    expect(
      _stateView(
        resolver.resolveAt(compiled, TimelineTime.fromMicroseconds(100)),
      ),
      first,
    );
    expect(
      _stateView(
        resolver.resolveAt(compiled, TimelineTime.fromMicroseconds(300)),
      ),
      first,
    );
    expect(
      _stateView(
        resolver.resolveAt(compiled, TimelineTime.fromMicroseconds(499)),
      ),
      first,
    );
    expect(
      _stateView(
        resolver.resolveAt(compiled, TimelineTime.fromMicroseconds(500)),
      ),
      second,
    );
    expect(
      _stateView(
        resolver.resolveAt(compiled, TimelineTime.fromMicroseconds(9999)),
      ),
      second,
    );
  });

  test('sequential and shuffled random seek are identical with 1000 shots', () {
    final shots = [
      for (var i = 0; i < 1000; i++)
        _shot(
          '$i',
          i * 1000,
          800,
          CameraView(
            centerX: i.toDouble(),
            centerY: -i.toDouble(),
            viewportWidth: 1,
          ),
        ),
    ];
    final compiled = compiler.compile(
      track: ProjectCameraTrack(id: CameraTrackId('large'), shots: shots),
      dependencyKey: key,
    );
    final times = [
      for (var i = 0; i < 5000; i++)
        TimelineTime.fromMicroseconds((i * 7919) % 1000000),
    ];
    final expected = {
      for (final time in times)
        time.microseconds: _signature(resolver.resolveAt(compiled, time)),
    };
    times.shuffle(math.Random(42));
    for (final time in times) {
      expect(
        _signature(resolver.resolveAt(compiled, time)),
        expected[time.microseconds],
      );
    }
  });

  test(
    'projection derives height, preserves outside centers, and does no rounding',
    () {
      final projection = const CameraProjectionCalculator().calculate(
        view: const CameraView(
          centerX: -2.25,
          centerY: 3.75,
          viewportWidth: .5,
        ),
        projectAspectRatio: 16 / 9,
        outputWidth: 1920.5,
        outputHeight: 1080.25,
      );
      expect(
        projection.worldHeight,
        closeTo(.5 * (16 / 9) / (1920.5 / 1080.25), 1e-12),
      );
      expect(projection.worldLeft, -2.5);
      expect(projection.outputWidth, 1920.5);
      expect(projection.normalizedViewportX(-2.25), .5);
    },
  );

  test(
    'single-view clips move automatically from previous to current view',
    () {
      const first = CameraView(centerX: 0, centerY: 0, viewportWidth: 1);
      const second = CameraView(centerX: 10, centerY: 4, viewportWidth: 4);
      final compiled = compiler.compile(
        track: ProjectCameraTrack(
          id: CameraTrackId('simple'),
          shots: [
            _shot('first', 0, 1000000, first),
            CameraShot(
              id: CameraShotId('second'),
              startTime: TimelineTime.fromMicroseconds(1000000),
              duration: TimelineDuration.fromMicroseconds(1000000),
              authorship: CameraAuthorship.manual,
              isLocked: false,
              keyframes: [
                CameraKeyframe(
                  id: CameraKeyframeId('second-view'),
                  offset: TimelineTime.zero,
                  view: second,
                  incomingTransition: CameraTransition(
                    type: CameraTransitionType.move,
                    duration: TimelineDuration.fromMicroseconds(400000),
                    easing: CameraEasing.linear,
                  ),
                ),
              ],
            ),
          ],
        ),
        dependencyKey: key,
      );
      expect(_single(compiled, 1000000), first);
      final midpoint = _single(compiled, 1200000);
      expect(midpoint.centerX, closeTo(5, 1e-12));
      expect(midpoint.centerY, closeTo(2, 1e-12));
      expect(midpoint.viewportWidth, closeTo(2, 1e-12));
      expect(_single(compiled, 1400000), second);
      expect(_single(compiled, 1900000), second);
    },
  );

  test(
    'simple Cut is immediate and Ease uses the selected movement duration',
    () {
      const first = CameraView(centerX: 0, centerY: 0, viewportWidth: 1);
      const target = CameraView(centerX: 8, centerY: 0, viewportWidth: .5);
      CompiledCameraTrack build(CameraTransition transition) =>
          compiler.compile(
            track: ProjectCameraTrack(
              id: CameraTrackId('simple'),
              shots: [
                _shot('first', 0, 1000, first),
                CameraShot(
                  id: CameraShotId('target'),
                  startTime: TimelineTime.fromMicroseconds(1000),
                  duration: TimelineDuration.fromMicroseconds(1000),
                  authorship: CameraAuthorship.manual,
                  isLocked: false,
                  keyframes: [
                    CameraKeyframe(
                      id: CameraKeyframeId('target-view'),
                      offset: TimelineTime.zero,
                      view: target,
                      incomingTransition: transition,
                    ),
                  ],
                ),
              ],
            ),
            dependencyKey: key,
          );
      expect(_single(build(const CameraTransition()), 1000), target);
      final eased = build(
        CameraTransition(
          type: CameraTransitionType.move,
          duration: TimelineDuration.fromMicroseconds(400),
          easing: CameraEasing.easeInOut,
        ),
      );
      expect(_single(eased, 1100).centerX, closeTo(1, 1e-12));
      expect(_single(eased, 1400), target);
    },
  );

  test('simple adapter stores only movement plus hold in the old schema', () {
    const adapter = SimpleCameraViewAdapter();
    final movement = TimelineDuration.fromMicroseconds(600000);
    final hold = TimelineDuration.fromMicroseconds(1400000);
    final transition = adapter.transitionFor(
      SimpleCameraMovement.ease,
      movement,
    );
    expect(transition.type, CameraTransitionType.move);
    expect(transition.easing, CameraEasing.easeInOut);
    expect(transition.duration, movement);
    expect(
      adapter
          .totalDuration(
            movement: SimpleCameraMovement.ease,
            movementDuration: movement,
            holdDuration: hold,
          )
          .microseconds,
      2000000,
    );
  });
}

CompiledCameraTrack _compile(
  TimelineDependencyKey key, {
  required CameraTransition transition,
  required CameraView from,
  required CameraView to,
}) => const CameraTimelineCompiler().compile(
  track: ProjectCameraTrack(
    id: CameraTrackId('t'),
    shots: [
      CameraShot(
        id: CameraShotId('s'),
        startTime: TimelineTime.zero,
        duration: TimelineDuration.fromMicroseconds(2000),
        authorship: CameraAuthorship.manual,
        isLocked: false,
        keyframes: [
          CameraKeyframe(
            id: CameraKeyframeId('a'),
            offset: TimelineTime.zero,
            view: from,
          ),
          CameraKeyframe(
            id: CameraKeyframeId('b'),
            offset: TimelineTime.fromMicroseconds(1000),
            view: to,
            incomingTransition: transition,
          ),
        ],
      ),
    ],
  ),
  dependencyKey: key,
);
CameraShot _shot(String id, int start, int duration, CameraView view) =>
    CameraShot(
      id: CameraShotId(id),
      startTime: TimelineTime.fromMicroseconds(start),
      duration: TimelineDuration.fromMicroseconds(duration),
      authorship: CameraAuthorship.manual,
      isLocked: false,
      keyframes: [
        CameraKeyframe(
          id: CameraKeyframeId('k$id'),
          offset: TimelineTime.zero,
          view: view,
        ),
      ],
    );
CameraView _single(CompiledCameraTrack track, int us) => _stateView(
  const CameraResolver().resolveAt(track, TimelineTime.fromMicroseconds(us)),
);
CameraView _stateView(ResolvedCameraState state) =>
    (state as ResolvedSingleCameraView).view;
String _signature(ResolvedCameraState state) => switch (state) {
  ResolvedSingleCameraView(:final view) =>
    's:${view.centerX}:${view.centerY}:${view.viewportWidth}',
  ResolvedCameraBlend(:final fromView, :final toView, :final targetOpacity) =>
    'b:${fromView.centerX}:${toView.centerX}:$targetOpacity',
};
