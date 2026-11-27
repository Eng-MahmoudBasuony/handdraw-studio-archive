import 'dart:async';
import 'dart:math' as math;
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_rect_list.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/polyline_bezier_fitter.dart';

class AutoPathPlan {
  const AutoPathPlan(this.strokes);

  final List<DrawingStroke> strokes;
}

final class AutoPathPlanningCancelled implements Exception {
  const AutoPathPlanningCancelled();

  @override
  String toString() => 'Auto Path planning cancelled.';
}

@visibleForTesting
int debugAutoPathPlannerActiveWorkers = 0;

final class AutoPathPlanningOperation {
  AutoPathPlanningOperation._();

  final Completer<AutoPathPlan> _result = Completer<AutoPathPlan>();
  final Completer<void> _stopped = Completer<void>();
  final Completer<void> _workerStarted = Completer<void>();
  ReceivePort? _responses;
  Future<Isolate>? _spawnFuture;
  Isolate? _isolate;
  var _cancelled = false;
  var _workerCounted = false;
  var _released = false;

  Future<AutoPathPlan> get result => _result.future;
  Future<void> get stopped => _stopped.future;
  @visibleForTesting
  Future<void> get workerStarted => _workerStarted.future;
  @visibleForTesting
  bool get isWorkerRunning => _workerCounted && !_released;
  bool get isCancelled => _cancelled;

  void _launch(_AutoPathWorkerRequest request) {
    final responses = ReceivePort();
    _responses = responses;
    responses.listen(_receive);
    final spawning = Isolate.spawn<_AutoPathWorkerRequest>(
      _autoPathWorker,
      request.copyWith(replyTo: responses.sendPort),
      onError: responses.sendPort,
      onExit: responses.sendPort,
      errorsAreFatal: true,
      debugName: 'handdraw-auto-path-planner',
    );
    _spawnFuture = spawning;
    unawaited(
      spawning
          .then((isolate) {
            if (_released || _cancelled) {
              isolate.kill(priority: Isolate.immediate);
              return;
            }
            _isolate = isolate;
            _workerCounted = true;
            debugAutoPathPlannerActiveWorkers++;
            if (!_workerStarted.isCompleted) _workerStarted.complete();
            if (_cancelled) {
              isolate.kill(priority: Isolate.immediate);
              _release();
            }
          })
          .catchError((Object error, StackTrace stackTrace) {
            if (!_cancelled && !_result.isCompleted) {
              _result.completeError(error, stackTrace);
            }
            if (!_workerStarted.isCompleted) {
              _workerStarted.completeError(error, stackTrace);
            }
            _release();
          }),
    );
  }

  void _receive(Object? message) {
    if (_cancelled) return;
    if (message case _AutoPathWorkerSuccess(:final plan)) {
      if (!_result.isCompleted) _result.complete(plan);
      _release();
      return;
    }
    if (message case _AutoPathWorkerFailure(:final error, :final stackTrace)) {
      if (!_result.isCompleted) {
        _result.completeError(
          StateError(error),
          StackTrace.fromString(stackTrace),
        );
      }
      _release();
      return;
    }
    if (message is List && message.length >= 2) {
      if (!_result.isCompleted) {
        _result.completeError(
          StateError('${message.first}'),
          StackTrace.fromString('${message[1]}'),
        );
      }
      _release();
      return;
    }
    if (message == null && !_result.isCompleted) {
      _result.completeError(
        StateError('Auto Path planner exited before returning a result.'),
      );
      _release();
    }
  }

  Future<void> cancel() async {
    if (_cancelled) return stopped;
    _cancelled = true;
    if (!_result.isCompleted) {
      _result.completeError(const AutoPathPlanningCancelled());
    }
    final spawning = _spawnFuture;
    if (spawning != null) {
      try {
        final isolate = _isolate ?? await spawning;
        isolate.kill(priority: Isolate.immediate);
      } catch (_) {
        // Spawn failures are delivered to [result].
      }
    }
    _release();
    return stopped;
  }

  void _release() {
    if (_released) return;
    _released = true;
    _responses?.close();
    _responses = null;
    _isolate = null;
    if (_workerCounted) {
      _workerCounted = false;
      debugAutoPathPlannerActiveWorkers--;
    }
    if (!_stopped.isCompleted) _stopped.complete();
  }
}

/// Converts platform-neutral Smart Path sections into an ordered animation
/// plan. Detection stays in the Smart Path package; sequencing stays here so
/// it can be tested and reused on every Flutter platform.
class AutoPathStrokePlanner {
  const AutoPathStrokePlanner([
    this._bezierFitter = const PolylineBezierFitter(),
  ]);

  final PolylineBezierFitter _bezierFitter;

  /// Builds a potentially dense plan away from Flutter's UI isolate.
  ///
  /// Smart Path can legitimately produce thousands of precise paths for a
  /// detailed illustration. Even with the indexed ordering algorithm, fitting
  /// and sorting all of that geometry is a sizeable CPU job and must not share
  /// a frame with pointer input or painting. The synchronous [build] remains
  /// available for small deterministic callers and tests; product flows should
  /// use this method when accepting analyzed artwork.
  Future<AutoPathPlan> buildResponsive({
    required List<SmartPathSection> sections,
    required HandDrawProject project,
    List<DrawingSceneGroup> sceneGroups = const [],
    List<String> timelineSectionOrder = const [],
    bool useDirectionalWipes = false,
  }) => startResponsive(
    sections: sections,
    project: project,
    sceneGroups: sceneGroups,
    timelineSectionOrder: timelineSectionOrder,
    useDirectionalWipes: useDirectionalWipes,
  ).result;

  AutoPathPlanningOperation startResponsive({
    required List<SmartPathSection> sections,
    required HandDrawProject project,
    List<DrawingSceneGroup> sceneGroups = const [],
    List<String> timelineSectionOrder = const [],
    bool useDirectionalWipes = false,
  }) {
    // Capture only the two scalar project settings used by planning. Sending
    // the full legacy project would also copy embedded Base64 artwork and any
    // existing strokes into the worker for no reason.
    final canvasHeight = project.canvasHeight;
    final revealWidth = project.revealWidth;
    final operation = AutoPathPlanningOperation._();
    operation._launch(
      _AutoPathWorkerRequest(
        replyTo: null,
        planner: this,
        sections: sections,
        canvasHeight: canvasHeight,
        revealWidth: revealWidth,
        sceneGroups: sceneGroups,
        timelineSectionOrder: timelineSectionOrder,
        useDirectionalWipes: useDirectionalWipes,
      ),
    );
    return operation;
  }

  AutoPathPlan build({
    required List<SmartPathSection> sections,
    required HandDrawProject project,
    List<DrawingSceneGroup> sceneGroups = const [],
    List<String> timelineSectionOrder = const [],
    bool useDirectionalWipes = false,
  }) => _build(
    sections: sections,
    canvasHeight: project.canvasHeight,
    revealWidth: project.revealWidth,
    sceneGroups: sceneGroups,
    timelineSectionOrder: timelineSectionOrder,
    useDirectionalWipes: useDirectionalWipes,
  );

  AutoPathPlan _build({
    required List<SmartPathSection> sections,
    required int canvasHeight,
    required double revealWidth,
    List<DrawingSceneGroup> sceneGroups = const [],
    List<String> timelineSectionOrder = const [],
    bool useDirectionalWipes = false,
  }) {
    final unitRect = const Rect.fromLTWH(0, 0, 1, 1);
    final pending = <DrawingStroke>[];
    final explicitStages = <String, _StageKey>{};
    final rows = _buildTextRows(sections);
    final textExclusions = ImmutableRectList.freeze(
      sections
          .where(
            (section) =>
                section.kind == SmartSectionKind.text &&
                section.mode != SmartSectionMode.ignore,
          )
          .map((section) => section.bounds.inflate(0.003).intersect(unitRect)),
    );
    final decorationExclusions = ImmutableRectList.freeze(
      sections
          .where(
            (section) =>
                section.kind == SmartSectionKind.shape &&
                section.mode != SmartSectionMode.ignore &&
                _isHorizontalDecoration(section.bounds),
          )
          .map(
            (section) => section.bounds
                .inflate(math.max(0.001, section.recommendedRevealWidth * 0.5))
                .intersect(unitRect),
          ),
    );

    for (final section in sections) {
      if (section.mode == SmartSectionMode.ignore) continue;
      final coverageWidth = (section.recommendedRevealWidth * canvasHeight)
          .clamp(3.0, canvasHeight * 0.80);
      final drawingWidth = math.min(
        coverageWidth,
        math.max(12.0, revealWidth * 0.65),
      );
      final clipPadding = section.kind == SmartSectionKind.text
          ? math.min(
              0.003,
              math.max(0.001, section.recommendedRevealWidth * 0.08),
            )
          : section.recommendedRevealWidth * 0.8;
      final clip = section.bounds.inflate(clipPadding).intersect(unitRect);

      final requiresApproximateTextReveal =
          section.kind == SmartSectionKind.text &&
          !section.hasPreciseTrace &&
          _isApproximateTextCenterline(section);
      if (section.mode == SmartSectionMode.revealText ||
          requiresApproximateTextReveal) {
        pending.add(
          _stroke(
            pending,
            name: '${section.label} • Reveal',
            points: section.revealPoints,
            sectionId: section.id,
            revealOnly: true,
            revealStyle: useDirectionalWipes
                ? RevealMaskStyle.directionalWipe
                : RevealMaskStyle.brush,
            clipBounds: clip,
            exclusionBounds: decorationExclusions,
            revealWidth: math.max(
              coverageWidth,
              section.bounds.height * canvasHeight * 1.08,
            ),
          ),
        );
        continue;
      }

      final detectedPaths = section.rightToLeft
          ? section.paths.reversed
          : section.paths;
      final isHorizontalDecoration =
          section.kind == SmartSectionKind.shape &&
          _isHorizontalDecoration(section.bounds);
      final paths = (isHorizontalDecoration
          ? _distinctHorizontalDecorations(detectedPaths, section.bounds)
          : detectedPaths.toList(growable: false));
      for (var pathIndex = 0; pathIndex < paths.length; pathIndex++) {
        final path = paths[pathIndex];
        final points = section.rightToLeft
            ? path.points.reversed.toList(growable: false)
            : path.points;
        final groups = section.role == SmartSectionRole.connector
            ? [_StagedPath(points)]
            : section.kind == SmartSectionKind.shape &&
                  !_isHorizontalDecoration(section.bounds)
            ? _splitShapePath(points, rows)
            : [_StagedPath(points)];
        for (final group in groups) {
          if (group.points.length < 2) continue;
          final stroke = _stroke(
            pending,
            name: section.label,
            points: group.points,
            sectionId: section.id,
            clipBounds: isHorizontalDecoration
                ? _horizontalDecorationClip(
                    section.bounds,
                    paths,
                    pathIndex,
                    clipPadding,
                  )
                : clip,
            exclusionBounds: section.kind == SmartSectionKind.shape
                ? isHorizontalDecoration
                      ? const []
                      : textExclusions
                : decorationExclusions,
            revealWidth: drawingWidth,
            isGlobalDecoration:
                section.role == SmartSectionRole.globalDecoration,
          );
          pending.add(stroke);
          if (group.stage != null) explicitStages[stroke.id] = group.stage!;
        }
      }

      if (section.kind == SmartSectionKind.text) {
        pending.add(
          _stroke(
            pending,
            name: '${section.label} • Complete',
            points: section.revealPoints,
            sectionId: section.id,
            revealOnly: true,
            clipBounds: clip,
            exclusionBounds: decorationExclusions,
            revealWidth: math.max(
              coverageWidth,
              section.bounds.height * canvasHeight * 1.08,
            ),
          ),
        );
      }
    }

    final keys = _buildOrderKeys(pending, rows, sections, explicitStages);
    pending.sort((a, b) => keys[a.id]!.compareTo(keys[b.id]!));
    final connectorSectionIds = {
      for (final section in sections)
        if (section.role == SmartSectionRole.connector ||
            section.role == SmartSectionRole.globalDecoration)
          section.id,
    };
    final directionLockedIds = {
      ...explicitStages.keys,
      for (final stroke in pending)
        if (connectorSectionIds.contains(stroke.sectionId)) stroke.id,
    };
    final spatiallyOrdered = _connectNearbyPaths(
      pending,
      keys,
      directionLockedIds,
    );
    return AutoPathPlan(
      List.unmodifiable(
        timelineSectionOrder.isEmpty
            ? _applySceneGroups(spatiallyOrdered, sceneGroups, sections)
            : _applyTimelineOrder(
                spatiallyOrdered,
                timelineSectionOrder,
                sceneGroups,
                sections,
              ),
      ),
    );
  }

  bool _isApproximateTextCenterline(SmartPathSection section) {
    if (section.paths.length != 1 || section.paths.single.points.length != 2) {
      return false;
    }
    final actual = section.paths.single.points;
    final fallback = section.revealPoints;
    const tolerance = 0.002;
    return (actual.first - fallback.first).distance <= tolerance &&
        (actual.last - fallback.last).distance <= tolerance;
  }

  List<SmartGeneratedPath> _distinctHorizontalDecorations(
    Iterable<SmartGeneratedPath> paths,
    Rect sectionBounds,
  ) {
    final candidates = paths.where((path) => path.points.length >= 2).toList();
    if (candidates.isEmpty) return const [];

    // Skeletonization can split one thick painted line into nearby fragments,
    // but a multi-line underline is intentional artwork and every visible
    // stroke needs its own pen pass. Group only paths that share the same
    // vertical band, then retain the longest representative in each band.
    candidates.sort(
      (left, right) =>
          _verticalCenter(left.points).compareTo(_verticalCenter(right.points)),
    );
    final bandTolerance = math.max(0.0035, sectionBounds.height * 0.18);
    final bands = <List<SmartGeneratedPath>>[];
    for (final candidate in candidates) {
      if (bands.isEmpty ||
          (_verticalCenter(candidate.points) -
                      _verticalCenter(bands.last.first.points))
                  .abs() >
              bandTolerance) {
        bands.add([candidate]);
      } else {
        bands.last.add(candidate);
      }
    }

    return [
      for (final band in bands)
        _leftToRight(
          band.reduce((best, candidate) {
            final bestSpan = _horizontalSpan(best.points);
            final candidateSpan = _horizontalSpan(candidate.points);
            if (candidateSpan != bestSpan) {
              return candidateSpan > bestSpan ? candidate : best;
            }
            return candidate.points.length > best.points.length
                ? candidate
                : best;
          }),
        ),
    ];
  }

  SmartGeneratedPath _leftToRight(SmartGeneratedPath path) {
    if (path.points.first.dx <= path.points.last.dx) return path;
    return SmartGeneratedPath(
      points: path.points.reversed.toList(growable: false),
    );
  }

  Rect _horizontalDecorationClip(
    Rect sectionBounds,
    List<SmartGeneratedPath> paths,
    int index,
    double padding,
  ) {
    if (paths.length <= 1) {
      return sectionBounds
          .inflate(padding)
          .intersect(const Rect.fromLTWH(0, 0, 1, 1));
    }
    final center = _verticalCenter(paths[index].points);
    final top = index == 0
        ? sectionBounds.top - padding
        : (_verticalCenter(paths[index - 1].points) + center) * 0.5;
    final bottom = index == paths.length - 1
        ? sectionBounds.bottom + padding
        : (center + _verticalCenter(paths[index + 1].points)) * 0.5;
    return Rect.fromLTRB(
      sectionBounds.left - padding,
      top,
      sectionBounds.right + padding,
      bottom,
    ).intersect(const Rect.fromLTWH(0, 0, 1, 1));
  }

  double _verticalCenter(List<Offset> points) {
    var top = points.first.dy;
    var bottom = top;
    for (final point in points.skip(1)) {
      top = math.min(top, point.dy);
      bottom = math.max(bottom, point.dy);
    }
    return (top + bottom) * 0.5;
  }

  double _horizontalSpan(List<Offset> points) {
    var left = points.first.dx;
    var right = left;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      right = math.max(right, point.dx);
    }
    return right - left;
  }

  List<DrawingStroke> _applyTimelineOrder(
    List<DrawingStroke> spatiallyOrdered,
    List<String> timelineSectionOrder,
    List<DrawingSceneGroup> sceneGroups,
    List<SmartPathSection> sections,
  ) {
    final globalIds = {
      for (final section in sections)
        if (section.role == SmartSectionRole.globalDecoration) section.id,
    };
    final groupBySection = <String, String>{};
    for (final group in sceneGroups) {
      for (final sectionId in group.sectionIds) {
        if (!globalIds.contains(sectionId)) {
          groupBySection[sectionId] = group.id;
        }
      }
    }
    final tagged = [
      for (final stroke in spatiallyOrdered)
        stroke.copyWith(sceneGroupId: groupBySection[stroke.sectionId]),
    ];
    final blocks = <String, List<DrawingStroke>>{};
    for (final stroke in tagged) {
      final id = stroke.sectionId;
      if (id != null) blocks.putIfAbsent(id, () => []).add(stroke);
    }
    final ordered = <DrawingStroke>[];
    final inserted = <String>{};
    for (final sectionId in timelineSectionOrder) {
      if (globalIds.contains(sectionId)) continue;
      for (final stroke in blocks[sectionId] ?? const <DrawingStroke>[]) {
        if (inserted.add(stroke.id)) ordered.add(stroke);
      }
    }
    // Preserve unknown/legacy content and keep global decorations last.
    for (final stroke in tagged) {
      if (!stroke.isGlobalDecoration && inserted.add(stroke.id)) {
        ordered.add(stroke);
      }
    }
    for (final stroke in tagged) {
      if (inserted.add(stroke.id)) ordered.add(stroke);
    }
    return ordered;
  }

  List<DrawingStroke> _applySceneGroups(
    List<DrawingStroke> spatiallyOrdered,
    List<DrawingSceneGroup> sceneGroups,
    List<SmartPathSection> sections,
  ) {
    if (sceneGroups.isEmpty) return spatiallyOrdered;
    final roleBySection = {
      for (final section in sections) section.id: section.role,
    };
    final groupBySection = <String, String>{};
    for (final group in sceneGroups) {
      for (final sectionId in group.sectionIds) {
        if (roleBySection[sectionId] == SmartSectionRole.globalDecoration) {
          continue;
        }
        groupBySection[sectionId] = group.id;
      }
    }
    final tagged = [
      for (final stroke in spatiallyOrdered)
        stroke.copyWith(sceneGroupId: groupBySection[stroke.sectionId]),
    ];
    final ordered = <DrawingStroke>[];
    final inserted = <String>{};
    for (final group in sceneGroups) {
      final members = tagged
          .where((stroke) => stroke.sceneGroupId == group.id)
          .toList(growable: false);
      for (final stroke in _optimizeSceneMembers(members, roleBySection)) {
        if (inserted.add(stroke.id)) ordered.add(stroke);
      }
    }
    for (final stroke in tagged) {
      if (inserted.add(stroke.id)) ordered.add(stroke);
    }
    return ordered;
  }

  List<DrawingStroke> _optimizeSceneMembers(
    List<DrawingStroke> members,
    Map<String, SmartSectionRole> roleBySection,
  ) {
    if (members.length < 2) return members;
    final blocks = <String, List<DrawingStroke>>{};
    for (final stroke in members) {
      final key = stroke.sectionId ?? stroke.id;
      blocks.putIfAbsent(key, () => <DrawingStroke>[]).add(stroke);
    }
    final content = blocks.entries
        .where(
          (entry) => roleBySection[entry.key] != SmartSectionRole.connector,
        )
        .map((entry) => entry.value)
        .toList();
    final connectors = blocks.entries
        .where(
          (entry) => roleBySection[entry.key] == SmartSectionRole.connector,
        )
        .expand((entry) => entry.value)
        .toList(growable: false);
    if (content.length < 2) {
      return [...content.expand((block) => block), ...connectors];
    }

    final orderedBlocks = <List<DrawingStroke>>[content.removeAt(0)];
    while (content.isNotEmpty) {
      final previous = orderedBlocks.last.last.orderedPoints.last;
      var bestIndex = 0;
      var bestDistance = double.infinity;
      for (var index = 0; index < content.length; index++) {
        final distance =
            (content[index].first.orderedPoints.first - previous).distance;
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = index;
        }
      }
      orderedBlocks.add(content.removeAt(bestIndex));
    }
    return [...orderedBlocks.expand((block) => block), ...connectors];
  }

  DrawingStroke _stroke(
    List<DrawingStroke> pending, {
    required String name,
    required List<Offset> points,
    required String sectionId,
    bool revealOnly = false,
    RevealMaskStyle revealStyle = RevealMaskStyle.brush,
    Rect? clipBounds,
    List<Rect> exclusionBounds = const [],
    double? revealWidth,
    bool isGlobalDecoration = false,
  }) {
    return DrawingStroke(
      id: 'auto-${DateTime.now().microsecondsSinceEpoch}-${pending.length}',
      name: name,
      points: points,
      geometry: _bezierFitter.fit(points),
      revealOnly: revealOnly,
      revealStyle: revealStyle,
      sectionId: sectionId,
      clipBounds: clipBounds,
      exclusionBounds: exclusionBounds,
      revealWidth: revealWidth,
      isGlobalDecoration: isGlobalDecoration,
    );
  }

  List<_TextRow> _buildTextRows(List<SmartPathSection> sections) {
    final textSections =
        sections
            .where(
              (section) =>
                  section.kind == SmartSectionKind.text &&
                  section.mode != SmartSectionMode.ignore,
            )
            .toList()
          ..sort((a, b) {
            final vertical = a.bounds.center.dy.compareTo(b.bounds.center.dy);
            return vertical != 0
                ? vertical
                : a.bounds.center.dx.compareTo(b.bounds.center.dx);
          });
    final rows = <_TextRow>[];
    for (final section in textSections) {
      final index = rows.indexWhere(
        (row) => (row.centerY - section.bounds.center.dy).abs() <= 0.055,
      );
      if (index < 0) {
        rows.add(_TextRow([section]));
      } else {
        rows[index].sections.add(section);
      }
    }
    rows.sort((a, b) => a.centerY.compareTo(b.centerY));
    for (final row in rows) {
      row.sections.sort(
        (a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx),
      );
    }
    return rows;
  }

  List<_StagedPath> _splitShapePath(List<Offset> points, List<_TextRow> rows) {
    if (points.length < 2 || rows.isEmpty) return [_StagedPath(points)];
    final segments = <_StagedPath>[];
    var current = <Offset>[points.first];
    var currentKey = _stageForPoint(points.first, rows);
    for (final point in points.skip(1)) {
      final key = _stageForPoint(point, rows);
      if (key == currentKey) {
        current.add(point);
        continue;
      }

      // The new-stage point must not leak into the previous reveal. Start the
      // next segment at the last old-stage point so the geometry remains
      // continuous while its pixels stay hidden until the next stage begins.
      final boundary = current.last;
      if (current.length >= 2) {
        segments.add(_StagedPath(current, currentKey));
      }
      current = <Offset>[boundary, point];
      currentKey = key;
    }
    if (current.length >= 2) {
      segments.add(_StagedPath(current, currentKey));
    }
    return segments.isEmpty ? [_StagedPath(points)] : segments;
  }

  _StageKey _stageForPoint(Offset point, List<_TextRow> rows) {
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      var closestObject = -1;
      var closestDistance = double.infinity;
      for (
        var objectIndex = 0;
        objectIndex < row.sections.length;
        objectIndex++
      ) {
        final bounds = row.sections[objectIndex].bounds;
        // Keep enough room around the glyphs to associate a surrounding card
        // with its text. The bottom edge is intentionally tight: outgoing
        // connectors normally start there, and a symmetric 0.028 padding made
        // their first visible pixels appear before the card was complete.
        final objectArea = Rect.fromLTRB(
          bounds.left - 0.03,
          bounds.top - 0.028,
          bounds.right + 0.03,
          bounds.bottom + 0.003,
        );
        if (objectArea.contains(point)) {
          final delta = point - bounds.center;
          final distance = delta.dx * delta.dx + delta.dy * delta.dy;
          if (distance < closestDistance) {
            closestDistance = distance;
            closestObject = objectIndex;
          }
        }
      }
      if (closestObject >= 0) {
        return _StageKey(rowIndex * 2, closestObject);
      }
    }
    var insertion = rows.indexWhere((row) => point.dy < row.centerY);
    if (insertion < 0) insertion = rows.length;
    if (insertion == 0) return const _StageKey(0, 0);
    final previousRow = rows[insertion - 1];
    var closestObject = 0;
    var closestDistance = double.infinity;
    for (var index = 0; index < previousRow.sections.length; index++) {
      final distance = (previousRow.sections[index].bounds.center.dx - point.dx)
          .abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        closestObject = index;
      }
    }
    return _StageKey(insertion * 2 - 1, closestObject);
  }

  Map<String, _OrderKey> _buildOrderKeys(
    List<DrawingStroke> strokes,
    List<_TextRow> rows,
    List<SmartPathSection> sections,
    Map<String, _StageKey> explicitStages,
  ) {
    final textSections = rows
        .expand((row) => row.sections)
        .toList(growable: false);
    final sectionsById = {for (final section in sections) section.id: section};
    final keys = <String, _OrderKey>{};
    for (final stroke in strokes) {
      final bounds = _strokeBounds(stroke);
      final sectionIndex = textSections.indexWhere(
        (section) => section.id == stroke.sectionId,
      );
      if (sectionIndex >= 0) {
        final section = textSections[sectionIndex];
        final rowIndex = rows.indexWhere(
          (row) => row.sections.any((item) => item.id == section.id),
        );
        final objectIndex = rows[rowIndex].sections.indexWhere(
          (item) => item.id == section.id,
        );
        final orderStage = _StageKey(rowIndex * 2, objectIndex);
        keys[stroke.id] = _OrderKey(
          stage: orderStage.stage,
          object: orderStage.object,
          phase: stroke.revealOnly ? 2 : 1,
          primary: section.rightToLeft ? -bounds.right : bounds.left,
          secondary: bounds.top,
        );
        continue;
      }

      final parentBounds = sectionsById[stroke.sectionId]?.bounds;
      final parentSection = sectionsById[stroke.sectionId];
      if (parentSection?.role == SmartSectionRole.globalDecoration) {
        keys[stroke.id] = _OrderKey(
          stage: rows.length * 2 + 2,
          object: 0,
          phase: 0,
          primary: sections.indexOf(parentSection!).toDouble(),
          secondary: 0,
        );
        continue;
      }
      if (parentSection?.role == SmartSectionRole.connector) {
        final stage = _stageForConnector(parentSection!, rows);
        final points = stroke.orderedPoints;
        keys[stroke.id] = _OrderKey(
          stage: stage.stage,
          object: stage.object,
          phase: 0,
          primary: points.isEmpty ? bounds.left : points.first.dx,
          secondary: points.isEmpty ? bounds.right : points.last.dx,
        );
        continue;
      }
      final schedulingBounds =
          parentBounds != null && _isHorizontalDecoration(parentBounds)
          ? parentBounds
          : bounds;
      final stage =
          explicitStages[stroke.id] ??
          _stageForShapeBounds(schedulingBounds, rows);
      keys[stroke.id] = _OrderKey(
        stage: stage.stage,
        object: stage.object,
        phase: 0,
        primary: schedulingBounds.center.dy,
        secondary: schedulingBounds.center.dx,
      );
    }
    return keys;
  }

  _StageKey _stageForConnector(SmartPathSection section, List<_TextRow> rows) {
    if (rows.isEmpty) return const _StageKey(0, 0);
    final points = section.paths.expand((path) => path.points).toList();
    final source = points.isEmpty ? section.bounds.topCenter : points.first;
    var sourceRow = 0;
    for (var index = 0; index < rows.length; index++) {
      if (rows[index].centerY <= source.dy + 0.025) sourceRow = index;
    }
    var sourceObject = 0;
    var closestDistance = double.infinity;
    for (var index = 0; index < rows[sourceRow].sections.length; index++) {
      final distance =
          (rows[sourceRow].sections[index].bounds.center.dx - source.dx).abs();
      if (distance < closestDistance) {
        closestDistance = distance;
        sourceObject = index;
      }
    }
    // Connectors are causal transitions: finish the source row, then draw the
    // whole edge before any labels or content belonging to the target row.
    return _StageKey(sourceRow * 2 + 1, sourceObject);
  }

  _StageKey _stageForShapeBounds(Rect bounds, List<_TextRow> rows) {
    // OCR bounds hug the glyphs, while a card border sits farther out. The
    // general object padding therefore has to be generous. A short outgoing
    // connector can fall inside that padding as well, which used to reveal a
    // remote blue/black tick before the card itself was finished. Identify
    // those narrow strokes from their geometry and schedule them in the gap
    // after the complete row.
    if (_isHorizontalDecoration(bounds)) {
      for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
        final row = rows[rowIndex];
        final rowTop = row.sections
            .map((section) => section.bounds.top)
            .reduce(math.min);
        final rowBottom = row.sections
            .map((section) => section.bounds.bottom)
            .reduce(math.max);
        final rowHeight = math.max(0.001, rowBottom - rowTop);
        final nextCenter = rowIndex + 1 < rows.length
            ? rows[rowIndex + 1].centerY
            : 1.0;
        // Native SVG text bounds include font descent and can extend several
        // pixels below the visible glyphs. Accept the lower quarter of those
        // bounds as the underline zone so SVG and raster artwork keep the same
        // reading order: title, underline, then the following text row.
        final underlineThreshold = math.min(
          rowBottom - 0.004,
          row.centerY + rowHeight * 0.25,
        );
        final sitsBelowText = bounds.center.dy >= underlineThreshold;
        final precedesNextRow = bounds.center.dy < nextCenter;
        if (sitsBelowText && precedesNextRow) {
          return _StageKey(rowIndex * 2 + 1, 0);
        }
      }
    }
    if (bounds.height >= 0.006 &&
        bounds.width <= math.max(0.012, bounds.height * 0.55)) {
      for (var rowIndex = 0; rowIndex < rows.length - 1; rowIndex++) {
        final row = rows[rowIndex];
        for (
          var objectIndex = 0;
          objectIndex < row.sections.length;
          objectIndex++
        ) {
          final section = row.sections[objectIndex];
          final horizontallyAligned =
              bounds.center.dx >= section.bounds.left - 0.025 &&
              bounds.center.dx <= section.bounds.right + 0.025;
          final startsBelowGlyphs =
              bounds.center.dy >= section.bounds.bottom + 0.004;
          final pointsTowardNextRow =
              bounds.center.dy < rows[rowIndex + 1].centerY;
          if (horizontallyAligned && startsBelowGlyphs && pointsTowardNextRow) {
            return _StageKey(rowIndex * 2 + 1, objectIndex);
          }
        }
      }
    }
    return _stageForPoint(bounds.center, rows);
  }

  bool _isHorizontalDecoration(Rect bounds) =>
      bounds.width >= 0.05 &&
      bounds.height <= math.max(0.025, bounds.width * 0.16);

  List<DrawingStroke> _connectNearbyPaths(
    List<DrawingStroke> sorted,
    Map<String, _OrderKey> keys,
    Set<String> directionLockedIds,
  ) {
    final result = <DrawingStroke>[];
    var cursor = 0;
    while (cursor < sorted.length) {
      final key = keys[sorted[cursor].id]!;
      var end = cursor + 1;
      while (end < sorted.length && key.sameGroup(keys[sorted[end].id]!)) {
        end++;
      }
      final group = sorted.sublist(cursor, end);
      result.addAll(
        key.phase == 0
            ? _nearestNeighborOrder(
                group,
                allowReverse: !group.any(
                  (stroke) => directionLockedIds.contains(stroke.id),
                ),
              )
            : group,
      );
      cursor = end;
    }
    return result;
  }

  List<DrawingStroke> _nearestNeighborOrder(
    List<DrawingStroke> source, {
    bool allowReverse = true,
  }) {
    if (source.length < 2) return source;
    if (source.length >= 96) {
      return _nearestNeighborOrderIndexed(source, allowReverse: allowReverse);
    }
    return _nearestNeighborOrderLinear(source, allowReverse: allowReverse);
  }

  List<DrawingStroke> _nearestNeighborOrderLinear(
    List<DrawingStroke> source, {
    required bool allowReverse,
  }) {
    final remaining = List<DrawingStroke>.of(source);
    final ordered = <DrawingStroke>[remaining.removeAt(0)];
    while (remaining.isNotEmpty) {
      final end = ordered.last.orderedPoints.last;
      var bestIndex = 0;
      var reverse = false;
      var bestDistance = double.infinity;
      for (var index = 0; index < remaining.length; index++) {
        final candidate = remaining[index];
        final startDistance = (candidate.orderedPoints.first - end).distance;
        final endDistance = allowReverse
            ? (candidate.orderedPoints.last - end).distance
            : double.infinity;
        final distance = math.min(startDistance, endDistance);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestIndex = index;
          reverse = endDistance < startDistance;
        }
      }
      final next = remaining.removeAt(bestIndex);
      ordered.add(reverse ? next.copyWith(reversed: !next.reversed) : next);
    }
    return ordered;
  }

  List<DrawingStroke> _nearestNeighborOrderIndexed(
    List<DrawingStroke> source, {
    required bool allowReverse,
  }) {
    final index = _NearestEndpointIndex(source, allowReverse: allowReverse)
      ..removeStroke(0);
    final ordered = <DrawingStroke>[source.first];
    while (!index.isEmpty) {
      final match = index.nearest(ordered.last.orderedPoints.last);
      final next = source[match.strokeIndex];
      ordered.add(
        match.reverse ? next.copyWith(reversed: !next.reversed) : next,
      );
      index.removeStroke(match.strokeIndex);
    }
    return ordered;
  }

  Rect _strokeBounds(DrawingStroke stroke) {
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
}

final class _AutoPathWorkerRequest {
  const _AutoPathWorkerRequest({
    required this.replyTo,
    required this.planner,
    required this.sections,
    required this.canvasHeight,
    required this.revealWidth,
    required this.sceneGroups,
    required this.timelineSectionOrder,
    required this.useDirectionalWipes,
  });

  final SendPort? replyTo;
  final AutoPathStrokePlanner planner;
  final List<SmartPathSection> sections;
  final int canvasHeight;
  final double revealWidth;
  final List<DrawingSceneGroup> sceneGroups;
  final List<String> timelineSectionOrder;
  final bool useDirectionalWipes;

  _AutoPathWorkerRequest copyWith({required SendPort replyTo}) =>
      _AutoPathWorkerRequest(
        replyTo: replyTo,
        planner: planner,
        sections: sections,
        canvasHeight: canvasHeight,
        revealWidth: revealWidth,
        sceneGroups: sceneGroups,
        timelineSectionOrder: timelineSectionOrder,
        useDirectionalWipes: useDirectionalWipes,
      );
}

final class _AutoPathWorkerSuccess {
  const _AutoPathWorkerSuccess(this.plan);
  final AutoPathPlan plan;
}

final class _AutoPathWorkerFailure {
  const _AutoPathWorkerFailure(this.error, this.stackTrace);
  final String error;
  final String stackTrace;
}

void _autoPathWorker(_AutoPathWorkerRequest request) {
  try {
    final plan = request.planner._build(
      sections: request.sections,
      canvasHeight: request.canvasHeight,
      revealWidth: request.revealWidth,
      sceneGroups: request.sceneGroups,
      timelineSectionOrder: request.timelineSectionOrder,
      useDirectionalWipes: request.useDirectionalWipes,
    );
    Isolate.exit(request.replyTo!, _AutoPathWorkerSuccess(plan));
  } catch (error, stackTrace) {
    Isolate.exit(
      request.replyTo!,
      _AutoPathWorkerFailure('$error', '$stackTrace'),
    );
  }
}

/// Dynamic exact nearest-neighbour index for dense Auto Path groups.
///
/// The original linear walk is retained for small groups. At large counts this
/// balanced k-d tree returns the same closest start/end point and preserves the
/// original source-order tie break, while removing both endpoints atomically
/// after a stroke is chosen.
final class _NearestEndpointIndex {
  _NearestEndpointIndex(
    List<DrawingStroke> strokes, {
    required bool allowReverse,
  }) : _strokeCount = strokes.length {
    final endpoints = <_StrokeEndpoint>[];
    for (var index = 0; index < strokes.length; index++) {
      final points = strokes[index].orderedPoints;
      endpoints.add(
        _StrokeEndpoint(
          point: points.first,
          strokeIndex: index,
          reverse: false,
        ),
      );
      if (allowReverse) {
        endpoints.add(
          _StrokeEndpoint(
            point: points.last,
            strokeIndex: index,
            reverse: true,
          ),
        );
      }
    }
    _root = _build(endpoints, 0, null);
  }

  final int _strokeCount;
  final Map<int, List<_EndpointNode>> _nodesByStroke = {};
  late final _EndpointNode? _root;
  var _removedStrokeCount = 0;

  bool get isEmpty => _removedStrokeCount >= _strokeCount;

  void removeStroke(int strokeIndex) {
    final nodes = _nodesByStroke[strokeIndex];
    if (nodes == null || nodes.every((node) => !node.active)) return;
    _removedStrokeCount++;
    for (final node in nodes) {
      if (!node.active) continue;
      node.active = false;
      _EndpointNode? current = node;
      while (current != null) {
        current.activeCount--;
        current = current.parent;
      }
    }
  }

  _EndpointMatch nearest(Offset target) {
    _EndpointMatch? best;
    var bestDistanceSquared = double.infinity;

    void search(_EndpointNode? node) {
      if (node == null || node.activeCount == 0) return;
      final delta = node.axis == 0
          ? target.dx - node.endpoint.point.dx
          : target.dy - node.endpoint.point.dy;
      final near = delta < 0 ? node.left : node.right;
      final far = delta < 0 ? node.right : node.left;
      search(near);

      if (node.active) {
        final offset = node.endpoint.point - target;
        final distanceSquared = offset.dx * offset.dx + offset.dy * offset.dy;
        final candidate = _EndpointMatch(
          strokeIndex: node.endpoint.strokeIndex,
          reverse: node.endpoint.reverse,
        );
        if (_isBetterEndpoint(
          candidate,
          distanceSquared,
          best,
          bestDistanceSquared,
        )) {
          best = candidate;
          bestDistanceSquared = distanceSquared;
        }
      }

      if (delta * delta <= bestDistanceSquared) search(far);
    }

    search(_root);
    return best!;
  }

  _EndpointNode? _build(
    List<_StrokeEndpoint> endpoints,
    int depth,
    _EndpointNode? parent,
  ) {
    if (endpoints.isEmpty) return null;
    final axis = depth & 1;
    endpoints.sort((left, right) {
      final primary = axis == 0
          ? left.point.dx.compareTo(right.point.dx)
          : left.point.dy.compareTo(right.point.dy);
      if (primary != 0) return primary;
      final secondary = axis == 0
          ? left.point.dy.compareTo(right.point.dy)
          : left.point.dx.compareTo(right.point.dx);
      if (secondary != 0) return secondary;
      final stroke = left.strokeIndex.compareTo(right.strokeIndex);
      if (stroke != 0) return stroke;
      return left.reverse == right.reverse ? 0 : (left.reverse ? 1 : -1);
    });
    final middle = endpoints.length >> 1;
    final node = _EndpointNode(
      endpoint: endpoints[middle],
      axis: axis,
      parent: parent,
    );
    _nodesByStroke.putIfAbsent(node.endpoint.strokeIndex, () => []).add(node);
    node.left = _build(endpoints.sublist(0, middle), depth + 1, node);
    node.right = _build(endpoints.sublist(middle + 1), depth + 1, node);
    node.activeCount =
        1 + (node.left?.activeCount ?? 0) + (node.right?.activeCount ?? 0);
    return node;
  }
}

bool _isBetterEndpoint(
  _EndpointMatch candidate,
  double candidateDistanceSquared,
  _EndpointMatch? best,
  double bestDistanceSquared,
) {
  if (best == null || candidateDistanceSquared < bestDistanceSquared) {
    return true;
  }
  if (candidateDistanceSquared > bestDistanceSquared) return false;
  if (candidate.strokeIndex != best.strokeIndex) {
    return candidate.strokeIndex < best.strokeIndex;
  }
  // Equal start/end distances retain the original non-reversed direction.
  return !candidate.reverse && best.reverse;
}

final class _StrokeEndpoint {
  const _StrokeEndpoint({
    required this.point,
    required this.strokeIndex,
    required this.reverse,
  });

  final Offset point;
  final int strokeIndex;
  final bool reverse;
}

final class _EndpointNode {
  _EndpointNode({
    required this.endpoint,
    required this.axis,
    required this.parent,
  });

  final _StrokeEndpoint endpoint;
  final int axis;
  final _EndpointNode? parent;
  _EndpointNode? left;
  _EndpointNode? right;
  var active = true;
  var activeCount = 1;
}

final class _EndpointMatch {
  const _EndpointMatch({required this.strokeIndex, required this.reverse});

  final int strokeIndex;
  final bool reverse;
}

class _TextRow {
  _TextRow(this.sections);

  final List<SmartPathSection> sections;

  double get centerY =>
      sections.fold<double>(
        0,
        (sum, section) => sum + section.bounds.center.dy,
      ) /
      sections.length;
}

class _StagedPath {
  const _StagedPath(this.points, [this.stage]);

  final List<Offset> points;
  final _StageKey? stage;
}

class _StageKey {
  const _StageKey(this.stage, this.object);

  final int stage;
  final int object;

  @override
  bool operator ==(Object other) =>
      other is _StageKey && stage == other.stage && object == other.object;

  @override
  int get hashCode => Object.hash(stage, object);
}

class _OrderKey {
  const _OrderKey({
    required this.stage,
    required this.object,
    required this.phase,
    required this.primary,
    required this.secondary,
  });

  final int stage;
  final int object;
  final int phase;
  final double primary;
  final double secondary;

  bool sameGroup(_OrderKey other) =>
      stage == other.stage && object == other.object && phase == other.phase;

  int compareTo(_OrderKey other) {
    var result = stage.compareTo(other.stage);
    if (result != 0) return result;
    result = object.compareTo(other.object);
    if (result != 0) return result;
    result = phase.compareTo(other.phase);
    if (result != 0) return result;
    result = primary.compareTo(other.primary);
    if (result != 0) return result;
    return secondary.compareTo(other.secondary);
  }
}
