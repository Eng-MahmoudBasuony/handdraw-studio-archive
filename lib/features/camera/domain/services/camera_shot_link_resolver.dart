import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class CameraTimelineContentSpan {
  const CameraTimelineContentSpan({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
  });

  final String id;
  final String name;
  final TimelineTime start;
  final TimelineTime end;
}

final class CameraShotLink {
  CameraShotLink({
    required List<CameraTimelineContentSpan> spans,
    required this.reachesTimelineEnd,
  }) : spans = List.unmodifiable(spans);

  final List<CameraTimelineContentSpan> spans;
  final bool reachesTimelineEnd;

  bool get isEmpty => spans.isEmpty;
  bool get isSingle => spans.length == 1;
  List<String> get sectionIds => [for (final span in spans) span.id];

  String displayName({required bool isArabic}) {
    if (isEmpty) return isArabic ? 'غير مرتبط بمشهد' : 'Not linked to a scene';
    if (isSingle) return spans.single.name;
    final first = spans.first.name;
    if (reachesTimelineEnd) {
      return isArabic ? '$first — إلى آخر مشهد' : '$first — to last scene';
    }
    return '$first — ${spans.last.name}';
  }
}

/// Resolves a camera shot's content link from the same section intervals shown
/// by the editor timeline. This keeps a free camera clip meaningfully linked
/// even when it does not carry a persistent scene owner ID.
final class CameraShotLinkResolver {
  const CameraShotLinkResolver();

  CameraShotLink resolve({
    required CameraShot shot,
    required List<CameraTimelineContentSpan> timelineSpans,
    List<String>? ownedSectionIds,
  }) {
    final ordered = [...timelineSpans]
      ..sort((a, b) => a.start.compareTo(b.start));
    final owned = ownedSectionIds?.toSet();
    final linked = [
      for (final span in ordered)
        if (owned != null && owned.isNotEmpty
            ? owned.contains(span.id)
            : _overlaps(shot, span))
          span,
    ];
    final timelineEnd = ordered.isEmpty ? null : ordered.last.end;
    return CameraShotLink(
      spans: linked,
      reachesTimelineEnd:
          linked.length > 1 &&
          timelineEnd != null &&
          shot.startTime.compareTo(linked.first.start) <= 0 &&
          shot.endTime.compareTo(timelineEnd) >= 0,
    );
  }

  bool _overlaps(CameraShot shot, CameraTimelineContentSpan span) =>
      shot.startTime.compareTo(span.end) < 0 &&
      shot.endTime.compareTo(span.start) > 0;
}
