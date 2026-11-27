import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_pause_point.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

void main() {
  test(
    'filled SVG animates across its center while keeping boundary nodes',
    () {
      final boundary = StrokePathGeometry(
        start: const Offset(0.2, 0.2),
        segments: const [
          StrokeLineSegment(end: Offset(0.8, 0.2)),
          StrokeLineSegment(end: Offset(0.8, 0.6)),
          StrokeLineSegment(end: Offset(0.2, 0.6)),
        ],
        closed: true,
      );
      final reveal = StrokePathGeometry(
        start: const Offset(0.2, 0.4),
        segments: const [StrokeLineSegment(end: Offset(0.8, 0.4))],
      );
      final stroke = DrawingStroke(
        id: 'filled-card',
        name: 'Filled card',
        geometry: boundary,
        animationGeometry: reveal,
        isFilledShape: true,
        revealStyle: RevealMaskStyle.directionalWipe,
      );
      const artwork = Rect.fromLTWH(0, 0, 1000, 500);

      final path = buildDrawingStrokePath(stroke, artwork);
      final metric = path.computeMetrics().single;
      expect(metric.getTangentForOffset(0)!.position, const Offset(200, 200));
      expect(stroke.orderedGeometry!.start, const Offset(0.2, 0.2));

      final snapshot = buildTimelineSnapshot(
        strokes: [stroke],
        artworkRect: artwork,
        progress: 0.5,
        durationSeconds: 1,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
      );
      expect(snapshot.handPosition.dy, closeTo(200, 0.001));
      expect(snapshot.handVisible, isTrue);
    },
  );

  test('shorter and longer scenes keep identical normalized hand motion', () {
    final strokes = [
      DrawingStroke(
        id: 'duration-safe-line',
        name: 'Duration safe line',
        points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
      ),
    ];
    const artwork = Rect.fromLTWH(0, 0, 1920, 1080);

    TimelineSnapshot snapshotFor(double duration) => buildTimelineSnapshot(
      strokes: strokes,
      artworkRect: artwork,
      progress: 0.5,
      durationSeconds: duration,
      startDelaySeconds: duration * (0.4 / 6),
      endHoldSeconds: duration * (0.9 / 6),
    );

    final reference = snapshotFor(6);
    final referenceRevealLength = _revealedLength(reference);
    for (final duration in [1.0, 3.0, 12.0, 30.0]) {
      final snapshot = snapshotFor(duration);
      expect(snapshot.handVisible, reference.handVisible);
      expect(snapshot.drawingComplete, reference.drawingComplete);
      expect(snapshot.revealedPaths.length, reference.revealedPaths.length);
      expect(
        snapshot.handPosition.dx,
        closeTo(reference.handPosition.dx, 0.01),
      );
      expect(
        snapshot.handPosition.dy,
        closeTo(reference.handPosition.dy, 0.01),
      );
      expect(_revealedLength(snapshot), closeTo(referenceRevealLength, 0.01));
    }
  });

  test('hand articulates naturally around the exact pen point', () {
    final strokes = [
      DrawingStroke(
        id: 'curve',
        name: 'Curve',
        points: const [
          Offset(0.1, 0.5),
          Offset(0.3, 0.1),
          Offset(0.5, 0.9),
          Offset(0.7, 0.2),
          Offset(0.9, 0.5),
        ],
      ),
    ];

    final angles = <double>[];
    for (final progress in [0.2, 0.35, 0.5, 0.65, 0.8]) {
      final snapshot = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: const Rect.fromLTWH(0, 0, 1920, 1080),
        progress: progress,
      );
      angles.add(snapshot.handAngle);
      expect(snapshot.cursor?.worldPenPoint, snapshot.handPosition);
      expect(snapshot.handAngle.abs(), lessThanOrEqualTo(12 * math.pi / 180));
    }
    expect(angles.any((angle) => angle.abs() > 0.01), isTrue);
    expect(angles.toSet().length, greaterThan(2));
  });

  test('natural wrist angle is resolution independent', () {
    final stroke = DrawingStroke(
      id: 'scaled-writing-line',
      name: 'Scaled writing line',
      revealWidth: 120,
      points: const [Offset(0.1, 0.45), Offset(0.9, 0.55)],
    );

    TimelineSnapshot atScale(double scale) => buildTimelineSnapshot(
      strokes: [stroke],
      artworkRect: Rect.fromLTWH(0, 0, 1000 * scale, 500 * scale),
      timingRect: const Rect.fromLTWH(0, 0, 1000, 500),
      progress: 0.37,
      durationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
    );

    expect(atScale(0.5).handAngle, closeTo(atScale(1).handAngle, 0.000001));
    expect(atScale(2).handAngle, closeTo(atScale(1).handAngle, 0.000001));
  });

  test(
    'draws at constant arc speed instead of restarting easing per stroke',
    () {
      final stroke = DrawingStroke(
        id: 'steady-line',
        name: 'Steady line',
        points: const [Offset(0, 0.5), Offset(1, 0.5)],
      );

      Offset positionAt(double progress) => buildTimelineSnapshot(
        strokes: [stroke],
        artworkRect: const Rect.fromLTWH(0, 0, 1000, 1000),
        progress: progress,
        durationSeconds: 1,
      ).handPosition;

      expect(positionAt(0.25).dx, closeTo(250, 0.01));
      expect(positionAt(0.50).dx, closeTo(500, 0.01));
      expect(positionAt(0.75).dx, closeTo(750, 0.01));
    },
  );

  test('dense auto paths reserve most scene time for visible drawing', () {
    final strokes = List.generate(85, (index) {
      final row = index ~/ 17;
      final column = index % 17;
      final x = 0.03 + column * 0.055;
      final y = 0.15 + row * 0.15;
      return DrawingStroke(
        id: 'dense-$index',
        name: 'Dense $index',
        points: [Offset(x, y), Offset(x + 0.025, y)],
      );
    });

    var visibleSamples = 0;
    const sampleCount = 1000;
    for (var index = 0; index < sampleCount; index++) {
      final snapshot = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: const Rect.fromLTWH(0, 0, 1920, 1080),
        progress: (index + 0.5) / sampleCount,
        durationSeconds: 6,
      );
      if (snapshot.handVisible) visibleSamples++;
    }

    expect(visibleSamples / sampleCount, greaterThan(0.85));
  });

  test('separates vertically stacked drawing sections automatically', () {
    final strokes = [
      DrawingStroke(
        id: 'title-main',
        name: 'Title main',
        points: const [Offset(0.1, 0.1), Offset(0.1, 0.2)],
      ),
      DrawingStroke(
        id: 'title-bar',
        name: 'Title bar',
        points: const [Offset(0.1, 0.12), Offset(0.3, 0.12)],
      ),
      DrawingStroke(
        id: 'underline',
        name: 'Underline',
        points: const [Offset(0.2, 0.24), Offset(0.8, 0.24)],
      ),
      DrawingStroke(
        id: 'caption',
        name: 'Caption',
        points: const [Offset(0.2, 0.32), Offset(0.8, 0.32)],
      ),
    ];

    expect(detectAutomaticSections(strokes), [0, 0, 1, 2]);
    expect(automaticSectionCount(strokes), 3);
  });

  test('standalone reveal-only stroke is written by the hand', () {
    final stroke = DrawingStroke(
      id: 'rtl-text',
      name: 'RTL text reveal',
      revealOnly: true,
      points: const [Offset(0.9, 0.5), Offset(0.1, 0.5)],
    );

    final early = buildTimelineSnapshot(
      strokes: [stroke],
      artworkRect: const Rect.fromLTWH(0, 0, 100, 100),
      progress: 0.25,
    );
    final late = buildTimelineSnapshot(
      strokes: [stroke],
      artworkRect: const Rect.fromLTWH(0, 0, 100, 100),
      progress: 0.75,
    );

    expect(early.handVisible, isTrue);
    expect(late.handVisible, isTrue);
    expect(early.penIsDrawing, isFalse);
    expect(late.penIsDrawing, isFalse);
    expect(early.handPosition.dx, closeTo(70, 0.01));
    expect(late.handPosition.dx, closeTo(30, 0.01));
  });

  test('completion reveal does not repeat a direct hand stroke', () {
    final direct = DrawingStroke(
      id: 'direct',
      name: 'Direct text path',
      sectionId: 'title',
      points: const [Offset(0.1, 0.4), Offset(0.5, 0.4)],
    );
    final completion = DrawingStroke(
      id: 'completion',
      name: 'Complete remaining pixels',
      sectionId: 'title',
      revealOnly: true,
      points: const [Offset(0.1, 0.4), Offset(0.9, 0.4)],
    );
    final snapshot = buildTimelineSnapshot(
      strokes: [direct, completion],
      artworkRect: const Rect.fromLTWH(0, 0, 100, 100),
      progress: .9,
    );
    expect(snapshot.cursor?.strokeId, 'completion');
    expect(snapshot.handVisible, isFalse);
    expect(snapshot.penIsDrawing, isFalse);
  });

  test('lifts the hand for both long and short gaps between strokes', () {
    DrawingStroke stroke(String id, double start, double end) => DrawingStroke(
      id: id,
      name: id,
      points: [Offset(start, 0.5), Offset(end, 0.5)],
    );

    final longJump = buildTimelineSnapshot(
      strokes: [stroke('first', 0.1, 0.2), stroke('far', 0.8, 0.9)],
      artworkRect: const Rect.fromLTWH(0, 0, 100, 100),
      progress: 0.5,
    );
    final shortGap = buildTimelineSnapshot(
      strokes: [stroke('first', 0.1, 0.2), stroke('near', 0.23, 0.33)],
      artworkRect: const Rect.fromLTWH(0, 0, 100, 100),
      progress: 0.5,
    );

    expect(longJump.handVisible, isFalse);
    expect(shortGap.handVisible, isFalse);
  });

  test('pause after keeps the hand fixed and does not write', () {
    final strokes = [
      DrawingStroke(
        id: 'a',
        name: 'PACKAGE A',
        sectionId: 'package-a',
        points: const [Offset(0.1, 0.3), Offset(0.4, 0.3)],
      ),
      DrawingStroke(
        id: 'a-composite-reveal',
        name: 'PACKAGE A composite reveal',
        sectionId: 'package-a',
        revealOnly: true,
        points: const [Offset(0.1, 0.35), Offset(0.45, 0.35)],
      ),
      DrawingStroke(
        id: 'b',
        name: 'PACKAGE B',
        sectionId: 'package-b',
        points: const [Offset(0.6, 0.6), Offset(0.9, 0.6)],
      ),
    ];
    const artwork = Rect.fromLTWH(0, 0, 1000, 1000);
    const timings = {
      'section:package-a': SectionTiming(pauseAfterSeconds: 1.5),
    };
    final total = timelineDurationSeconds(
      strokes: strokes,
      timingRect: artwork,
      durationSeconds: 4,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      sectionTimings: timings,
    );
    expect(total, closeTo(5.5, 0.0001));

    final paused = <TimelineSnapshot>[];
    for (var step = 0; step <= 550; step++) {
      final snapshot = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: artwork,
        progress: step / 550,
        durationSeconds: 4,
        sectionTimings: timings,
      );
      if (snapshot.phase == TimelinePhase.pauseAfter) paused.add(snapshot);
    }

    expect(paused.length, greaterThan(100));
    expect(paused.first.handVisible, isTrue);
    expect(paused.first.penIsDrawing, isFalse);
    expect(paused.first.handPosition.dx, closeTo(400, 0.001));
    expect(paused.first.handPosition.dy, closeTo(300, 0.001));
    expect(paused.first.revealedPaths, hasLength(2));
    expect(
      paused.last.handPosition.dx,
      closeTo(paused.first.handPosition.dx, 0.001),
    );
    expect(
      paused.last.handPosition.dy,
      closeTo(paused.first.handPosition.dy, 0.001),
    );
    expect(
      _revealedLength(paused.last),
      closeTo(_revealedLength(paused.first), 0.001),
    );
  });

  test('advanced speed changes output time without changing old defaults', () {
    final stroke = DrawingStroke(
      id: 'line',
      name: 'Line',
      points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
    );
    const rect = Rect.fromLTWH(0, 0, 1920, 1080);
    final normal = timelineDurationSeconds(
      strokes: [stroke],
      timingRect: rect,
      durationSeconds: 6,
      startDelaySeconds: 0.4,
      endHoldSeconds: 0.9,
    );
    final faster = timelineDurationSeconds(
      strokes: [stroke],
      timingRect: rect,
      durationSeconds: 6,
      startDelaySeconds: 0.4,
      endHoldSeconds: 0.9,
      sectionTimings: const {'stroke:line': SectionTiming(speedMultiplier: 2)},
    );

    expect(normal, closeTo(6, 0.0001));
    expect(faster, closeTo(3.65, 0.0001));
  });

  test('global drawing speed changes motion only and preserves both holds', () {
    final stroke = DrawingStroke(
      id: 'line',
      name: 'Line',
      points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
    );
    const rect = Rect.fromLTWH(0, 0, 1920, 1080);

    final slower = timelineDurationSeconds(
      strokes: [stroke],
      timingRect: rect,
      durationSeconds: 6,
      drawingDurationSeconds: 4.7,
      drawingSpeed: 0.5,
      startDelaySeconds: 0.4,
      endHoldSeconds: 0.9,
    );
    final faster = timelineDurationSeconds(
      strokes: [stroke],
      timingRect: rect,
      durationSeconds: 6,
      drawingDurationSeconds: 4.7,
      drawingSpeed: 2,
      startDelaySeconds: 0.4,
      endHoldSeconds: 0.9,
    );

    expect(slower, closeTo(10.7, 0.0001));
    expect(faster, closeTo(3.65, 0.0001));
  });

  test('slower drawing uses the whole extended motion time continuously', () {
    final stroke = DrawingStroke(
      id: 'line',
      name: 'Line',
      points: const [Offset(0, 0.5), Offset(1, 0.5)],
    );

    TimelineSnapshot at(double progress) => buildTimelineSnapshot(
      strokes: [stroke],
      artworkRect: const Rect.fromLTWH(0, 0, 1000, 1000),
      progress: progress,
      durationSeconds: 4,
      drawingDurationSeconds: 4,
      drawingSpeed: 0.5,
    );

    expect(at(0.25).phase, TimelinePhase.drawing);
    expect(at(0.25).handPosition.dx, closeTo(250, 0.01));
    expect(at(0.5).phase, TimelinePhase.drawing);
    expect(at(0.5).handPosition.dx, closeTo(500, 0.01));
    expect(at(0.75).phase, TimelinePhase.drawing);
    expect(at(0.75).handPosition.dx, closeTo(750, 0.01));
  });

  test('drawing speed and pen travel speed affect independent phases', () {
    final project = HandDrawProject(
      strokes: [
        DrawingStroke(
          id: 'a',
          name: 'A',
          points: const [Offset(0.1, 0.25), Offset(0.4, 0.25)],
        ),
        DrawingStroke(
          id: 'b',
          name: 'B',
          points: const [Offset(0.6, 0.75), Offset(0.9, 0.75)],
        ),
      ],
    );
    final normal = resolveProjectTimeline(project).breakdown;
    final fastDrawing = resolveProjectTimeline(
      project.copyWith(drawingSpeed: 2),
    ).breakdown;
    final fastTravel = resolveProjectTimeline(
      project.copyWith(penTravelSpeed: 2),
    ).breakdown;

    expect(
      fastDrawing.drawingSeconds,
      closeTo(normal.drawingSeconds / 2, 1e-6),
    );
    expect(
      fastDrawing.penTravelSeconds,
      closeTo(normal.penTravelSeconds, 1e-6),
    );
    expect(fastTravel.drawingSeconds, closeTo(normal.drawingSeconds, 1e-6));
    expect(
      fastTravel.penTravelSeconds,
      closeTo(normal.penTravelSeconds / 2, 1e-6),
    );
  });

  test('fit to duration changes drawing only and reaches the exact target', () {
    final project = HandDrawProject(
      startDelaySeconds: 0.75,
      endHoldSeconds: 1.25,
      strokes: [
        DrawingStroke(
          id: 'a',
          name: 'A',
          points: const [Offset(0.1, 0.25), Offset(0.4, 0.25)],
        ),
        DrawingStroke(
          id: 'b',
          name: 'B',
          points: const [Offset(0.6, 0.75), Offset(0.9, 0.75)],
        ),
      ],
      sectionTimings: const {'stroke:a': SectionTiming(pauseAfterSeconds: 0.6)},
    );
    final baseline = resolveProjectTimeline(project);
    final target =
        baseline.durationSeconds - baseline.breakdown.drawingSeconds / 2;
    final result = fitProjectToDuration(project, target);

    expect(result.isSuccess, isTrue);
    expect(result.drawingSpeed, closeTo(2, 1e-6));
    final fitted = resolveProjectTimeline(
      project.copyWith(drawingSpeed: result.drawingSpeed),
    );
    expect(fitted.durationSeconds, closeTo(target, 1e-6));
    expect(
      fitted.breakdown.penTravelSeconds,
      closeTo(baseline.breakdown.penTravelSeconds, 1e-6),
    );
    expect(fitted.breakdown.sectionPauseSeconds, 0.6);
    expect(fitted.breakdown.startDelaySeconds, 0.75);
    expect(fitted.breakdown.endHoldSeconds, 1.25);
  });

  test('fit to duration rejects targets below fixed timing', () {
    final project = HandDrawProject(
      startDelaySeconds: 3,
      endHoldSeconds: 2,
      strokes: [
        DrawingStroke(
          id: 'line',
          name: 'Line',
          points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
        ),
      ],
    );

    final result = fitProjectToDuration(project, 4.5);
    expect(result.isSuccess, isFalse);
    expect(result.minimumDurationSeconds, greaterThan(5));
  });

  test('voice cues preserve absolute section starts after earlier edits', () {
    final strokes = [
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
    ];
    final keys = buildTimelineSections(strokes);
    final project = HandDrawProject(
      strokes: strokes,
      sectionTimings: {keys[1].key: const SectionTiming(voiceCueSeconds: 5)},
    );
    final original = resolveProjectTimeline(project).voiceCues[keys[1].key]!;
    expect(original.hasConflict, isFalse);
    expect(
      original.earliestStartSeconds + original.resolvedPauseBeforeSeconds,
      closeTo(5, 0.0001),
    );

    final changed = project.copyWith(
      sectionTimings: {
        keys[0].key: const SectionTiming(pauseAfterSeconds: 0.5),
        keys[1].key: const SectionTiming(voiceCueSeconds: 5),
      },
    );
    final recalculated = resolveProjectTimeline(
      changed,
    ).voiceCues[keys[1].key]!;
    expect(recalculated.hasConflict, isFalse);
    expect(
      recalculated.earliestStartSeconds +
          recalculated.resolvedPauseBeforeSeconds,
      closeTo(5, 0.0001),
    );
    expect(
      recalculated.resolvedPauseBeforeSeconds,
      lessThan(original.resolvedPauseBeforeSeconds),
    );
  });

  test('voice cue reports a conflict instead of changing drawing speed', () {
    final strokes = [
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
    ];
    final secondKey = buildTimelineSections(strokes)[1].key;
    final resolution = resolveProjectTimeline(
      HandDrawProject(
        strokes: strokes,
        sectionTimings: {secondKey: const SectionTiming(voiceCueSeconds: 0.2)},
      ),
    ).voiceCues[secondKey]!;

    expect(resolution.hasConflict, isTrue);
    expect(resolution.resolvedPauseBeforeSeconds, 0);
    expect(resolution.lateBySeconds, greaterThan(0));
  });

  test('a longer Voice Guide never stretches or leaves drawing incomplete', () {
    final project = HandDrawProject(
      durationSeconds: 6,
      strokes: [
        DrawingStroke(
          id: 'line',
          name: 'Line',
          points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
        ),
      ],
    );

    expect(projectTimelineProgressAt(project, 3), closeTo(0.5, 0.0001));
    expect(projectTimelineProgressAt(project, 6), 1);
    expect(
      projectTimelineProgressAt(project, 11.13),
      1,
      reason: 'Voice-only tail must hold the completed drawing.',
    );

    final snapshot = buildTimelineSnapshot(
      strokes: project.strokes,
      artworkRect: const Rect.fromLTWH(0, 0, 1920, 1080),
      progress: projectTimelineProgressAt(project, 11.13),
      durationSeconds: project.durationSeconds,
      startDelaySeconds: project.startDelaySeconds,
      endHoldSeconds: project.endHoldSeconds,
      sectionTimings: project.sectionTimings,
    );
    expect(snapshot.drawingComplete, isTrue);
  });

  test(
    'an in-stroke pause freezes reveal and hand while silencing the pen',
    () {
      final stroke = DrawingStroke(
        id: 'line',
        name: 'Line',
        points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
        pausePoints: const [
          StrokePausePoint(id: 'middle', progress: 0.5, durationSeconds: 1),
        ],
      );
      final project = HandDrawProject(
        durationSeconds: 4,
        drawingDurationSeconds: 4,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        strokes: [stroke],
      );
      expect(projectTimelineDuration(project), closeTo(5, 0.0001));

      TimelineSnapshot atSeconds(double seconds) => buildTimelineSnapshot(
        strokes: project.strokes,
        artworkRect: const Rect.fromLTWH(0, 0, 1000, 500),
        progress: seconds / 5,
        durationSeconds: project.durationSeconds,
        drawingDurationSeconds: project.drawingDurationSeconds,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
      );

      final first = atSeconds(2.1);
      final second = atSeconds(2.9);
      expect(first.phase, TimelinePhase.strokePause);
      expect(second.phase, TimelinePhase.strokePause);
      expect(first.penIsDrawing, isFalse);
      expect(first.handVisible, isTrue);
      expect(second.handPosition, first.handPosition);
      expect(_revealedLength(second), closeTo(_revealedLength(first), 0.001));
      expect(atSeconds(3.1).phase, TimelinePhase.drawing);
    },
  );

  test('drawing speed changes drawing time but never scales pause points', () {
    final stroke = DrawingStroke(
      id: 'line',
      name: 'Line',
      points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
      pausePoints: const [
        StrokePausePoint(id: 'hold', progress: 0.4, durationSeconds: 1.25),
      ],
    );
    final normal = resolveProjectTimeline(
      HandDrawProject(
        strokes: [stroke],
        startDelaySeconds: 0,
        endHoldSeconds: 0,
      ),
    );
    final fast = resolveProjectTimeline(
      HandDrawProject(
        strokes: [stroke],
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        drawingSpeed: 2,
      ),
    );
    final fastest = resolveProjectTimeline(
      HandDrawProject(
        strokes: [stroke],
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        drawingSpeed: maximumProjectDrawingSpeed,
      ),
    );
    final verySlow = resolveProjectTimeline(
      HandDrawProject(
        strokes: [stroke],
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        drawingSpeed: minimumProjectDrawingSpeed,
      ),
    );
    expect(normal.breakdown.sectionPauseSeconds, closeTo(1.25, 0.0001));
    expect(fast.breakdown.sectionPauseSeconds, closeTo(1.25, 0.0001));
    expect(
      fast.breakdown.drawingSeconds,
      closeTo(normal.breakdown.drawingSeconds / 2, 0.0001),
    );
    expect(fastest.breakdown.sectionPauseSeconds, closeTo(1.25, 0.0001));
    expect(
      fastest.breakdown.drawingSeconds,
      closeTo(
        normal.breakdown.drawingSeconds / maximumProjectDrawingSpeed,
        0.0001,
      ),
    );
    expect(
      verySlow.breakdown.drawingSeconds,
      closeTo(normal.breakdown.drawingSeconds * 10, 0.0001),
    );
  });

  test('section spans use the same absolute schedule as project preview', () {
    final project = HandDrawProject(
      durationSeconds: 8,
      startDelaySeconds: 1,
      endHoldSeconds: 1.5,
      strokes: [
        DrawingStroke(
          id: 'a',
          name: 'A',
          sectionId: 'first',
          points: const [Offset(0.1, 0.2), Offset(0.4, 0.2)],
        ),
        DrawingStroke(
          id: 'b',
          name: 'B',
          sectionId: 'second',
          points: const [Offset(0.6, 0.7), Offset(0.9, 0.7)],
        ),
      ],
    );

    final spans = projectTimelineSectionSpans(project);

    expect(spans.map((span) => span.sectionId), ['first', 'second']);
    expect(spans.first.startSeconds, 0);
    expect(spans.first.endSeconds, spans.last.startSeconds);
    expect(
      spans.last.endSeconds,
      closeTo(projectTimelineDuration(project), 0.0001),
    );
  });

  test('section animate pause and transition durations resolve exactly', () {
    final project = HandDrawProject(
      durationSeconds: 8,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'a',
          name: 'A',
          sectionId: 'first',
          points: const [Offset(0.1, 0.2), Offset(0.4, 0.2)],
        ),
        DrawingStroke(
          id: 'b',
          name: 'B',
          sectionId: 'second',
          points: const [Offset(0.6, 0.7), Offset(0.9, 0.7)],
        ),
      ],
      sectionTimings: const {
        'section:first': SectionTiming(
          animationDurationSeconds: 2,
          pauseAfterSeconds: 0.5,
          transitionAfterSeconds: 0.75,
        ),
      },
    );

    final metrics = projectTimelineSectionMetrics(project);
    final spans = projectTimelineSectionSpans(project);

    expect(metrics['first']!.animationSeconds, closeTo(2, 0.0001));
    expect(metrics['first']!.pauseAfterSeconds, closeTo(0.5, 0.0001));
    expect(metrics['first']!.transitionAfterSeconds, closeTo(0.75, 0.0001));
    expect(metrics['first']!.totalSeconds, closeTo(3.25, 0.0001));
    expect(spans.first.durationSeconds, closeTo(3.25, 0.0001));
    expect(spans.first.endSeconds, closeTo(spans.last.startSeconds, 0.0001));
  });

  test('saved section duration follows overall and section drawing speed', () {
    final project = HandDrawProject(
      durationSeconds: 1.12,
      drawingDurationSeconds: 1.12,
      drawingSpeed: 5.35,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'reference-speed',
          name: 'Reference speed',
          sectionId: 'reference-speed',
          points: const [Offset(0.1, 0.5), Offset(0.7, 0.5)],
        ),
      ],
      sectionTimings: const {
        'section:reference-speed': SectionTiming(
          animationDurationSeconds: 1.12,
        ),
      },
    );

    expect(
      resolveProjectTimeline(project).breakdown.drawingSeconds,
      closeTo(1.12 / 5.35, 0.000001),
    );
    expect(
      resolveProjectTimeline(
        project.copyWith(
          sectionTimings: const {
            'section:reference-speed': SectionTiming(
              animationDurationSeconds: 1.12,
              speedMultiplier: 2,
            ),
          },
        ),
      ).breakdown.drawingSeconds,
      closeTo(1.12 / 5.35 / 2, 0.000001),
    );
  });

  test('isolated stroke preview inherits its saved section drawing speed', () {
    final project = HandDrawProject(
      durationSeconds: 4,
      drawingDurationSeconds: 4,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'slow-line',
          name: 'Slow line',
          sectionId: 'slow-section',
          points: [Offset(0.1, 0.5), Offset(0.9, 0.5)],
        ),
      ],
    );
    final normalDuration = projectTimelineStrokeDrawingDuration(project, 0);
    final slowProject = project.copyWith(
      sectionTimings: const {
        'section:slow-section': SectionTiming(speedMultiplier: 0.25),
      },
    );

    expect(normalDuration, closeTo(4, 0.0001));
    expect(
      projectTimelineStrokeDrawingDuration(slowProject, 0),
      closeTo(normalDuration * 4, 0.0001),
    );
  });

  test('section hand entrance and exit share the exact project schedule', () {
    final stroke = DrawingStroke(
      id: 'animated-hand',
      name: 'Animated hand',
      sectionId: 'scene',
      points: const [Offset(0.2, 0.5), Offset(0.8, 0.5)],
    );
    final project = HandDrawProject(
      durationSeconds: 3,
      drawingDurationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [stroke],
      sectionTimings: const {
        'section:scene': SectionTiming(
          pauseBeforeSeconds: .5,
          animationDurationSeconds: 1,
          pauseAfterSeconds: .5,
          handEntranceAnimation: SectionHandEntranceAnimation.fadeIn,
          handEntranceDurationSeconds: .5,
          handExitAnimation: SectionHandExitAnimation.moveOut,
          handExitDurationSeconds: .5,
        ),
      },
    );
    const rect = Rect.fromLTWH(0, 0, 1000, 600);

    TimelineSnapshot at(double seconds) => buildTimelineSnapshot(
      strokes: project.strokes,
      artworkRect: rect,
      timingRect: rect,
      progress: seconds / projectTimelineDuration(project),
      durationSeconds: projectTimelineDuration(project),
      drawingDurationSeconds: project.drawingDurationSeconds,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      sectionTimings: project.sectionTimings,
    );

    final metrics = projectTimelineSectionMetrics(project).values.single;
    expect(metrics.pauseBeforeSeconds, closeTo(.5, .0001));
    expect(metrics.handEntranceSeconds, closeTo(.5, .0001));
    expect(metrics.animationSeconds, closeTo(1, .0001));
    expect(metrics.pauseAfterSeconds, closeTo(.5, .0001));
    expect(metrics.handExitSeconds, closeTo(.5, .0001));
    expect(metrics.totalSeconds, closeTo(3, .0001));
    expect(projectTimelineDuration(project), closeTo(3, .0001));

    final entering = at(.75);
    expect(entering.phase, TimelinePhase.handEntrance);
    expect(entering.handVisible, isTrue);
    expect(entering.handOpacity, closeTo(.5, .02));

    final exiting = at(2.75);
    expect(exiting.phase, TimelinePhase.handExit);
    expect(exiting.handVisible, isTrue);
    expect(exiting.handPosition.dx, greaterThan(800));
  });

  test('hidden paths are excluded from preview geometry and duration', () {
    final visible = DrawingStroke(
      id: 'visible',
      name: 'Visible',
      points: const [Offset(0.1, 0.3), Offset(0.9, 0.3)],
    );
    final hidden = DrawingStroke(
      id: 'hidden',
      name: 'Hidden',
      hidden: true,
      points: const [Offset(0.1, 0.7), Offset(0.9, 0.7)],
    );
    final visibleDuration = timelineDurationSeconds(
      strokes: [visible],
      timingRect: const Rect.fromLTWH(0, 0, 100, 100),
      durationSeconds: 4,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
    );
    final withHiddenDuration = timelineDurationSeconds(
      strokes: [visible, hidden],
      timingRect: const Rect.fromLTWH(0, 0, 100, 100),
      durationSeconds: 4,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
    );
    final snapshot = buildTimelineSnapshot(
      strokes: [visible, hidden],
      artworkRect: const Rect.fromLTWH(0, 0, 100, 100),
      progress: 1,
      durationSeconds: 4,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
    );

    expect(withHiddenDuration, visibleDuration);
    expect(snapshot.revealedPaths, hasLength(1));
  });

  test('reveal-only section honors its authored hand exit animation', () {
    final project = HandDrawProject(
      durationSeconds: 1.42,
      drawingDurationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'reference-reveal',
          name: 'Reference reveal',
          sectionId: 'reference',
          points: const [Offset(.1, .5), Offset(.7, .5)],
          revealOnly: true,
          revealStyle: RevealMaskStyle.directionalWipe,
        ),
      ],
      sectionTimings: const {
        'section:reference': SectionTiming(
          animationDurationSeconds: 1,
          handExitAnimation: SectionHandExitAnimation.moveOut,
          handExitDurationSeconds: .42,
        ),
      },
    );
    const artwork = Rect.fromLTWH(0, 0, 1000, 600);

    TimelineSnapshot at(double seconds) => buildTimelineSnapshot(
      strokes: project.strokes,
      artworkRect: artwork,
      timingRect: artwork,
      progress: seconds / projectTimelineDuration(project),
      durationSeconds: projectTimelineDuration(project),
      drawingDurationSeconds: project.drawingDurationSeconds,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      sectionTimings: project.sectionTimings,
    );

    expect(projectTimelineDuration(project), closeTo(1.42, .0001));
    expect(at(.99).phase, TimelinePhase.drawing);
    final exiting = at(1.21);
    expect(exiting.phase, TimelinePhase.handExit);
    expect(exiting.handVisible, isTrue);
    expect(exiting.handPosition.dx, greaterThan(700));
  });

  test('final section can keep the hand at the pen after drawing', () {
    const artwork = Rect.fromLTWH(0, 0, 1000, 600);
    final stroke = DrawingStroke(
      id: 'held-hand',
      name: 'Held hand',
      sectionId: 'final',
      points: const [Offset(.1, .5), Offset(.7, .5)],
    );
    final project = HandDrawProject(
      durationSeconds: 1.7,
      drawingDurationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: .5,
      strokes: [stroke],
      sectionTimings: const {
        'section:final': SectionTiming(
          animationDurationSeconds: 1,
          pauseAfterSeconds: .2,
          pauseHandBehavior: PauseHandBehavior.hide,
          handExitAnimation: SectionHandExitAnimation.moveOut,
          handExitDurationSeconds: .4,
          keepHandVisibleAfterDrawing: true,
        ),
      },
    );

    TimelineSnapshot snapshot(HandDrawProject value) => buildTimelineSnapshot(
      strokes: value.strokes,
      artworkRect: artwork,
      timingRect: artwork,
      progress: 1,
      durationSeconds: projectTimelineDuration(value),
      drawingDurationSeconds: value.drawingDurationSeconds,
      startDelaySeconds: value.startDelaySeconds,
      endHoldSeconds: value.endHoldSeconds,
      sectionTimings: value.sectionTimings,
    );

    TimelineSnapshot at(double seconds) => buildTimelineSnapshot(
      strokes: project.strokes,
      artworkRect: artwork,
      timingRect: artwork,
      progress: seconds / projectTimelineDuration(project),
      durationSeconds: projectTimelineDuration(project),
      drawingDurationSeconds: project.drawingDurationSeconds,
      startDelaySeconds: project.startDelaySeconds,
      endHoldSeconds: project.endHoldSeconds,
      sectionTimings: project.sectionTimings,
    );

    final resolved = resolveProjectTimeline(project);
    expect(resolved.breakdown.handAnimationSeconds, 0);
    expect(resolved.durationSeconds, closeTo(1.7, .0001));
    expect(at(1.1).phase, TimelinePhase.pauseAfter);
    expect(at(1.1).handVisible, isTrue);
    final held = snapshot(project);
    expect(held.phase, TimelinePhase.endHold);
    expect(held.drawingComplete, isTrue);
    expect(held.handVisible, isTrue);
    expect(held.handOpacity, 1);
    expect(held.handPosition, const Offset(700, 300));

    final defaultBehavior = HandDrawProject(
      durationSeconds: 1.5,
      drawingDurationSeconds: 1,
      startDelaySeconds: 0,
      endHoldSeconds: .5,
      strokes: [stroke],
      sectionTimings: const {
        'section:final': SectionTiming(animationDurationSeconds: 1),
      },
    );
    expect(snapshot(defaultBehavior).handVisible, isFalse);
  });

  test('geometry cache retains both working rectangles above 512 paths', () {
    final strokes = List.generate(
      600,
      (index) => DrawingStroke(
        id: 'dense-$index',
        name: 'Dense $index',
        points: [
          Offset(0.05, (index + 1) / 602),
          Offset(0.95, (index + 1) / 602),
        ],
      ),
      growable: false,
    );
    const previewRect = Rect.fromLTWH(10, 20, 960, 540);
    const timingRect = Rect.fromLTWH(0, 0, 1920, 1080);

    final firstPreview = buildStrokeGeometry(strokes, previewRect);
    final firstTiming = buildStrokeGeometry(strokes, timingRect);
    final secondPreview = buildStrokeGeometry(strokes, previewRect);
    final secondTiming = buildStrokeGeometry(strokes, timingRect);

    expect(firstPreview, hasLength(600));
    expect(firstTiming, hasLength(600));
    for (var index = 0; index < strokes.length; index++) {
      expect(
        identical(firstPreview[index].path, secondPreview[index].path),
        isTrue,
      );
      expect(
        identical(firstTiming[index].path, secondTiming[index].path),
        isTrue,
      );
    }
  });

  test('completed strokes reuse compiled paths without changing geometry', () {
    final strokes = List.generate(
      4,
      (index) => DrawingStroke(
        id: 'cached-$index',
        name: 'Cached $index',
        points: [
          Offset(0.05 + index * 0.2, 0.5),
          Offset(0.20 + index * 0.2, 0.5),
        ],
      ),
      growable: false,
    );
    const rect = Rect.fromLTWH(0, 0, 1000, 600);
    final geometries = buildStrokeGeometry(strokes, rect);
    final snapshot = buildTimelineSnapshot(
      strokes: strokes,
      artworkRect: rect,
      timingRect: rect,
      progress: 0.8,
      durationSeconds: 4,
      drawingDurationSeconds: 4,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
    );

    expect(snapshot.revealedPaths.length, greaterThanOrEqualTo(2));
    expect(
      identical(snapshot.revealedPaths.first.path, geometries.first.path),
      isTrue,
    );
    expect(
      snapshot.revealedPaths.first.path.computeMetrics().single.length,
      closeTo(geometries.first.length, 0.0001),
    );
  });
}

double _revealedLength(TimelineSnapshot snapshot) => snapshot.revealedPaths
    .expand((path) => path.path.computeMetrics())
    .fold(0, (total, metric) => total + metric.length);
