import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_rect_list.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_pause_point.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/natural_hand_motion.dart';

const minimumProjectDrawingSpeed = 0.1;
const maximumProjectDrawingSpeed = 8.0;

class StrokeGeometry {
  StrokeGeometry({
    required this.strokeId,
    required this.sectionId,
    required this.path,
    required this.timingLength,
    required this.timingStart,
    required this.timingEnd,
    required this.sectionIndex,
    required this.revealOnly,
    required this.revealStyle,
    required this.rightToLeft,
    required this.revealWidth,
    required this.clipRect,
    required this.clipPath,
    required this.exclusionRects,
    required this.pausePoints,
    required this.vectorMaskStrokes,
    required this.fillColorValue,
    required this.isTextShape,
    required this.isFilledShape,
    required this.isGlobalDecoration,
  });

  final String strokeId;
  final String? sectionId;
  final Path path;
  final double timingLength;
  final Offset timingStart;
  final Offset timingEnd;
  final int sectionIndex;
  final bool revealOnly;
  final RevealMaskStyle revealStyle;
  final bool rightToLeft;
  final double? revealWidth;
  final Rect? clipRect;
  final Path? clipPath;
  final List<Rect> exclusionRects;
  final List<StrokePausePoint> pausePoints;
  final List<VectorMaskStroke> vectorMaskStrokes;
  final int? fillColorValue;
  final bool isTextShape;
  final bool isFilledShape;
  final bool isGlobalDecoration;

  PathMetric? _metric;

  PathMetric get metric => _metric ??= path.computeMetrics().first;

  double get length => metric.length;

  Tangent tangentAt(double distance) =>
      metric.getTangentForOffset(distance.clamp(0.0, metric.length)) ??
      const Tangent(Offset.zero, Offset(1, 0));
}

/// The single resolved cursor consumed by reveal, hand rendering and
/// diagnostics. It identifies the exact geometry that produced the pen point.
class ResolvedDrawingCursor {
  const ResolvedDrawingCursor({
    required this.sectionId,
    required this.strokeId,
    required this.pathId,
    required this.progress,
    required this.distance,
    required this.worldPenPoint,
    required this.activePathGeometry,
  });

  final String? sectionId;
  final String strokeId;
  final String pathId;
  final double progress;
  final double distance;
  final Offset worldPenPoint;
  final Path activePathGeometry;
}

class RevealedPath {
  const RevealedPath({
    required this.path,
    required this.sectionIndex,
    this.revealWidth,
    this.clipRect,
    this.clipPath,
    this.exclusionRects = const [],
    this.revealStyle = RevealMaskStyle.brush,
    this.activeBrushDirection,
    this.rightToLeft = false,
    this.vectorMaskStrokes = const [],
    this.strokeProgress = 1,
    this.fillColorValue,
    this.isTextShape = false,
    this.isFilledShape = false,
    this.isGlobalDecoration = false,
  });

  final Path path;
  final int sectionIndex;
  final double? revealWidth;
  final Rect? clipRect;
  final Path? clipPath;
  final List<Rect> exclusionRects;
  final RevealMaskStyle revealStyle;

  /// Fixed start-to-end direction used to keep an active broad brush behind
  /// the nib. Completed reveals leave this null and retain their normal caps.
  final Offset? activeBrushDirection;
  final bool rightToLeft;
  final List<VectorMaskStroke> vectorMaskStrokes;
  final double strokeProgress;
  final int? fillColorValue;
  final bool isTextShape;
  final bool isFilledShape;
  final bool isGlobalDecoration;
}

/// Immutable backing data for the completed part of a dense reveal timeline.
///
/// [TimelineSnapshot.revealedPaths] remains the compatibility surface for all
/// consumers. Renderers can use this metadata to compile stable brush chunks
/// once instead of regrouping thousands of completed paths on every frame.
class StableRevealSequence {
  const StableRevealSequence({
    required this.paths,
    required this.visibleCount,
    this.activePath,
  });

  final List<RevealedPath> paths;
  final int visibleCount;
  final RevealedPath? activePath;
}

class TimelineSnapshot {
  const TimelineSnapshot({
    required this.revealedPaths,
    required this.handPosition,
    required this.handAngle,
    required this.handVisible,
    this.handOpacity = 1,
    this.penLiftProgress,
    this.penTravelDistance,
    this.sectionClips = const [],
    this.drawingComplete = false,
    this.phase = TimelinePhase.drawing,
    this.penIsDrawing = false,
    this.cursor,
    this.stableRevealSequence,
  });

  final List<RevealedPath> revealedPaths;
  final Offset handPosition;
  final double handAngle;
  final bool handVisible;
  final double handOpacity;

  /// Local progress only during a pen-up transfer; null while touching ink.
  final double? penLiftProgress;

  /// Transfer distance in the same coordinates as handPosition.
  final double? penTravelDistance;
  final List<Rect> sectionClips;
  final bool drawingComplete;
  final TimelinePhase phase;
  final bool penIsDrawing;
  final ResolvedDrawingCursor? cursor;
  final StableRevealSequence? stableRevealSequence;
}

final class _StableRevealListView extends ListBase<RevealedPath> {
  _StableRevealListView(this._paths, int visibleCount, [this._activePath])
    : _visibleCount = visibleCount.clamp(0, _paths.length);

  final List<RevealedPath> _paths;
  final int _visibleCount;
  final RevealedPath? _activePath;

  @override
  int get length => _visibleCount + (_activePath == null ? 0 : 1);

  @override
  set length(int value) =>
      throw UnsupportedError('Reveal views are immutable.');

  @override
  RevealedPath operator [](int index) {
    RangeError.checkValidIndex(index, this);
    if (index < _visibleCount) return _paths[index];
    return _activePath!;
  }

  @override
  void operator []=(int index, RevealedPath value) =>
      throw UnsupportedError('Reveal views are immutable.');
}

enum TimelinePhase {
  startDelay,
  handEntrance,
  drawing,
  pauseBefore,
  pauseAfter,
  strokePause,
  travel,
  handExit,
  endHold,
}

class TimelineSectionDefinition {
  const TimelineSectionDefinition({
    required this.index,
    required this.key,
    required this.label,
    required this.strokeIndices,
  });

  final int index;
  final String key;
  final String label;
  final List<int> strokeIndices;
}

/// Absolute timing occupied by one drawable section on the shared project
/// timeline. The same schedule drives Preview and MOV export.
class ProjectTimelineSectionSpan {
  const ProjectTimelineSectionSpan({
    required this.sectionId,
    required this.startSeconds,
    required this.endSeconds,
  });

  final String sectionId;
  final double startSeconds;
  final double endSeconds;

  double get durationSeconds => math.max(0, endSeconds - startSeconds);
}

/// Editable timing components for one section, resolved from the exact motion
/// schedule shared by Preview, audio synthesis, and MOV export.
class ProjectTimelineSectionMetrics {
  const ProjectTimelineSectionMetrics({
    required this.sectionId,
    required this.pauseBeforeSeconds,
    required this.handEntranceSeconds,
    required this.animationSeconds,
    required this.pauseAfterSeconds,
    required this.handExitSeconds,
    required this.transitionAfterSeconds,
  });

  final String sectionId;
  final double pauseBeforeSeconds;
  final double handEntranceSeconds;
  final double animationSeconds;
  final double pauseAfterSeconds;
  final double handExitSeconds;
  final double transitionAfterSeconds;

  double get totalSeconds =>
      pauseBeforeSeconds +
      handEntranceSeconds +
      animationSeconds +
      pauseAfterSeconds +
      handExitSeconds +
      transitionAfterSeconds;
}

class SectionVoiceCueResolution {
  const SectionVoiceCueResolution({
    required this.sectionKey,
    required this.cueSeconds,
    required this.earliestStartSeconds,
    required this.resolvedPauseBeforeSeconds,
    required this.hasConflict,
  });

  final String sectionKey;
  final double cueSeconds;
  final double earliestStartSeconds;
  final double resolvedPauseBeforeSeconds;
  final bool hasConflict;

  double get lateBySeconds => math.max(0, earliestStartSeconds - cueSeconds);
}

class ProjectTimelineResolution {
  const ProjectTimelineResolution({
    required this.durationSeconds,
    required this.voiceCues,
    required this.breakdown,
  });

  final double durationSeconds;
  final Map<String, SectionVoiceCueResolution> voiceCues;
  final ProjectTimingBreakdown breakdown;
}

class ProjectTimingBreakdown {
  const ProjectTimingBreakdown({
    required this.startDelaySeconds,
    required this.drawingSeconds,
    required this.penTravelSeconds,
    required this.sectionPauseSeconds,
    required this.handAnimationSeconds,
    required this.endHoldSeconds,
  });

  final double startDelaySeconds;
  final double drawingSeconds;
  final double penTravelSeconds;
  final double sectionPauseSeconds;
  final double handAnimationSeconds;
  final double endHoldSeconds;

  double get totalSeconds =>
      startDelaySeconds +
      drawingSeconds +
      penTravelSeconds +
      sectionPauseSeconds +
      handAnimationSeconds +
      endHoldSeconds;
}

class FitToDurationResult {
  const FitToDurationResult._({
    required this.isSuccess,
    required this.targetDurationSeconds,
    required this.minimumDurationSeconds,
    required this.maximumDurationSeconds,
    this.drawingSpeed,
    this.resolvedDurationSeconds,
  });

  final bool isSuccess;
  final double targetDurationSeconds;
  final double minimumDurationSeconds;
  final double maximumDurationSeconds;
  final double? drawingSpeed;
  final double? resolvedDurationSeconds;

  static FitToDurationResult success({
    required double targetDurationSeconds,
    required double minimumDurationSeconds,
    required double maximumDurationSeconds,
    required double drawingSpeed,
    required double resolvedDurationSeconds,
  }) => FitToDurationResult._(
    isSuccess: true,
    targetDurationSeconds: targetDurationSeconds,
    minimumDurationSeconds: minimumDurationSeconds,
    maximumDurationSeconds: maximumDurationSeconds,
    drawingSpeed: drawingSpeed,
    resolvedDurationSeconds: resolvedDurationSeconds,
  );

  static FitToDurationResult impossible({
    required double targetDurationSeconds,
    required double minimumDurationSeconds,
    required double maximumDurationSeconds,
  }) => FitToDurationResult._(
    isSuccess: false,
    targetDurationSeconds: targetDurationSeconds,
    minimumDurationSeconds: minimumDurationSeconds,
    maximumDurationSeconds: maximumDurationSeconds,
  );
}

Path buildSmoothPath(List<Offset> normalizedPoints, Rect artworkRect) {
  final points = normalizedPoints
      .map(
        (point) => Offset(
          artworkRect.left + point.dx * artworkRect.width,
          artworkRect.top + point.dy * artworkRect.height,
        ),
      )
      .toList(growable: false);

  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length == 1) return path;
  if (points.length == 2) {
    path.lineTo(points.last.dx, points.last.dy);
    return path;
  }

  for (var index = 0; index < points.length - 1; index++) {
    final p0 = index == 0 ? points[index] : points[index - 1];
    final p1 = points[index];
    final p2 = points[index + 1];
    final p3 = index + 2 < points.length ? points[index + 2] : p2;
    final control1 = p1 + (p2 - p0) / 6;
    final control2 = p2 - (p3 - p1) / 6;
    path.cubicTo(
      control1.dx,
      control1.dy,
      control2.dx,
      control2.dy,
      p2.dx,
      p2.dy,
    );
  }
  return path;
}

/// Builds the exact editable geometry when available and transparently falls
/// back to the smoothed legacy point list for older projects.
Path buildDrawingStrokePath(DrawingStroke stroke, Rect artworkRect) =>
    stroke.orderedAnimationGeometry?.toPath(artworkRect) ??
    buildSmoothPath(stroke.orderedPoints, artworkRect);

Path _buildClipPath(List<List<Offset>> polygons, Rect artworkRect) {
  final path = Path();
  for (final polygon in polygons) {
    if (polygon.length < 3) continue;
    path.addPolygon([
      for (final point in polygon)
        Offset(
          artworkRect.left + point.dx * artworkRect.width,
          artworkRect.top + point.dy * artworkRect.height,
        ),
    ], true);
  }
  return path;
}

String _clipPolygonSignature(List<List<Offset>> polygons) {
  final value = StringBuffer();
  for (final polygon in polygons) {
    value.write('${polygon.length}:');
    for (final point in polygon) {
      value
        ..write(point.dx.toStringAsPrecision(12))
        ..write(',')
        ..write(point.dy.toStringAsPrecision(12))
        ..write(';');
    }
    value.write('|');
  }
  return value.toString();
}

final LinkedHashMap<(DrawingStroke, Rect), _CachedStrokePath> _strokePathCache =
    LinkedHashMap();
const _minimumStrokePathCacheEntries = 512;
const _strokePathRectWorkingSets = 2;
var _maximumStrokePathCacheEntries = _minimumStrokePathCacheEntries;
final Expando<DrawingStroke> _orderedSceneRevealStrokeCache = Expando();

DrawingStroke _resolvedOrderedSceneRevealStroke(DrawingStroke stroke) {
  final isSceneReveal =
      stroke.revealOnly &&
      stroke.id.startsWith('scene-reveal-') &&
      stroke.clipBounds != null;
  if (!isSceneReveal) return stroke;
  final cached = _orderedSceneRevealStrokeCache[stroke];
  if (cached != null) return cached;
  final bounds = stroke.clipBounds!;
  final drift = math.min(bounds.height * 0.055, 0.018);
  final y = bounds.center.dy;
  final rightToLeft =
      stroke.orderedPoints.first.dx > stroke.orderedPoints.last.dx;
  final points = [
    Offset(bounds.left, (y + drift * 0.25).clamp(bounds.top, bounds.bottom)),
    Offset(
      bounds.left + bounds.width * 0.32,
      (y - drift).clamp(bounds.top, bounds.bottom),
    ),
    Offset(
      bounds.left + bounds.width * 0.68,
      (y + drift * 0.72).clamp(bounds.top, bounds.bottom),
    ),
    Offset(bounds.right, (y - drift * 0.18).clamp(bounds.top, bounds.bottom)),
  ];
  final resolved = stroke.copyWith(
    points: rightToLeft ? points.reversed.toList(growable: false) : points,
    geometry: null,
    animationGeometry: null,
    reversed: false,
    revealStyle: RevealMaskStyle.directionalWipe,
  );
  _orderedSceneRevealStrokeCache[stroke] = resolved;
  return resolved;
}

void _reserveStrokePathWorkingSet(int strokeCount) {
  // Preview commonly resolves geometry once in the fitted artwork rectangle
  // and once in the project timing rectangle. A fixed 512-entry LRU used to
  // thrash when Auto Path produced 513+ strokes: the second sequential pass
  // evicted the first pass before it could be reused on the following frame.
  // Reserve both active working sets. This changes only cache retention; the
  // exact Path and PathMetric used for drawing remain untouched.
  _maximumStrokePathCacheEntries = math.max(
    _minimumStrokePathCacheEntries,
    strokeCount * _strokePathRectWorkingSets,
  );
  while (_strokePathCache.length > _maximumStrokePathCacheEntries) {
    _strokePathCache.remove(_strokePathCache.keys.first);
  }
}

_CachedStrokePath? _cachedStrokePath(DrawingStroke stroke, Rect artworkRect) {
  final key = (stroke, artworkRect);
  final cached = _strokePathCache.remove(key);
  if (cached != null) {
    _strokePathCache[key] = cached;
    return cached;
  }
  final path = buildDrawingStrokePath(stroke, artworkRect);
  final result = _CachedStrokePath(path);
  _strokePathCache[key] = result;
  if (_strokePathCache.length > _maximumStrokePathCacheEntries) {
    _strokePathCache.remove(_strokePathCache.keys.first);
  }
  return result;
}

List<StrokeGeometry> buildStrokeGeometry(
  List<DrawingStroke> strokes,
  Rect artworkRect, {
  Rect? timingRect,
}) {
  _reserveStrokePathWorkingSet(strokes.length);
  final result = <StrokeGeometry>[];
  // A scene mask is authored once but may be referenced by hundreds of
  // generated strokes. Canonicalizing it keeps those strokes in one renderer
  // batch and avoids rebuilding identical clip paths.
  final clipPathCache = <String, Path>{};
  final clipPathIdentityCache = HashMap<List<List<Offset>>, Path>.identity();
  final exclusionRectIdentityCache = HashMap<List<Rect>, List<Rect>>.identity();
  final sectionIndices = detectAutomaticSections(strokes);
  final resolvedTimingRect = timingRect ?? artworkRect;
  for (var index = 0; index < strokes.length; index++) {
    final stroke = _resolvedOrderedSceneRevealStroke(strokes[index]);
    final normalizedTimingPoints = stroke.orderedPoints;
    if (normalizedTimingPoints.length < 2) continue;
    final timingPoints = normalizedTimingPoints
        .map(
          (point) => Offset(
            resolvedTimingRect.left + point.dx * resolvedTimingRect.width,
            resolvedTimingRect.top + point.dy * resolvedTimingRect.height,
          ),
        )
        .toList(growable: false);
    var timingLength = 0.0;
    for (var pointIndex = 1; pointIndex < timingPoints.length; pointIndex++) {
      timingLength +=
          (timingPoints[pointIndex] - timingPoints[pointIndex - 1]).distance;
    }
    if (timingLength <= 0) continue;
    final cached = _cachedStrokePath(stroke, artworkRect);
    if (cached == null) continue;
    result.add(
      StrokeGeometry(
        strokeId: stroke.id,
        sectionId: stroke.sectionId,
        path: cached.path,
        timingLength: timingLength,
        timingStart: timingPoints.first,
        timingEnd: timingPoints.last,
        sectionIndex: sectionIndices[index],
        revealOnly: stroke.revealOnly,
        revealStyle: stroke.revealStyle,
        rightToLeft:
            normalizedTimingPoints.first.dx > normalizedTimingPoints.last.dx,
        revealWidth: stroke.revealWidth,
        clipRect: stroke.clipBounds == null
            ? null
            : Rect.fromLTRB(
                artworkRect.left + stroke.clipBounds!.left * artworkRect.width,
                artworkRect.top + stroke.clipBounds!.top * artworkRect.height,
                artworkRect.left + stroke.clipBounds!.right * artworkRect.width,
                artworkRect.top +
                    stroke.clipBounds!.bottom * artworkRect.height,
              ),
        clipPath: stroke.clipPolygons.isEmpty
            ? null
            : clipPathIdentityCache.putIfAbsent(
                stroke.clipPolygons,
                () => clipPathCache.putIfAbsent(
                  _clipPolygonSignature(stroke.clipPolygons),
                  () => _buildClipPath(stroke.clipPolygons, artworkRect),
                ),
              ),
        exclusionRects: exclusionRectIdentityCache.putIfAbsent(
          stroke.exclusionBounds,
          () => ImmutableRectList.freeze(
            stroke.exclusionBounds.map(
              (bounds) => Rect.fromLTRB(
                artworkRect.left + bounds.left * artworkRect.width,
                artworkRect.top + bounds.top * artworkRect.height,
                artworkRect.left + bounds.right * artworkRect.width,
                artworkRect.top + bounds.bottom * artworkRect.height,
              ),
            ),
          ),
        ),
        pausePoints: stroke.pausePoints,
        vectorMaskStrokes: stroke.vectorMaskStrokes,
        fillColorValue: stroke.fillColorValue,
        isTextShape: stroke.isTextShape,
        isFilledShape: stroke.isFilledShape,
        isGlobalDecoration: stroke.isGlobalDecoration,
      ),
    );
  }
  return result;
}

class _CachedStrokePath {
  const _CachedStrokePath(this.path);

  final Path path;
}

typedef _TimelinePlanKey = ({
  List<DrawingStroke> strokes,
  Rect artworkRect,
  Rect? timingRect,
  double durationSeconds,
  double? drawingDurationSeconds,
  double drawingSpeed,
  double penTravelSpeed,
  double startDelaySeconds,
  double endHoldSeconds,
  Map<String, SectionTiming> sectionTimings,
});

class _CompiledTimelinePlan {
  const _CompiledTimelinePlan({
    required this.visibleStrokes,
    required this.geometries,
    required this.sectionClips,
    required this.sections,
    required this.schedule,
    required this.completedReveals,
    required this.fullReveals,
    required this.sectionsWithDirectHandStrokes,
    required this.startDelay,
    required this.endHold,
  });

  final List<DrawingStroke> visibleStrokes;
  final List<StrokeGeometry> geometries;
  final List<Rect> sectionClips;
  final List<TimelineSectionDefinition> sections;
  final _TimelineSchedule schedule;
  final List<RevealedPath> completedReveals;
  final List<RevealedPath> fullReveals;
  final Set<String> sectionsWithDirectHandStrokes;
  final double startDelay;
  final double endHold;
}

final LinkedHashMap<_TimelinePlanKey, _CompiledTimelinePlan>
_timelinePlanCache = LinkedHashMap();
const _maximumTimelinePlanCacheEntries = 3;
const _maximumTimelinePlanCachePaths = 24000;

_CompiledTimelinePlan _compiledTimelinePlan({
  required List<DrawingStroke> strokes,
  required Rect artworkRect,
  required double durationSeconds,
  required double? drawingDurationSeconds,
  required double drawingSpeed,
  required double penTravelSpeed,
  required double startDelaySeconds,
  required double endHoldSeconds,
  required Map<String, SectionTiming> sectionTimings,
  required Rect? timingRect,
}) {
  final key = (
    strokes: strokes,
    artworkRect: artworkRect,
    timingRect: timingRect,
    durationSeconds: durationSeconds,
    drawingDurationSeconds: drawingDurationSeconds,
    drawingSpeed: drawingSpeed,
    penTravelSpeed: penTravelSpeed,
    startDelaySeconds: startDelaySeconds,
    endHoldSeconds: endHoldSeconds,
    sectionTimings: sectionTimings,
  );
  final cached = _timelinePlanCache.remove(key);
  if (cached != null) {
    _timelinePlanCache[key] = cached;
    return cached;
  }

  final visibleStrokes = strokes
      .where((stroke) => !stroke.hidden)
      .toList(growable: false);
  final resolvedTimingRect = timingRect ?? artworkRect;
  final geometries = buildStrokeGeometry(
    visibleStrokes,
    artworkRect,
    timingRect: resolvedTimingRect,
  );
  final sectionClips = _buildSectionClips(visibleStrokes, artworkRect);
  final sections = buildTimelineSections(visibleStrokes);
  final safeDuration = math.max(durationSeconds, 0.001);
  final startDelay = math.max(0.0, startDelaySeconds);
  final endHold = math.max(0.0, endHoldSeconds);
  final nominalDrawingDuration = math.max(
    0.001,
    drawingDurationSeconds ?? safeDuration - startDelay - endHold,
  );
  final schedule = _buildSchedule(
    geometries: geometries,
    minimumDrawWeight: resolvedTimingRect.shortestSide * 0.035,
    sections: sections,
    sectionTimings: sectionTimings,
    motionDuration: nominalDrawingDuration,
    drawingSpeed: drawingSpeed,
    penTravelSpeed: penTravelSpeed,
    timelineOffsetSeconds: startDelay,
  );
  final completedReveals = <RevealedPath>[
    for (final segment in schedule.segments)
      if (segment.kind == _TimelineSegmentKind.draw)
        _completedReveal(geometries[segment.strokeIndex], segment),
  ];
  final fullReveals = <RevealedPath>[
    for (final geometry in geometries) _fullReveal(geometry),
  ];
  final result = _CompiledTimelinePlan(
    visibleStrokes: visibleStrokes,
    geometries: geometries,
    sectionClips: sectionClips,
    sections: sections,
    schedule: schedule,
    completedReveals: List.unmodifiable(completedReveals),
    fullReveals: List.unmodifiable(fullReveals),
    sectionsWithDirectHandStrokes: {
      for (final geometry in geometries)
        if (!geometry.revealOnly && geometry.sectionId != null)
          geometry.sectionId!,
    },
    startDelay: startDelay,
    endHold: endHold,
  );
  _timelinePlanCache[key] = result;
  while (_timelinePlanCache.length > _maximumTimelinePlanCacheEntries ||
      (_timelinePlanCache.length > 1 &&
          _timelinePlanCache.values.fold<int>(
                0,
                (total, plan) => total + plan.geometries.length,
              ) >
              _maximumTimelinePlanCachePaths)) {
    _timelinePlanCache.remove(_timelinePlanCache.keys.first);
  }
  return result;
}

RevealedPath _fullReveal(StrokeGeometry geometry) => RevealedPath(
  path: geometry.path,
  sectionIndex: geometry.sectionIndex,
  revealWidth: geometry.revealWidth,
  clipRect: geometry.clipRect,
  clipPath: geometry.clipPath,
  exclusionRects: geometry.exclusionRects,
  revealStyle: geometry.revealStyle,
  rightToLeft: geometry.rightToLeft,
  vectorMaskStrokes: geometry.vectorMaskStrokes,
  fillColorValue: geometry.fillColorValue,
  isTextShape: geometry.isTextShape,
  isFilledShape: geometry.isFilledShape,
  isGlobalDecoration: geometry.isGlobalDecoration,
);

RevealedPath _completedReveal(
  StrokeGeometry geometry,
  _TimelineSegment segment,
) {
  final wholeStroke = segment.startProgress <= 0 && segment.endProgress >= 1;
  return RevealedPath(
    // Most generated strokes are complete segments. Reuse their compiled Path
    // identity; pause-split segments retain the exact metric extraction.
    path: wholeStroke
        ? geometry.path
        : geometry.metric.extractPath(
            geometry.length * segment.startProgress,
            geometry.length * segment.endProgress,
          ),
    sectionIndex: geometry.sectionIndex,
    revealWidth: geometry.revealWidth,
    clipRect: geometry.clipRect,
    clipPath: geometry.clipPath,
    exclusionRects: geometry.exclusionRects,
    revealStyle: geometry.revealStyle,
    rightToLeft: geometry.rightToLeft,
    vectorMaskStrokes: geometry.vectorMaskStrokes,
    strokeProgress: segment.endProgress,
    fillColorValue: geometry.fillColorValue,
    isTextShape: geometry.isTextShape,
    isFilledShape: geometry.isFilledShape,
    isGlobalDecoration: geometry.isGlobalDecoration,
  );
}

List<int> detectAutomaticSections(List<DrawingStroke> strokes) {
  if (strokes.isEmpty) return const [];
  if (strokes.any((stroke) => stroke.sectionId != null)) {
    final geometric = _detectGeometricSections(strokes);
    final keys = <String, int>{};
    final result = <int>[];
    for (var index = 0; index < strokes.length; index++) {
      final key = strokes[index].sectionId ?? 'manual-${geometric[index]}';
      result.add(keys.putIfAbsent(key, () => keys.length));
    }
    return result;
  }
  return _detectGeometricSections(strokes);
}

List<int> _detectGeometricSections(List<DrawingStroke> strokes) {
  final result = <int>[];
  var section = 0;
  var bounds = _normalizedStrokeBounds(strokes.first);
  result.add(section);

  for (var index = 1; index < strokes.length; index++) {
    final next = _normalizedStrokeBounds(strokes[index]);
    final verticalGap = next.top > bounds.bottom
        ? next.top - bounds.bottom
        : bounds.top > next.bottom
        ? bounds.top - next.bottom
        : 0.0;
    final centerDistance = (next.center.dy - bounds.center.dy).abs();
    if (verticalGap > 0.012 || centerDistance > 0.05) {
      section++;
      bounds = next;
    } else {
      bounds = bounds.expandToInclude(next);
    }
    result.add(section);
  }
  return result;
}

int automaticSectionCount(List<DrawingStroke> strokes) {
  final sections = detectAutomaticSections(strokes);
  return sections.isEmpty ? 0 : sections.last + 1;
}

List<TimelineSectionDefinition> buildTimelineSections(
  List<DrawingStroke> strokes,
) {
  final assignments = detectAutomaticSections(strokes);
  if (assignments.isEmpty) return const [];
  final sectionCount = assignments.reduce(math.max) + 1;
  return List.generate(sectionCount, (sectionIndex) {
    final strokeIndices = <int>[
      for (var index = 0; index < assignments.length; index++)
        if (assignments[index] == sectionIndex) index,
    ];
    final first = strokes[strokeIndices.first];
    return TimelineSectionDefinition(
      index: sectionIndex,
      key: first.sectionId == null
          ? 'stroke:${first.id}'
          : 'section:${first.sectionId}',
      label: first.name,
      strokeIndices: List.unmodifiable(strokeIndices),
    );
  });
}

Rect _normalizedStrokeBounds(DrawingStroke stroke) {
  final points = stroke.orderedPoints;
  if (points.isEmpty) return Rect.zero;
  var left = points.first.dx;
  var right = left;
  var top = points.first.dy;
  var bottom = top;
  for (final point in points.skip(1)) {
    left = math.min(left, point.dx);
    right = math.max(right, point.dx);
    top = math.min(top, point.dy);
    bottom = math.max(bottom, point.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

List<Rect> _buildSectionClips(List<DrawingStroke> strokes, Rect artworkRect) {
  final assignments = detectAutomaticSections(strokes);
  if (assignments.isEmpty) return const [];
  final count = assignments.reduce(math.max) + 1;
  final bounds = List<Rect?>.filled(count, null);
  for (var index = 0; index < strokes.length; index++) {
    final section = assignments[index];
    final strokeBounds = _normalizedStrokeBounds(strokes[index]);
    bounds[section] = bounds[section] == null
        ? strokeBounds
        : bounds[section]!.expandToInclude(strokeBounds);
  }

  final boundaries = <double>[0];
  for (var index = 0; index < count - 1; index++) {
    final current = bounds[index]!;
    final next = bounds[index + 1]!;
    final boundary = current.bottom <= next.top
        ? (current.bottom + next.top) / 2
        : (current.center.dy + next.center.dy) / 2;
    boundaries.add(boundary.clamp(0.0, 1.0));
  }
  boundaries.add(1);

  return List.generate(count, (index) {
    final top = artworkRect.top + boundaries[index] * artworkRect.height;
    final bottom = artworkRect.top + boundaries[index + 1] * artworkRect.height;
    return Rect.fromLTRB(artworkRect.left, top, artworkRect.right, bottom);
  });
}

TimelineSnapshot buildTimelineSnapshot({
  required List<DrawingStroke> strokes,
  required Rect artworkRect,
  required double progress,
  double durationSeconds = 1,
  double? drawingDurationSeconds,
  double drawingSpeed = 1,
  double penTravelSpeed = 1,
  double startDelaySeconds = 0,
  double endHoldSeconds = 0,
  Map<String, SectionTiming> sectionTimings = const {},
  Rect? timingRect,
}) {
  final plan = _compiledTimelinePlan(
    strokes: strokes,
    artworkRect: artworkRect,
    durationSeconds: durationSeconds,
    drawingDurationSeconds: drawingDurationSeconds,
    drawingSpeed: drawingSpeed,
    penTravelSpeed: penTravelSpeed,
    startDelaySeconds: startDelaySeconds,
    endHoldSeconds: endHoldSeconds,
    sectionTimings: sectionTimings,
    timingRect: timingRect,
  );
  final geometries = plan.geometries;
  final sectionClips = plan.sectionClips;
  if (geometries.isEmpty) {
    return TimelineSnapshot(
      revealedPaths: const [],
      handPosition: Offset.zero,
      handAngle: 0,
      handVisible: false,
      sectionClips: sectionClips,
    );
  }
  final sectionsWithDirectHandStrokes = plan.sectionsWithDirectHandStrokes;
  bool handFollows(StrokeGeometry geometry) =>
      !geometry.revealOnly ||
      geometry.sectionId == null ||
      !sectionsWithDirectHandStrokes.contains(geometry.sectionId);
  final fallbackRevealWidth = artworkRect.shortestSide * 0.05;
  final revealWidthScale = timingRect == null || timingRect.height <= 0
      ? 1.0
      : artworkRect.height / timingRect.height;

  final startDelay = plan.startDelay;
  final endHold = plan.endHold;
  final sections = plan.sections;
  final schedule = plan.schedule;
  final totalDuration = startDelay + schedule.duration + endHold;
  final time = progress.clamp(0.0, 1.0) * totalDuration;
  if (time < startDelay) {
    return TimelineSnapshot(
      revealedPaths: const [],
      handPosition: geometries.first.tangentAt(0).position,
      handAngle: 0,
      handVisible: false,
      sectionClips: sectionClips,
      phase: TimelinePhase.startDelay,
    );
  }

  final motionEnd = startDelay + schedule.duration;
  if (time >= motionEnd) {
    final last = geometries.last;
    final tangent = last.tangentAt(last.length);
    final finalTiming = _timingForSection(
      sections,
      sectionTimings,
      last.sectionIndex,
    );
    final authoredExit =
        finalTiming.handExitAnimation != SectionHandExitAnimation.none;
    final keepHandVisible = finalTiming.keepHandVisibleAfterDrawing;
    final fadeDuration = math.min(0.2, endHold);
    final holdElapsed = time - motionEnd;
    final opacity = fadeDuration <= 0
        ? 0.0
        : (1 - holdElapsed / fadeDuration).clamp(0.0, 1.0);
    final fullReveals = plan.fullReveals;
    return TimelineSnapshot(
      revealedPaths: fullReveals,
      handPosition: tangent.position,
      handAngle: _naturalHandAngle(
        last,
        tangent,
        last.length,
        fallbackRevealWidth,
        revealWidthScale,
      ),
      handVisible:
          handFollows(last) &&
          (keepHandVisible || (!authoredExit && opacity > 0)),
      handOpacity: keepHandVisible ? 1 : opacity,
      sectionClips: sectionClips,
      drawingComplete: true,
      phase: TimelinePhase.endHold,
      stableRevealSequence: StableRevealSequence(
        paths: fullReveals,
        visibleCount: fullReveals.length,
      ),
    );
  }

  final elapsed = time - startDelay;
  final segmentIndex = schedule.segmentIndexAt(elapsed);
  if (segmentIndex >= schedule.segments.length) {
    return _completedTimelineSnapshot(
      plan: plan,
      geometries: geometries,
      sectionClips: sectionClips,
      handVisible: handFollows(geometries.last),
      fallbackRevealWidth: fallbackRevealWidth,
      revealWidthScale: revealWidthScale,
    );
  }
  final segment = schedule.segments[segmentIndex];
  final cursor = elapsed - schedule.startTimeOf(segmentIndex);
  final completedRevealCount = schedule.completedDrawCountsBefore[segmentIndex];
  final completedReveals = plan.completedReveals;
  final stableSequence = StableRevealSequence(
    paths: completedReveals,
    visibleCount: completedRevealCount,
  );
  final revealed = _StableRevealListView(
    completedReveals,
    completedRevealCount,
  );
  final local = segment.duration == 0 ? 1.0 : cursor / segment.duration;
  if (segment.kind == _TimelineSegmentKind.draw) {
    final geometry = geometries[segment.strokeIndex];
    // Do not restart an ease curve for every generated stroke. On 50–100
    // tiny glyph paths that repeatedly stops and launches the hand, which
    // reads as shaking. Constant arc-length progress keeps the nib calm
    // while the smooth path still gives the motion its natural curvature.
    final motionProgress = local;
    final segmentProgress = lerpDouble(
      segment.startProgress,
      segment.endProgress,
      motionProgress,
    )!;
    final startDistance = geometry.length * segment.startProgress;
    final distance = geometry.length * segmentProgress;
    final tangent = geometry.tangentAt(distance);
    final activeReveal = distance > startDistance
        ? RevealedPath(
            path: geometry.metric.extractPath(startDistance, distance),
            sectionIndex: geometry.sectionIndex,
            revealWidth: geometry.revealWidth,
            clipRect: geometry.clipRect,
            clipPath: geometry.clipPath,
            exclusionRects: geometry.exclusionRects,
            revealStyle: geometry.revealStyle,
            activeBrushDirection:
                geometry.tangentAt(geometry.length).position -
                geometry.tangentAt(0).position,
            rightToLeft: geometry.rightToLeft,
            vectorMaskStrokes: geometry.vectorMaskStrokes,
            strokeProgress: segmentProgress,
            fillColorValue: geometry.fillColorValue,
            isTextShape: geometry.isTextShape,
            isFilledShape: geometry.isFilledShape,
            isGlobalDecoration: geometry.isGlobalDecoration,
          )
        : null;
    return TimelineSnapshot(
      revealedPaths: _StableRevealListView(
        completedReveals,
        completedRevealCount,
        activeReveal,
      ),
      handPosition: tangent.position,
      handAngle: _naturalHandAngle(
        geometry,
        tangent,
        distance,
        fallbackRevealWidth,
        revealWidthScale,
      ),
      handVisible: handFollows(geometry),
      sectionClips: sectionClips,
      phase: TimelinePhase.drawing,
      penIsDrawing: !geometry.revealOnly,
      cursor: ResolvedDrawingCursor(
        sectionId: geometry.sectionId,
        strokeId: geometry.strokeId,
        pathId: geometry.strokeId,
        progress: segmentProgress,
        distance: distance,
        worldPenPoint: tangent.position,
        activePathGeometry: geometry.path,
      ),
      stableRevealSequence: StableRevealSequence(
        paths: completedReveals,
        visibleCount: completedRevealCount,
        activePath: activeReveal,
      ),
    );
  }

  if (segment.kind == _TimelineSegmentKind.handEntrance ||
      segment.kind == _TimelineSegmentKind.handExit) {
    final geometry = geometries[segment.strokeIndex];
    final entrance = segment.kind == _TimelineSegmentKind.handEntrance;
    final tangent = geometry.tangentAt(entrance ? 0 : geometry.length);
    final timing = _timingForSection(
      sections,
      sectionTimings,
      geometry.sectionIndex,
    );
    final eased = _easeInOut(local);
    final edge = _nearestOutsidePoint(artworkRect, tangent.position);
    var position = tangent.position;
    var opacity = 1.0;
    if (entrance) {
      switch (timing.handEntranceAnimation) {
        case SectionHandEntranceAnimation.none:
          break;
        case SectionHandEntranceAnimation.fadeIn:
          opacity = eased;
        case SectionHandEntranceAnimation.moveIn:
          position = Offset.lerp(edge, tangent.position, eased)!;
        case SectionHandEntranceAnimation.slingshot:
          position = Offset.lerp(edge, tangent.position, _easeOutBack(local))!;
      }
    } else {
      switch (timing.handExitAnimation) {
        case SectionHandExitAnimation.none:
        case SectionHandExitAnimation.disappear:
          break;
        case SectionHandExitAnimation.fadeOut:
          opacity = 1 - eased;
        case SectionHandExitAnimation.moveOut:
          position = Offset.lerp(tangent.position, edge, eased)!;
        case SectionHandExitAnimation.slingshot:
          position = Offset.lerp(tangent.position, edge, _easeInBack(local))!;
      }
    }
    return TimelineSnapshot(
      revealedPaths: revealed,
      handPosition: position,
      handAngle: _naturalHandAngle(
        geometry,
        tangent,
        entrance ? 0 : geometry.length,
        fallbackRevealWidth,
        revealWidthScale,
      ),
      handVisible: handFollows(geometry) && opacity > 0,
      handOpacity: opacity.clamp(0.0, 1.0),
      sectionClips: sectionClips,
      phase: entrance ? TimelinePhase.handEntrance : TimelinePhase.handExit,
      stableRevealSequence: stableSequence,
    );
  }

  if (segment.kind == _TimelineSegmentKind.pauseBefore ||
      segment.kind == _TimelineSegmentKind.pauseAfter) {
    final geometry = geometries[segment.strokeIndex];
    final atStart = segment.kind == _TimelineSegmentKind.pauseBefore;
    final tangent = geometry.tangentAt(atStart ? 0 : geometry.length);
    final timing = _timingForSection(
      sections,
      sectionTimings,
      geometry.sectionIndex,
    );
    return TimelineSnapshot(
      revealedPaths: revealed,
      handPosition: tangent.position,
      handAngle: _naturalHandAngle(
        geometry,
        tangent,
        atStart ? 0 : geometry.length,
        fallbackRevealWidth,
        revealWidthScale,
      ),
      handVisible:
          handFollows(geometry) &&
          (timing.pauseHandBehavior == PauseHandBehavior.keepVisible ||
              (!atStart && timing.keepHandVisibleAfterDrawing)),
      sectionClips: sectionClips,
      phase: atStart ? TimelinePhase.pauseBefore : TimelinePhase.pauseAfter,
      stableRevealSequence: stableSequence,
    );
  }

  if (segment.kind == _TimelineSegmentKind.strokePause) {
    final geometry = geometries[segment.strokeIndex];
    final tangent = geometry.tangentAt(geometry.length * segment.startProgress);
    return TimelineSnapshot(
      revealedPaths: revealed,
      handPosition: tangent.position,
      handAngle: _naturalHandAngle(
        geometry,
        tangent,
        geometry.length * segment.startProgress,
        fallbackRevealWidth,
        revealWidthScale,
      ),
      handVisible: handFollows(geometry) && segment.keepHandVisible,
      sectionClips: sectionClips,
      phase: TimelinePhase.strokePause,
      penIsDrawing: false,
      stableRevealSequence: stableSequence,
    );
  }

  final from = geometries[segment.strokeIndex];
  final to = geometries[segment.strokeIndex + 1];
  final fromTangent = from.tangentAt(from.length);
  final toTangent = to.tangentAt(0);
  final eased = _easeInOut(local);
  return TimelineSnapshot(
    revealedPaths: revealed,
    handPosition: Offset.lerp(fromTangent.position, toTangent.position, eased)!,
    handAngle: 0,
    // A gap between two generated paths is always a real pen lift. Keeping
    // the hand visible here made it dart across holes and nearby letters as
    // if those invisible connections were intentional strokes.
    handVisible: false,
    sectionClips: sectionClips,
    phase: TimelinePhase.travel,
    penLiftProgress: local,
    penTravelDistance: (toTangent.position - fromTangent.position).distance,
    stableRevealSequence: stableSequence,
  );
}

TimelineSnapshot _completedTimelineSnapshot({
  required _CompiledTimelinePlan plan,
  required List<StrokeGeometry> geometries,
  required List<Rect> sectionClips,
  required bool handVisible,
  required double fallbackRevealWidth,
  required double revealWidthScale,
}) {
  final last = geometries.last;
  final tangent = last.tangentAt(last.length);
  final fullReveals = plan.fullReveals;
  return TimelineSnapshot(
    revealedPaths: fullReveals,
    handPosition: tangent.position,
    handAngle: _naturalHandAngle(
      last,
      tangent,
      last.length,
      fallbackRevealWidth,
      revealWidthScale,
    ),
    handVisible: handVisible,
    sectionClips: sectionClips,
    drawingComplete: true,
    phase: TimelinePhase.endHold,
    stableRevealSequence: StableRevealSequence(
      paths: fullReveals,
      visibleCount: fullReveals.length,
    ),
  );
}

double _naturalHandAngle(
  StrokeGeometry geometry,
  Tangent tangent,
  double distance,
  double fallbackRevealWidth,
  double revealWidthScale,
) {
  if (geometry.revealOnly) return 0;
  return const NaturalHandMotion().angleAt(
    tangent: tangent,
    distance: distance,
    pathLength: geometry.length,
    revealWidth: geometry.revealWidth == null
        ? fallbackRevealWidth
        : geometry.revealWidth! * revealWidthScale,
  );
}

double timelineDurationSeconds({
  required List<DrawingStroke> strokes,
  required Rect timingRect,
  required double durationSeconds,
  double? drawingDurationSeconds,
  double drawingSpeed = 1,
  double penTravelSpeed = 1,
  required double startDelaySeconds,
  required double endHoldSeconds,
  Map<String, SectionTiming> sectionTimings = const {},
}) {
  final visibleStrokes = strokes.where((stroke) => !stroke.hidden).toList();
  if (visibleStrokes.isEmpty) return math.max(durationSeconds, 0.001);
  final safeDuration = math.max(durationSeconds, 0.001);
  final startDelay = math.max(0.0, startDelaySeconds);
  final endHold = math.max(0.0, endHoldSeconds);
  final nominalDrawingDuration = math.max(
    0.001,
    drawingDurationSeconds ?? safeDuration - startDelay - endHold,
  );
  final schedule = _buildSchedule(
    geometries: buildStrokeGeometry(visibleStrokes, timingRect),
    minimumDrawWeight: timingRect.shortestSide * 0.035,
    sections: buildTimelineSections(visibleStrokes),
    sectionTimings: sectionTimings,
    motionDuration: nominalDrawingDuration,
    drawingSpeed: drawingSpeed,
    penTravelSpeed: penTravelSpeed,
    timelineOffsetSeconds: startDelay,
  );
  return startDelay + schedule.duration + endHold;
}

double projectTimelineDuration(HandDrawProject project) =>
    resolveProjectTimeline(project).durationSeconds;

/// Returns the exact drawing time assigned to one stroke by the production
/// schedule. Isolated stroke previews use this value so their hand movement
/// keeps the same authored speed as the full Preview and MOV export.
double projectTimelineStrokeDrawingDuration(
  HandDrawProject project,
  int strokeIndex,
) {
  if (strokeIndex < 0 || strokeIndex >= project.strokes.length) return 0;
  final target = project.strokes[strokeIndex];
  if (target.hidden) return 0;
  final visibleStrokes = project.strokes
      .where((stroke) => !stroke.hidden)
      .toList(growable: false);
  final visibleIndex = visibleStrokes.indexWhere(
    (stroke) => stroke.id == target.id,
  );
  if (visibleIndex < 0) return 0;
  final timingRect = Rect.fromLTWH(
    0,
    0,
    project.canvasWidth.toDouble(),
    project.canvasHeight.toDouble(),
  );
  final geometries = buildStrokeGeometry(visibleStrokes, timingRect);
  if (visibleIndex >= geometries.length) return 0;
  final schedule = _buildSchedule(
    geometries: geometries,
    minimumDrawWeight: timingRect.shortestSide * 0.035,
    sections: buildTimelineSections(visibleStrokes),
    sectionTimings: project.sectionTimings,
    motionDuration: project.drawingDurationSeconds,
    drawingSpeed: project.drawingSpeed,
    penTravelSpeed: project.penTravelSpeed,
    timelineOffsetSeconds: math.max(0.0, project.startDelaySeconds),
  );
  return schedule.segments
      .where(
        (segment) =>
            segment.strokeIndex == visibleIndex &&
            segment.kind == _TimelineSegmentKind.draw,
      )
      .fold(0.0, (duration, segment) => duration + segment.duration);
}

/// Resolves the visible time range of every applied section using the exact
/// motion schedule consumed by Preview and export.
// Weak keys keep repeated UI updates cheap without retaining closed projects.
final _sectionSpanCache = Expando<List<ProjectTimelineSectionSpan>>();

List<ProjectTimelineSectionSpan> projectTimelineSectionSpans(
  HandDrawProject project,
) =>
    _sectionSpanCache[project] ??= _computeProjectTimelineSectionSpans(project);

List<ProjectTimelineSectionSpan> _computeProjectTimelineSectionSpans(
  HandDrawProject project,
) {
  final visibleStrokes = project.strokes
      .where((stroke) => !stroke.hidden)
      .toList(growable: false);
  if (visibleStrokes.isEmpty) return const [];

  final timingRect = Rect.fromLTWH(
    0,
    0,
    project.canvasWidth.toDouble(),
    project.canvasHeight.toDouble(),
  );
  final geometries = buildStrokeGeometry(visibleStrokes, timingRect);
  if (geometries.isEmpty) return const [];
  final sections = buildTimelineSections(visibleStrokes);
  final startDelay = math.max(0.0, project.startDelaySeconds);
  final endHold = math.max(0.0, project.endHoldSeconds);
  final schedule = _buildSchedule(
    geometries: geometries,
    minimumDrawWeight: timingRect.shortestSide * 0.035,
    sections: sections,
    sectionTimings: project.sectionTimings,
    motionDuration: project.drawingDurationSeconds,
    drawingSpeed: project.drawingSpeed,
    penTravelSpeed: project.penTravelSpeed,
    timelineOffsetSeconds: startDelay,
  );

  final starts = <int, double>{};
  final ends = <int, double>{};
  var cursor = startDelay;
  for (final segment in schedule.segments) {
    final geometryIndex = segment.strokeIndex;
    final sectionIndex = geometries[geometryIndex].sectionIndex;
    starts.putIfAbsent(sectionIndex, () => cursor);
    cursor += segment.duration;
    ends[sectionIndex] = cursor;
  }
  if (starts.isEmpty) return const [];
  starts[starts.keys.reduce(math.min)] = 0;
  final lastSection = ends.keys.reduce(math.max);
  ends[lastSection] = cursor + endHold;

  return List.unmodifiable([
    for (final section in sections)
      if (starts[section.index] case final start?)
        ProjectTimelineSectionSpan(
          sectionId: section.key.startsWith('section:')
              ? section.key.substring('section:'.length)
              : section.key,
          startSeconds: start,
          endSeconds: ends[section.index] ?? start,
        ),
  ]);
}

// Weak keys keep repeated UI updates cheap without retaining closed projects.
final _sectionMetricsCache =
    Expando<Map<String, ProjectTimelineSectionMetrics>>();

Map<String, ProjectTimelineSectionMetrics> projectTimelineSectionMetrics(
  HandDrawProject project,
) => _sectionMetricsCache[project] ??= _computeProjectTimelineSectionMetrics(
  project,
);

Map<String, ProjectTimelineSectionMetrics>
_computeProjectTimelineSectionMetrics(HandDrawProject project) {
  final visibleStrokes = project.strokes
      .where((stroke) => !stroke.hidden)
      .toList(growable: false);
  if (visibleStrokes.isEmpty) return const {};
  final timingRect = Rect.fromLTWH(
    0,
    0,
    project.canvasWidth.toDouble(),
    project.canvasHeight.toDouble(),
  );
  final geometries = buildStrokeGeometry(visibleStrokes, timingRect);
  if (geometries.isEmpty) return const {};
  final sections = buildTimelineSections(visibleStrokes);
  final schedule = _buildSchedule(
    geometries: geometries,
    minimumDrawWeight: timingRect.shortestSide * 0.035,
    sections: sections,
    sectionTimings: project.sectionTimings,
    motionDuration: project.drawingDurationSeconds,
    drawingSpeed: project.drawingSpeed,
    penTravelSpeed: project.penTravelSpeed,
    timelineOffsetSeconds: math.max(0.0, project.startDelaySeconds),
  );
  final drawing = <int, double>{};
  final pausesBefore = <int, double>{};
  final entrances = <int, double>{};
  final pauses = <int, double>{};
  final exits = <int, double>{};
  final transitions = <int, double>{};
  for (final segment in schedule.segments) {
    final sectionIndex = geometries[segment.strokeIndex].sectionIndex;
    switch (segment.kind) {
      case _TimelineSegmentKind.draw:
        drawing.update(
          sectionIndex,
          (value) => value + segment.duration,
          ifAbsent: () => segment.duration,
        );
      case _TimelineSegmentKind.pauseAfter:
        pauses.update(
          sectionIndex,
          (value) => value + segment.duration,
          ifAbsent: () => segment.duration,
        );
      case _TimelineSegmentKind.pauseBefore:
        pausesBefore.update(
          sectionIndex,
          (value) => value + segment.duration,
          ifAbsent: () => segment.duration,
        );
      case _TimelineSegmentKind.handEntrance:
        entrances.update(
          sectionIndex,
          (value) => value + segment.duration,
          ifAbsent: () => segment.duration,
        );
      case _TimelineSegmentKind.handExit:
        exits.update(
          sectionIndex,
          (value) => value + segment.duration,
          ifAbsent: () => segment.duration,
        );
      case _TimelineSegmentKind.travel:
        final nextIndex = math.min(
          segment.strokeIndex + 1,
          geometries.length - 1,
        );
        if (geometries[nextIndex].sectionIndex != sectionIndex) {
          transitions.update(
            sectionIndex,
            (value) => value + segment.duration,
            ifAbsent: () => segment.duration,
          );
        }
      case _TimelineSegmentKind.strokePause:
        break;
    }
  }
  return Map.unmodifiable({
    for (final section in sections)
      _publicSectionId(section.key): ProjectTimelineSectionMetrics(
        sectionId: _publicSectionId(section.key),
        pauseBeforeSeconds: pausesBefore[section.index] ?? 0,
        handEntranceSeconds: entrances[section.index] ?? 0,
        animationSeconds: drawing[section.index] ?? 0,
        pauseAfterSeconds: pauses[section.index] ?? 0,
        handExitSeconds: exits[section.index] ?? 0,
        transitionAfterSeconds: transitions[section.index] ?? 0,
      ),
  });
}

String _publicSectionId(String key) =>
    key.startsWith('section:') ? key.substring('section:'.length) : key;

/// Converts an absolute preview time to the drawing timeline's normalized
/// progress. A Voice Guide may be longer than the drawing, but it must never
/// stretch the hand motion or reveal animation.
double projectTimelineProgressAt(
  HandDrawProject project,
  double positionSeconds,
) {
  final duration = projectTimelineDuration(project);
  if (duration <= 0) return 0;
  return (positionSeconds / duration).clamp(0.0, 1.0);
}

final _projectResolutionCache = Expando<ProjectTimelineResolution>();

ProjectTimelineResolution resolveProjectTimeline(
  HandDrawProject project, {
  double? drawingSpeedOverride,
}) {
  if (drawingSpeedOverride != null) {
    return _computeProjectTimeline(
      project,
      drawingSpeedOverride: drawingSpeedOverride,
    );
  }
  return _projectResolutionCache[project] ??= _computeProjectTimeline(project);
}

ProjectTimelineResolution _computeProjectTimeline(
  HandDrawProject project, {
  double? drawingSpeedOverride,
}) {
  final visibleStrokes = project.strokes
      .where((stroke) => !stroke.hidden)
      .toList();
  if (visibleStrokes.isEmpty) {
    final duration = math.max(project.durationSeconds, 0.001);
    return ProjectTimelineResolution(
      durationSeconds: duration,
      voiceCues: const {},
      breakdown: ProjectTimingBreakdown(
        startDelaySeconds: 0,
        drawingSeconds: duration,
        penTravelSeconds: 0,
        sectionPauseSeconds: 0,
        handAnimationSeconds: 0,
        endHoldSeconds: 0,
      ),
    );
  }
  final timingRect = Rect.fromLTWH(
    0,
    0,
    project.canvasWidth.toDouble(),
    project.canvasHeight.toDouble(),
  );
  final startDelay = math.max(0.0, project.startDelaySeconds);
  final endHold = math.max(0.0, project.endHoldSeconds);
  final schedule = _buildSchedule(
    geometries: buildStrokeGeometry(visibleStrokes, timingRect),
    minimumDrawWeight: timingRect.shortestSide * 0.035,
    sections: buildTimelineSections(visibleStrokes),
    sectionTimings: project.sectionTimings,
    motionDuration: project.drawingDurationSeconds,
    drawingSpeed: drawingSpeedOverride ?? project.drawingSpeed,
    penTravelSpeed: project.penTravelSpeed,
    timelineOffsetSeconds: startDelay,
  );
  return ProjectTimelineResolution(
    durationSeconds: startDelay + schedule.duration + endHold,
    voiceCues: schedule.voiceCues,
    breakdown: ProjectTimingBreakdown(
      startDelaySeconds: startDelay,
      drawingSeconds: schedule.drawingDuration,
      penTravelSeconds: schedule.travelDuration,
      sectionPauseSeconds: schedule.pauseDuration,
      handAnimationSeconds: schedule.handAnimationDuration,
      endHoldSeconds: endHold,
    ),
  );
}

/// Finds a global drawing speed that reaches [targetDurationSeconds] without
/// changing start/end holds, section pauses, voice cues, or pen travel speed.
/// Preview, audio, and export subsequently consume the same resolved timeline.
FitToDurationResult fitProjectToDuration(
  HandDrawProject project,
  double targetDurationSeconds,
) {
  const minimumSpeed = minimumProjectDrawingSpeed;
  const maximumSpeed = maximumProjectDrawingSpeed;
  final target = targetDurationSeconds;
  final fastest = resolveProjectTimeline(
    project,
    drawingSpeedOverride: maximumSpeed,
  ).durationSeconds;
  final slowest = resolveProjectTimeline(
    project,
    drawingSpeedOverride: minimumSpeed,
  ).durationSeconds;
  if (!target.isFinite ||
      target < fastest - 0.001 ||
      target > slowest + 0.001) {
    return FitToDurationResult.impossible(
      targetDurationSeconds: target,
      minimumDurationSeconds: fastest,
      maximumDurationSeconds: slowest,
    );
  }

  var lowerSpeed = minimumSpeed;
  var upperSpeed = maximumSpeed;
  for (var iteration = 0; iteration < 64; iteration++) {
    final speed = (lowerSpeed + upperSpeed) / 2;
    final duration = resolveProjectTimeline(
      project,
      drawingSpeedOverride: speed,
    ).durationSeconds;
    if (duration > target) {
      lowerSpeed = speed;
    } else {
      upperSpeed = speed;
    }
  }
  final speed = (lowerSpeed + upperSpeed) / 2;
  final duration = resolveProjectTimeline(
    project,
    drawingSpeedOverride: speed,
  ).durationSeconds;
  return FitToDurationResult.success(
    targetDurationSeconds: target,
    minimumDurationSeconds: fastest,
    maximumDurationSeconds: slowest,
    drawingSpeed: speed,
    resolvedDurationSeconds: duration,
  );
}

double _easeInOut(double value) => value < 0.5
    ? 4 * value * value * value
    : 1 - math.pow(-2 * value + 2, 3) / 2;

double _easeOutBack(double value) {
  const overshoot = 1.70158;
  final shifted = value - 1;
  return 1 +
      (overshoot + 1) * shifted * shifted * shifted +
      overshoot * shifted * shifted;
}

double _easeInBack(double value) {
  const overshoot = 1.70158;
  return (overshoot + 1) * value * value * value - overshoot * value * value;
}

Offset _nearestOutsidePoint(Rect rect, Offset point) {
  final distances = <(double, Offset)>[
    (point.dx - rect.left, Offset(rect.left - rect.width * .18, point.dy)),
    (rect.right - point.dx, Offset(rect.right + rect.width * .18, point.dy)),
    (point.dy - rect.top, Offset(point.dx, rect.top - rect.height * .18)),
    (rect.bottom - point.dy, Offset(point.dx, rect.bottom + rect.height * .18)),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  return distances.first.$2;
}

enum _TimelineSegmentKind {
  draw,
  travel,
  pauseBefore,
  handEntrance,
  pauseAfter,
  handExit,
  strokePause,
}

class _TimelineSegment {
  const _TimelineSegment({
    required this.strokeIndex,
    required this.duration,
    required this.kind,
    this.startProgress = 0,
    this.endProgress = 1,
    this.keepHandVisible = true,
  });

  final int strokeIndex;
  final double duration;
  final _TimelineSegmentKind kind;
  final double startProgress;
  final double endProgress;
  final bool keepHandVisible;
}

class _WeightedTimelineSegment {
  const _WeightedTimelineSegment({
    required this.strokeIndex,
    required this.weight,
    required this.kind,
  });

  final int strokeIndex;
  final double weight;
  final _TimelineSegmentKind kind;
}

class _TimelineSchedule {
  _TimelineSchedule(
    this.segments,
    this.duration,
    this.voiceCues,
    this.drawingDuration,
    this.travelDuration,
    this.pauseDuration,
    this.handAnimationDuration,
  ) : cumulativeEndTimes = _buildCumulativeEndTimes(segments),
      completedDrawCountsBefore = _buildCompletedDrawCounts(segments);

  final List<_TimelineSegment> segments;
  final double duration;
  final Map<String, SectionVoiceCueResolution> voiceCues;
  final double drawingDuration;
  final double travelDuration;
  final double pauseDuration;
  final double handAnimationDuration;
  final List<double> cumulativeEndTimes;
  final List<int> completedDrawCountsBefore;

  int segmentIndexAt(double elapsed) {
    var low = 0;
    var high = cumulativeEndTimes.length;
    // Match the old `cursor >= duration` boundary behavior: a segment is
    // complete at its exact end time, including zero-duration segments.
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (elapsed < cumulativeEndTimes[middle]) {
        high = middle;
      } else {
        low = middle + 1;
      }
    }
    return low;
  }

  double startTimeOf(int segmentIndex) =>
      segmentIndex <= 0 ? 0 : cumulativeEndTimes[segmentIndex - 1];
}

List<double> _buildCumulativeEndTimes(List<_TimelineSegment> segments) {
  var elapsed = 0.0;
  return List<double>.unmodifiable([
    for (final segment in segments) elapsed += segment.duration,
  ]);
}

List<int> _buildCompletedDrawCounts(List<_TimelineSegment> segments) {
  var completed = 0;
  final result = <int>[];
  for (final segment in segments) {
    result.add(completed);
    if (segment.kind == _TimelineSegmentKind.draw) completed++;
  }
  return List<int>.unmodifiable(result);
}

_TimelineSchedule _buildSchedule({
  required List<StrokeGeometry> geometries,
  required double minimumDrawWeight,
  required List<TimelineSectionDefinition> sections,
  required Map<String, SectionTiming> sectionTimings,
  required double motionDuration,
  required double drawingSpeed,
  required double penTravelSpeed,
  required double timelineOffsetSeconds,
}) {
  if (geometries.isEmpty) {
    return _TimelineSchedule(const [], 0, const {}, 0, 0, 0, 0);
  }
  final weighted = <_WeightedTimelineSegment>[];
  for (var index = 0; index < geometries.length; index++) {
    final geometry = geometries[index];
    weighted.add(
      _WeightedTimelineSegment(
        strokeIndex: index,
        weight: math.max(geometry.timingLength, minimumDrawWeight),
        kind: _TimelineSegmentKind.draw,
      ),
    );
    if (index < geometries.length - 1) {
      final end = geometry.timingEnd;
      final start = geometries[index + 1].timingStart;
      weighted.add(
        _WeightedTimelineSegment(
          strokeIndex: index,
          weight: ((start - end).distance * 0.08).clamp(2.0, 24.0),
          kind: _TimelineSegmentKind.travel,
        ),
      );
    }
  }
  final totalWeight = weighted.fold<double>(
    0,
    (sum, item) => sum + item.weight,
  );
  final nominalDrawDurationBySection = <int, double>{};
  for (final item in weighted) {
    if (item.kind != _TimelineSegmentKind.draw) continue;
    final sectionIndex = geometries[item.strokeIndex].sectionIndex;
    final duration = motionDuration * item.weight / totalWeight;
    nominalDrawDurationBySection.update(
      sectionIndex,
      (value) => value + duration,
      ifAbsent: () => duration,
    );
  }
  final firstBySection = <int, int>{};
  final lastBySection = <int, int>{};
  final firstHandBySection = <int, int>{};
  final lastHandBySection = <int, int>{};
  for (var index = 0; index < geometries.length; index++) {
    final section = geometries[index].sectionIndex;
    firstBySection.putIfAbsent(section, () => index);
    lastBySection[section] = index;
    if (!geometries[index].revealOnly) {
      firstHandBySection.putIfAbsent(section, () => index);
      lastHandBySection[section] = index;
    }
  }
  // Reveal-only sections still display the hand. They therefore need the same
  // authored entrance/exit scheduling as direct drawing sections. A mixed
  // section keeps following only its direct strokes so its completion mask
  // remains hand-free.
  for (final section in firstBySection.keys) {
    firstHandBySection.putIfAbsent(section, () => firstBySection[section]!);
    lastHandBySection.putIfAbsent(section, () => lastBySection[section]!);
  }

  final scheduled = <_TimelineSegment>[];
  final voiceCues = <String, SectionVoiceCueResolution>{};
  var scheduledDuration = 0.0;
  var drawingDuration = 0.0;
  var travelDuration = 0.0;
  var pauseDuration = 0.0;
  var handAnimationDuration = 0.0;
  void addSegment(_TimelineSegment segment) {
    scheduled.add(segment);
    scheduledDuration += segment.duration;
    switch (segment.kind) {
      case _TimelineSegmentKind.draw:
        drawingDuration += segment.duration;
      case _TimelineSegmentKind.travel:
        travelDuration += segment.duration;
      case _TimelineSegmentKind.pauseBefore:
      case _TimelineSegmentKind.pauseAfter:
      case _TimelineSegmentKind.strokePause:
        pauseDuration += segment.duration;
      case _TimelineSegmentKind.handEntrance:
      case _TimelineSegmentKind.handExit:
        handAnimationDuration += segment.duration;
    }
  }

  for (final item in weighted) {
    final geometry = geometries[item.strokeIndex];
    final timing = _timingForSection(
      sections,
      sectionTimings,
      geometry.sectionIndex,
    );
    if (item.kind == _TimelineSegmentKind.draw &&
        firstBySection[geometry.sectionIndex] == item.strokeIndex) {
      var pauseBefore = timing.pauseBeforeSeconds;
      final cue = timing.voiceCueSeconds;
      if (cue != null) {
        final sectionKey = sections[geometry.sectionIndex].key;
        final earliestStart = timelineOffsetSeconds + scheduledDuration;
        final delta = cue - earliestStart;
        final hasConflict = delta < -0.0005;
        pauseBefore = math.max(0, delta);
        voiceCues[sectionKey] = SectionVoiceCueResolution(
          sectionKey: sectionKey,
          cueSeconds: cue,
          earliestStartSeconds: earliestStart,
          resolvedPauseBeforeSeconds: pauseBefore,
          hasConflict: hasConflict,
        );
      }
      if (pauseBefore > 0) {
        addSegment(
          _TimelineSegment(
            strokeIndex:
                firstHandBySection[geometry.sectionIndex] ?? item.strokeIndex,
            duration: pauseBefore,
            kind: _TimelineSegmentKind.pauseBefore,
          ),
        );
      }
      final entranceStroke = firstHandBySection[geometry.sectionIndex];
      if (entranceStroke != null &&
          timing.handEntranceAnimation != SectionHandEntranceAnimation.none &&
          timing.handEntranceDurationSeconds > 0) {
        addSegment(
          _TimelineSegment(
            strokeIndex: entranceStroke,
            duration: timing.handEntranceDurationSeconds,
            kind: _TimelineSegmentKind.handEntrance,
          ),
        );
      }
    }
    final nominalDuration = motionDuration * item.weight / totalWeight;
    if (item.kind == _TimelineSegmentKind.draw) {
      final targetDuration = timing.animationDurationSeconds;
      final effectiveSpeed =
          drawingSpeed.clamp(
            minimumProjectDrawingSpeed,
            maximumProjectDrawingSpeed,
          ) *
          timing.speedMultiplier;
      final drawDuration = targetDuration == null
          ? nominalDuration / effectiveSpeed
          : targetDuration *
                nominalDuration /
                math.max(
                  nominalDrawDurationBySection[geometry.sectionIndex] ?? 0,
                  0.000001,
                ) /
                effectiveSpeed;
      var startProgress = 0.0;
      for (final pause in geometry.pausePoints) {
        final pauseProgress = pause.progress.clamp(0.01, 0.99);
        final portion = pauseProgress - startProgress;
        if (portion > 0) {
          addSegment(
            _TimelineSegment(
              strokeIndex: item.strokeIndex,
              duration: drawDuration * portion,
              kind: _TimelineSegmentKind.draw,
              startProgress: startProgress,
              endProgress: pauseProgress,
            ),
          );
        }
        addSegment(
          _TimelineSegment(
            strokeIndex: item.strokeIndex,
            duration: pause.durationSeconds,
            kind: _TimelineSegmentKind.strokePause,
            startProgress: pauseProgress,
            endProgress: pauseProgress,
            keepHandVisible: pause.keepHandVisible,
          ),
        );
        startProgress = pauseProgress;
      }
      if (startProgress < 1) {
        addSegment(
          _TimelineSegment(
            strokeIndex: item.strokeIndex,
            duration: drawDuration * (1 - startProgress),
            kind: _TimelineSegmentKind.draw,
            startProgress: startProgress,
            endProgress: 1,
          ),
        );
      }
    } else {
      final nextIndex = math.min(item.strokeIndex + 1, geometries.length - 1);
      final isSectionTransition =
          geometries[nextIndex].sectionIndex != geometry.sectionIndex;
      addSegment(
        _TimelineSegment(
          strokeIndex: item.strokeIndex,
          duration: isSectionTransition && timing.transitionAfterSeconds != null
              ? timing.transitionAfterSeconds!
              : nominalDuration / penTravelSpeed.clamp(0.25, 4.0),
          kind: item.kind,
        ),
      );
    }
    if (item.kind == _TimelineSegmentKind.draw &&
        lastBySection[geometry.sectionIndex] == item.strokeIndex) {
      final exitStroke =
          lastHandBySection[geometry.sectionIndex] ?? item.strokeIndex;
      if (timing.pauseAfterSeconds > 0) {
        addSegment(
          _TimelineSegment(
            strokeIndex: exitStroke,
            duration: timing.pauseAfterSeconds,
            kind: _TimelineSegmentKind.pauseAfter,
          ),
        );
      }
      if (lastHandBySection[geometry.sectionIndex] != null &&
          !timing.keepHandVisibleAfterDrawing &&
          timing.handExitAnimation != SectionHandExitAnimation.none &&
          timing.handExitAnimation != SectionHandExitAnimation.disappear &&
          timing.handExitDurationSeconds > 0) {
        addSegment(
          _TimelineSegment(
            strokeIndex: exitStroke,
            duration: timing.handExitDurationSeconds,
            kind: _TimelineSegmentKind.handExit,
          ),
        );
      }
    }
  }
  return _TimelineSchedule(
    List.unmodifiable(scheduled),
    scheduledDuration,
    Map.unmodifiable(voiceCues),
    drawingDuration,
    travelDuration,
    pauseDuration,
    handAnimationDuration,
  );
}

SectionTiming _timingForSection(
  List<TimelineSectionDefinition> sections,
  Map<String, SectionTiming> timings,
  int sectionIndex,
) {
  if (sectionIndex < 0 || sectionIndex >= sections.length) {
    return const SectionTiming();
  }
  return timings[sections[sectionIndex].key] ?? const SectionTiming();
}

/// Drops only derived geometry/schedule working sets; documents remain intact.
void clearMotionRenderingCaches() {
  _strokePathCache.clear();
  _timelinePlanCache.clear();
}
