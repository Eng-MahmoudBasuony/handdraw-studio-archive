import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class OfflineAudioMixClip {
  const OfflineAudioMixClip({
    required this.trackId,
    required this.assetId,
    required this.timelineInterval,
    required this.sourceOffset,
  });
  final AudioTrackId trackId;
  final ProjectAssetId assetId;
  final TimelineInterval timelineInterval;
  final TimelineTime sourceOffset;
}

/// Deterministic offline selection contract. Voice Guide is structurally
/// separate in CompiledTimeline and can never enter this plan.
final class OfflineAudioMixPlan {
  OfflineAudioMixPlan._(List<OfflineAudioMixClip> clips)
    : clips = List.unmodifiable(clips);

  factory OfflineAudioMixPlan.fromTimeline(CompiledTimeline timeline) =>
      OfflineAudioMixPlan._([
        for (final track in timeline.audio)
          if (!track.referenceOnly && !track.muted)
            OfflineAudioMixClip(
              trackId: track.audioTrackId,
              assetId: track.assetId,
              timelineInterval: track.interval,
              sourceOffset: track.sourceOffset,
            ),
      ]);

  final List<OfflineAudioMixClip> clips;
}
