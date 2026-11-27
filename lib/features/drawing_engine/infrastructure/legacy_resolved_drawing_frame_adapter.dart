import 'dart:ui';

import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';

/// The sole 4C compatibility boundary from integer timeline time to the
/// production reveal/geometry scheduler. It owns no timing state.
final class LegacyResolvedDrawingFrameAdapter {
  const LegacyResolvedDrawingFrameAdapter();

  TimelineSnapshot resolveOrStaticArtwork({
    required HandDrawProject project,
    required ResolvedDrawingFrame? frame,
    required Rect artworkRect,
    Rect? timingRect,
  }) {
    if (frame != null) {
      return resolve(
        project: project,
        frame: frame,
        artworkRect: artworkRect,
        timingRect: timingRect,
      );
    }
    if (project.strokes.isEmpty) {
      return const TimelineSnapshot(
        revealedPaths: [],
        handPosition: Offset.zero,
        handAngle: 0,
        handVisible: false,
        drawingComplete: true,
        phase: TimelinePhase.endHold,
      );
    }
    return const TimelineSnapshot(
      revealedPaths: [],
      handPosition: Offset.zero,
      handAngle: 0,
      handVisible: false,
      phase: TimelinePhase.startDelay,
    );
  }

  TimelineSnapshot resolve({
    required HandDrawProject project,
    required ResolvedDrawingFrame frame,
    required Rect artworkRect,
    Rect? timingRect,
  }) {
    final durationUs = frame.duration.microseconds;
    final progress = durationUs == 0
        ? 1.0
        : frame.localTime.microseconds / durationUs;
    return buildTimelineSnapshot(
      strokes: project.strokes,
      artworkRect: artworkRect,
      progress: progress,
      durationSeconds: project.durationSeconds,
      drawingDurationSeconds: project.drawingDurationSeconds,
      drawingSpeed: project.drawingSpeed,
      penTravelSpeed: project.penTravelSpeed,
      startDelaySeconds: project.startDelaySeconds,
      endHoldSeconds: project.endHoldSeconds,
      sectionTimings: project.sectionTimings,
      timingRect: timingRect,
    );
  }
}
