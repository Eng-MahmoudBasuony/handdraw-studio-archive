import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/frame_sampling_policy.dart';
import 'package:handdraw_studio/features/timeline/domain/services/global_timeline_resolver.dart';

final class UnifiedProjectFrameResolver {
  const UnifiedProjectFrameResolver();

  ResolvedProjectFrame resolveForPreview(
    CompiledTimeline timeline,
    TimelineTime time,
  ) => const GlobalTimelineResolver().resolveAt(timeline, time);

  ResolvedProjectFrame resolveForExportFrame({
    required CompiledTimeline timeline,
    required int frameIndex,
    required FrameRate frameRate,
  }) {
    const sampling = FrameSamplingPolicy();
    final frameCount = sampling.frameCount(
      duration: timeline.duration,
      frameRate: frameRate,
    );
    final time = frameCount > 0 && frameIndex == frameCount - 1
        ? TimelineTime.fromMicroseconds(timeline.duration.microseconds)
        : sampling.timeForFrame(
            index: frameIndex,
            duration: timeline.duration,
            frameRate: frameRate,
          );
    return const GlobalTimelineResolver().resolveAt(timeline, time);
  }
}
