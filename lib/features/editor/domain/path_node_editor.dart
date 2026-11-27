import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

enum PathNodeKind {
  startAnchor,
  endAnchor,
  quadraticControl,
  control1,
  control2,
}

class PathNodeReference {
  const PathNodeReference({required this.kind, this.segmentIndex = -1});

  final PathNodeKind kind;
  final int segmentIndex;

  @override
  bool operator ==(Object other) =>
      other is PathNodeReference &&
      other.kind == kind &&
      other.segmentIndex == segmentIndex;

  @override
  int get hashCode => Object.hash(kind, segmentIndex);
}

class PathNodePosition {
  const PathNodePosition({required this.reference, required this.position});

  final PathNodeReference reference;
  final Offset position;
}

/// Pure immutable editing operations for vector path nodes.
class PathNodeEditor {
  const PathNodeEditor();

  List<PathNodePosition> nodes(StrokePathGeometry geometry) {
    final result = <PathNodePosition>[
      PathNodePosition(
        reference: const PathNodeReference(kind: PathNodeKind.startAnchor),
        position: geometry.start,
      ),
    ];
    for (var index = 0; index < geometry.segments.length; index++) {
      final segment = geometry.segments[index];
      if (segment case StrokeQuadraticSegment(:final control)) {
        result.add(
          PathNodePosition(
            reference: PathNodeReference(
              kind: PathNodeKind.quadraticControl,
              segmentIndex: index,
            ),
            position: control,
          ),
        );
      }
      if (segment case StrokeCubicSegment(:final control1, :final control2)) {
        result.addAll([
          PathNodePosition(
            reference: PathNodeReference(
              kind: PathNodeKind.control1,
              segmentIndex: index,
            ),
            position: control1,
          ),
          PathNodePosition(
            reference: PathNodeReference(
              kind: PathNodeKind.control2,
              segmentIndex: index,
            ),
            position: control2,
          ),
        ]);
      }
      result.add(
        PathNodePosition(
          reference: PathNodeReference(
            kind: PathNodeKind.endAnchor,
            segmentIndex: index,
          ),
          position: segment.end,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  StrokePathGeometry move(
    StrokePathGeometry geometry,
    PathNodeReference reference,
    Offset destination,
  ) {
    if (!destination.dx.isFinite || !destination.dy.isFinite) return geometry;
    final segments = List<StrokePathSegment>.of(geometry.segments);
    switch (reference.kind) {
      case PathNodeKind.startAnchor:
        final delta = destination - geometry.start;
        if (segments.isNotEmpty) {
          final first = segments.first;
          segments[0] = switch (first) {
            StrokeLineSegment() => first,
            StrokeQuadraticSegment(:final control, :final end) =>
              StrokeQuadraticSegment(control: control + delta, end: end),
            StrokeCubicSegment(:final control1, :final control2, :final end) =>
              StrokeCubicSegment(
                control1: control1 + delta,
                control2: control2,
                end: end,
              ),
          };
        }
        if (geometry.closed && segments.isNotEmpty) {
          final last = segments.last;
          segments[segments.length - 1] = switch (last) {
            StrokeLineSegment() => last,
            StrokeQuadraticSegment(:final control, :final end) =>
              StrokeQuadraticSegment(control: control + delta, end: end),
            StrokeCubicSegment(:final control1, :final control2, :final end) =>
              StrokeCubicSegment(
                control1: control1,
                control2: control2 + delta,
                end: end,
              ),
          };
        }
        return StrokePathGeometry(
          start: destination,
          segments: segments,
          closed: geometry.closed,
          smoothAnchors: geometry.smoothAnchors,
        );

      case PathNodeKind.endAnchor:
        final index = reference.segmentIndex;
        if (index < 0 || index >= segments.length) return geometry;
        final current = segments[index];
        final delta = destination - current.end;
        segments[index] = switch (current) {
          StrokeLineSegment() => StrokeLineSegment(end: destination),
          StrokeQuadraticSegment(:final control) => StrokeQuadraticSegment(
            control: control + delta,
            end: destination,
          ),
          StrokeCubicSegment(:final control1, :final control2) =>
            StrokeCubicSegment(
              control1: control1,
              control2: control2 + delta,
              end: destination,
            ),
        };
        if (index + 1 < segments.length) {
          final next = segments[index + 1];
          segments[index + 1] = switch (next) {
            StrokeLineSegment() => next,
            StrokeQuadraticSegment(:final control, :final end) =>
              StrokeQuadraticSegment(control: control + delta, end: end),
            StrokeCubicSegment(:final control1, :final control2, :final end) =>
              StrokeCubicSegment(
                control1: control1 + delta,
                control2: control2,
                end: end,
              ),
          };
        }
        return StrokePathGeometry(
          start: geometry.start,
          segments: segments,
          closed: geometry.closed,
          smoothAnchors: geometry.smoothAnchors,
        );

      case PathNodeKind.quadraticControl:
        final index = reference.segmentIndex;
        if (index < 0 || index >= segments.length) return geometry;
        final current = segments[index];
        if (current is! StrokeQuadraticSegment) return geometry;
        segments[index] = StrokeQuadraticSegment(
          control: destination,
          end: current.end,
        );
        return StrokePathGeometry(
          start: geometry.start,
          segments: segments,
          closed: geometry.closed,
          smoothAnchors: geometry.smoothAnchors,
        );

      case PathNodeKind.control1:
      case PathNodeKind.control2:
        final index = reference.segmentIndex;
        if (index < 0 || index >= segments.length) return geometry;
        final current = segments[index];
        if (current is! StrokeCubicSegment) return geometry;
        segments[index] = StrokeCubicSegment(
          control1: reference.kind == PathNodeKind.control1
              ? destination
              : current.control1,
          control2: reference.kind == PathNodeKind.control2
              ? destination
              : current.control2,
          end: current.end,
        );
        _preserveSmoothTangent(
          geometry,
          segments,
          movedKind: reference.kind,
          segmentIndex: index,
          destination: destination,
        );
        return StrokePathGeometry(
          start: geometry.start,
          segments: segments,
          closed: geometry.closed,
          smoothAnchors: geometry.smoothAnchors,
        );
    }
  }

  StrokePathGeometry splitSegment(
    StrokePathGeometry geometry,
    int segmentIndex, {
    double progress = 0.5,
  }) {
    if (segmentIndex < 0 || segmentIndex >= geometry.segments.length) {
      return geometry;
    }
    final t = progress.clamp(0.01, 0.99);
    final start = _segmentStart(geometry, segmentIndex);
    final segment = geometry.segments[segmentIndex];
    final split = switch (segment) {
      StrokeLineSegment(:final end) => <StrokePathSegment>[
        StrokeLineSegment(end: Offset.lerp(start, end, t)!),
        StrokeLineSegment(end: end),
      ],
      StrokeQuadraticSegment(:final control, :final end) => () {
        final firstControl = Offset.lerp(start, control, t)!;
        final secondControl = Offset.lerp(control, end, t)!;
        final midpoint = Offset.lerp(firstControl, secondControl, t)!;
        return <StrokePathSegment>[
          StrokeQuadraticSegment(control: firstControl, end: midpoint),
          StrokeQuadraticSegment(control: secondControl, end: end),
        ];
      }(),
      StrokeCubicSegment(:final control1, :final control2, :final end) => () {
        final a = Offset.lerp(start, control1, t)!;
        final b = Offset.lerp(control1, control2, t)!;
        final c = Offset.lerp(control2, end, t)!;
        final d = Offset.lerp(a, b, t)!;
        final e = Offset.lerp(b, c, t)!;
        final midpoint = Offset.lerp(d, e, t)!;
        return <StrokePathSegment>[
          StrokeCubicSegment(control1: a, control2: d, end: midpoint),
          StrokeCubicSegment(control1: e, control2: c, end: end),
        ];
      }(),
    };
    final segments = List<StrokePathSegment>.of(geometry.segments)
      ..replaceRange(segmentIndex, segmentIndex + 1, split);
    final insertedAnchor = segmentIndex + 1;
    return StrokePathGeometry(
      start: geometry.start,
      segments: segments,
      closed: geometry.closed,
      smoothAnchors: {
        for (final anchor in geometry.smoothAnchors)
          anchor > insertedAnchor ? anchor + 1 : anchor,
        if (segment is! StrokeLineSegment) insertedAnchor,
      }.toList(),
    );
  }

  StrokePathGeometry deleteAnchor(
    StrokePathGeometry geometry,
    PathNodeReference reference,
  ) {
    if (geometry.segments.length <= 1) return geometry;
    if (reference.kind == PathNodeKind.startAnchor) {
      final removed = geometry.segments.first;
      return StrokePathGeometry(
        start: removed.end,
        segments: geometry.segments.skip(1).toList(),
        closed: false,
        smoothAnchors: [
          for (final anchor in geometry.smoothAnchors)
            if (anchor > 0) anchor - 1,
        ],
      );
    }
    if (reference.kind != PathNodeKind.endAnchor) return geometry;
    final index = reference.segmentIndex;
    if (index < 0 || index >= geometry.segments.length) return geometry;
    final segments = List<StrokePathSegment>.of(geometry.segments);
    if (index == segments.length - 1) {
      segments.removeLast();
    } else {
      final current = segments[index];
      final next = segments[index + 1];
      segments[index] = _joinAcrossAnchor(current, next);
      segments.removeAt(index + 1);
    }
    final removedAnchor = index + 1;
    return StrokePathGeometry(
      start: geometry.start,
      segments: segments,
      closed: geometry.closed && segments.length > 1,
      smoothAnchors: [
        for (final anchor in geometry.smoothAnchors)
          if (anchor != removedAnchor)
            anchor > removedAnchor ? anchor - 1 : anchor,
      ],
    );
  }

  StrokePathGeometry setAnchorSmooth(
    StrokePathGeometry geometry,
    PathNodeReference reference, {
    required bool smooth,
  }) {
    final anchorIndex = _anchorIndex(reference);
    if (anchorIndex == null || anchorIndex > geometry.segments.length) {
      return geometry;
    }
    final smoothAnchors = geometry.smoothAnchors.toSet();
    if (!smooth) {
      smoothAnchors.remove(anchorIndex);
      return StrokePathGeometry(
        start: geometry.start,
        segments: geometry.segments,
        closed: geometry.closed,
        smoothAnchors: smoothAnchors.toList(),
      );
    }
    smoothAnchors.add(anchorIndex);
    final segments = List<StrokePathSegment>.of(geometry.segments);
    final anchor = anchorIndex == 0
        ? geometry.start
        : segments[anchorIndex - 1].end;
    final incomingIndex = anchorIndex - 1;
    final outgoingIndex = anchorIndex;
    final incoming = incomingIndex >= 0
        ? _incomingControl(segments[incomingIndex])
        : null;
    final outgoing = outgoingIndex < segments.length
        ? _outgoingControl(segments[outgoingIndex])
        : null;
    var direction = outgoing == null ? null : outgoing - anchor;
    if (direction == null || direction.distance <= 0.000001) {
      direction = incoming == null ? const Offset(1, 0) : anchor - incoming;
    }
    direction = direction / math.max(0.000001, direction.distance);
    if (incomingIndex >= 0 && incoming != null) {
      segments[incomingIndex] = _replaceIncomingControl(
        segments[incomingIndex],
        anchor - direction * (anchor - incoming).distance,
      );
    }
    if (outgoingIndex < segments.length && outgoing != null) {
      segments[outgoingIndex] = _replaceOutgoingControl(
        segments[outgoingIndex],
        anchor + direction * (outgoing - anchor).distance,
      );
    }
    return StrokePathGeometry(
      start: geometry.start,
      segments: segments,
      closed: geometry.closed,
      smoothAnchors: smoothAnchors.toList(),
    );
  }

  List<StrokePathGeometry> splitPath(
    StrokePathGeometry geometry,
    int anchorIndex,
  ) {
    if (geometry.closed ||
        anchorIndex <= 0 ||
        anchorIndex >= geometry.segments.length) {
      return [geometry];
    }
    final firstSegments = geometry.segments.take(anchorIndex).toList();
    final secondSegments = geometry.segments.skip(anchorIndex).toList();
    final secondStart = firstSegments.last.end;
    return [
      StrokePathGeometry(
        start: geometry.start,
        segments: firstSegments,
        smoothAnchors: [
          for (final anchor in geometry.smoothAnchors)
            if (anchor <= anchorIndex) anchor,
        ],
      ),
      StrokePathGeometry(
        start: secondStart,
        segments: secondSegments,
        smoothAnchors: [
          for (final anchor in geometry.smoothAnchors)
            if (anchor >= anchorIndex) anchor - anchorIndex,
        ],
      ),
    ];
  }

  StrokePathGeometry joinPaths(
    StrokePathGeometry first,
    StrokePathGeometry second,
  ) {
    final bridgeRequired = (first.end - second.start).distance > 0.000001;
    final offset = first.segments.length + (bridgeRequired ? 1 : 0);
    return StrokePathGeometry(
      start: first.start,
      segments: [
        ...first.segments,
        if (bridgeRequired) StrokeLineSegment(end: second.start),
        ...second.segments,
      ],
      smoothAnchors: [
        ...first.smoothAnchors,
        for (final anchor in second.smoothAnchors) anchor + offset,
      ],
    );
  }

  StrokePathGeometry setStartAnchor(
    StrokePathGeometry geometry,
    int anchorIndex,
  ) {
    if (!geometry.closed || geometry.segments.isEmpty) return geometry;
    final hasExplicitClosure =
        (geometry.segments.last.end - geometry.start).distance <= 0.000001;
    final segments = <StrokePathSegment>[
      ...geometry.segments,
      if (!hasExplicitClosure) StrokeLineSegment(end: geometry.start),
    ];
    if (anchorIndex <= 0 || anchorIndex >= segments.length) return geometry;
    final newStart = segments[anchorIndex - 1].end;
    final rotated = [
      ...segments.skip(anchorIndex),
      ...segments.take(anchorIndex),
    ];
    return StrokePathGeometry(
      start: newStart,
      segments: rotated,
      closed: true,
      smoothAnchors: [
        for (final anchor in geometry.smoothAnchors)
          ((anchor - anchorIndex) % segments.length + segments.length) %
              segments.length,
      ],
    );
  }

  Offset _segmentStart(StrokePathGeometry geometry, int segmentIndex) =>
      segmentIndex == 0
      ? geometry.start
      : geometry.segments[segmentIndex - 1].end;

  int? _anchorIndex(PathNodeReference reference) => switch (reference.kind) {
    PathNodeKind.startAnchor => 0,
    PathNodeKind.endAnchor => reference.segmentIndex + 1,
    _ => null,
  };

  Offset? _incomingControl(StrokePathSegment segment) => switch (segment) {
    StrokeLineSegment() => null,
    StrokeQuadraticSegment(:final control) => control,
    StrokeCubicSegment(:final control2) => control2,
  };

  Offset? _outgoingControl(StrokePathSegment segment) => switch (segment) {
    StrokeLineSegment() => null,
    StrokeQuadraticSegment(:final control) => control,
    StrokeCubicSegment(:final control1) => control1,
  };

  StrokePathSegment _replaceIncomingControl(
    StrokePathSegment segment,
    Offset control,
  ) => switch (segment) {
    StrokeLineSegment() => segment,
    StrokeQuadraticSegment(:final end) => StrokeQuadraticSegment(
      control: control,
      end: end,
    ),
    StrokeCubicSegment(:final control1, :final end) => StrokeCubicSegment(
      control1: control1,
      control2: control,
      end: end,
    ),
  };

  StrokePathSegment _replaceOutgoingControl(
    StrokePathSegment segment,
    Offset control,
  ) => switch (segment) {
    StrokeLineSegment() => segment,
    StrokeQuadraticSegment(:final end) => StrokeQuadraticSegment(
      control: control,
      end: end,
    ),
    StrokeCubicSegment(:final control2, :final end) => StrokeCubicSegment(
      control1: control,
      control2: control2,
      end: end,
    ),
  };

  StrokePathSegment _joinAcrossAnchor(
    StrokePathSegment incoming,
    StrokePathSegment outgoing,
  ) {
    if (incoming is StrokeCubicSegment || outgoing is StrokeCubicSegment) {
      return StrokeCubicSegment(
        control1: _outgoingControl(incoming) ?? incoming.end,
        control2: _incomingControl(outgoing) ?? incoming.end,
        end: outgoing.end,
      );
    }
    if (incoming is StrokeQuadraticSegment ||
        outgoing is StrokeQuadraticSegment) {
      return StrokeQuadraticSegment(
        control:
            _outgoingControl(incoming) ??
            _incomingControl(outgoing) ??
            incoming.end,
        end: outgoing.end,
      );
    }
    return StrokeLineSegment(end: outgoing.end);
  }

  void _preserveSmoothTangent(
    StrokePathGeometry geometry,
    List<StrokePathSegment> segments, {
    required PathNodeKind movedKind,
    required int segmentIndex,
    required Offset destination,
  }) {
    if (segments.isEmpty) return;
    final rawAnchorIndex = movedKind == PathNodeKind.control1
        ? segmentIndex
        : segmentIndex + 1;
    final anchorIndex = geometry.closed && rawAnchorIndex == segments.length
        ? 0
        : rawAnchorIndex;
    if (!geometry.smoothAnchors.contains(anchorIndex)) return;
    final anchor = anchorIndex == 0
        ? geometry.start
        : segments[anchorIndex - 1].end;
    final movedVector = destination - anchor;
    if (movedVector.distance <= 0.000001) return;
    final direction = movedVector / movedVector.distance;

    if (movedKind == PathNodeKind.control1) {
      final incomingIndex = segmentIndex > 0
          ? segmentIndex - 1
          : geometry.closed
          ? segments.length - 1
          : null;
      if (incomingIndex == null) return;
      final opposite = _incomingControl(segments[incomingIndex]);
      if (opposite == null) return;
      segments[incomingIndex] = _replaceIncomingControl(
        segments[incomingIndex],
        anchor - direction * (anchor - opposite).distance,
      );
      return;
    }

    final outgoingIndex = segmentIndex + 1 < segments.length
        ? segmentIndex + 1
        : geometry.closed
        ? 0
        : null;
    if (outgoingIndex == null) return;
    final opposite = _outgoingControl(segments[outgoingIndex]);
    if (opposite == null) return;
    segments[outgoingIndex] = _replaceOutgoingControl(
      segments[outgoingIndex],
      anchor - direction * (opposite - anchor).distance,
    );
  }
}
