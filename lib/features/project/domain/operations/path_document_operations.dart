import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_support.dart';

enum DocumentPathNodeKind {
  startAnchor,
  endAnchor,
  quadraticControl,
  control1,
  control2,
}

final class DocumentPathNodeReference {
  const DocumentPathNodeReference({required this.kind, this.segmentIndex = -1});

  final DocumentPathNodeKind kind;
  final int segmentIndex;
}

/// Commits path-node edits as document transactions. Pointer movement stays
/// outside the operation layer; one final destination produces one result.
final class PathDocumentOperations {
  const PathDocumentOperations();

  DocumentOperationResult addNode({
    required ProjectDocument document,
    required StrokeId strokeId,
    required int segmentIndex,
    double progress = 0.5,
  }) => _geometry(document, strokeId, 'add-path-node', (geometry) {
    if (segmentIndex < 0 || segmentIndex >= geometry.segments.length) {
      return null;
    }
    final t = progress.clamp(0.01, 0.99);
    final start = segmentIndex == 0
        ? geometry.start
        : geometry.segments[segmentIndex - 1].end;
    final segment = geometry.segments[segmentIndex];
    final split = switch (segment) {
      StrokeLineSegment(:final end) => <StrokePathSegment>[
        StrokeLineSegment(end: Offset.lerp(start, end, t)!),
        StrokeLineSegment(end: end),
      ],
      StrokeQuadraticSegment(:final control, :final end) => () {
        final a = Offset.lerp(start, control, t)!;
        final b = Offset.lerp(control, end, t)!;
        final midpoint = Offset.lerp(a, b, t)!;
        return <StrokePathSegment>[
          StrokeQuadraticSegment(control: a, end: midpoint),
          StrokeQuadraticSegment(control: b, end: end),
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
    return StrokePathGeometry(
      start: geometry.start,
      segments: segments,
      closed: geometry.closed,
      smoothAnchors: [
        for (final anchor in geometry.smoothAnchors)
          anchor > segmentIndex + 1 ? anchor + 1 : anchor,
        if (segment is! StrokeLineSegment) segmentIndex + 1,
      ],
    );
  });

  DocumentOperationResult deleteNode({
    required ProjectDocument document,
    required StrokeId strokeId,
    required DocumentPathNodeReference node,
  }) => _geometry(document, strokeId, 'delete-path-node', (geometry) {
    if (geometry.segments.length <= 1) return null;
    if (node.kind == DocumentPathNodeKind.startAnchor) {
      return StrokePathGeometry(
        start: geometry.segments.first.end,
        segments: geometry.segments.skip(1).toList(),
        smoothAnchors: [
          for (final anchor in geometry.smoothAnchors)
            if (anchor > 0) anchor - 1,
        ],
      );
    }
    if (node.kind != DocumentPathNodeKind.endAnchor ||
        node.segmentIndex < 0 ||
        node.segmentIndex >= geometry.segments.length) {
      return null;
    }
    final segments = List<StrokePathSegment>.of(geometry.segments);
    if (node.segmentIndex == segments.length - 1) {
      segments.removeLast();
    } else {
      final incoming = segments[node.segmentIndex];
      final outgoing = segments[node.segmentIndex + 1];
      segments[node.segmentIndex] = _join(incoming, outgoing);
      segments.removeAt(node.segmentIndex + 1);
    }
    final removedAnchor = node.segmentIndex + 1;
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
  });

  DocumentOperationResult moveNode({
    required ProjectDocument document,
    required StrokeId strokeId,
    required DocumentPathNodeReference node,
    required DocumentPoint destination,
  }) {
    if (!destination.x.isFinite || !destination.y.isFinite) {
      return invalid(document, 'A path-node destination must be finite.');
    }
    return _geometry(document, strokeId, 'move-path-node', (geometry) {
      final target = Offset(destination.x, destination.y);
      final segments = List<StrokePathSegment>.of(geometry.segments);
      if (node.kind == DocumentPathNodeKind.startAnchor) {
        final delta = target - geometry.start;
        if (segments.isNotEmpty) {
          segments[0] = _shiftOutgoingControl(segments.first, delta);
          if (geometry.closed) {
            segments[segments.length - 1] = _shiftIncomingControl(
              segments.last,
              delta,
            );
          }
        }
        return StrokePathGeometry(
          start: target,
          segments: segments,
          closed: geometry.closed,
          smoothAnchors: geometry.smoothAnchors,
        );
      }
      final index = node.segmentIndex;
      if (index < 0 || index >= segments.length) return null;
      final segment = segments[index];
      if (node.kind == DocumentPathNodeKind.endAnchor) {
        final delta = target - segment.end;
        segments[index] = _moveEndAnchor(segment, target, delta);
        if (index + 1 < segments.length) {
          segments[index + 1] = _shiftOutgoingControl(
            segments[index + 1],
            delta,
          );
        }
        return StrokePathGeometry(
          start: geometry.start,
          segments: segments,
          closed: geometry.closed,
          smoothAnchors: geometry.smoothAnchors,
        );
      }
      segments[index] = switch ((node.kind, segment)) {
        (
          DocumentPathNodeKind.quadraticControl,
          StrokeQuadraticSegment(:final end),
        ) =>
          StrokeQuadraticSegment(control: target, end: end),
        (
          DocumentPathNodeKind.control1,
          StrokeCubicSegment(:final control2, :final end),
        ) =>
          StrokeCubicSegment(control1: target, control2: control2, end: end),
        (
          DocumentPathNodeKind.control2,
          StrokeCubicSegment(:final control1, :final end),
        ) =>
          StrokeCubicSegment(control1: control1, control2: target, end: end),
        _ => segment,
      };
      return StrokePathGeometry(
        start: geometry.start,
        segments: segments,
        closed: geometry.closed,
        smoothAnchors: geometry.smoothAnchors,
      );
    });
  }

  DocumentOperationResult setNodeSmooth({
    required ProjectDocument document,
    required StrokeId strokeId,
    required int anchorIndex,
    required bool smooth,
  }) => _geometry(
    document,
    strokeId,
    smooth ? 'smooth-path-node' : 'corner-path-node',
    (geometry) {
      if (anchorIndex < 0 || anchorIndex > geometry.segments.length) {
        return null;
      }
      final anchors = geometry.smoothAnchors.toSet();
      if (!smooth) {
        anchors.remove(anchorIndex);
        return StrokePathGeometry(
          start: geometry.start,
          segments: geometry.segments,
          closed: geometry.closed,
          smoothAnchors: anchors.toList(),
        );
      }
      anchors.add(anchorIndex);
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
        smoothAnchors: anchors.toList(),
      );
    },
  );

  DocumentOperationResult splitPath({
    required ProjectDocument document,
    required StrokeId strokeId,
    required int anchorIndex,
    required IdAllocationContext ids,
  }) {
    final stroke = strokeById(document, strokeId);
    if (stroke == null) return missing(document, 'Stroke', strokeId);
    final geometry = stroke.geometry;
    if (geometry == null ||
        geometry.closed ||
        anchorIndex <= 0 ||
        anchorIndex >= geometry.segments.length) {
      return invalid(document, 'The selected anchor cannot split this path.');
    }
    final section = sectionById(document, stroke.sectionId);
    if (section == null) return missing(document, 'Section', stroke.sectionId);

    final firstSegments = geometry.segments.take(anchorIndex).toList();
    final secondSegments = geometry.segments.skip(anchorIndex).toList();
    final first = StrokePathGeometry(
      start: geometry.start,
      segments: firstSegments,
      smoothAnchors: [
        for (final anchor in geometry.smoothAnchors)
          if (anchor <= anchorIndex) anchor,
      ],
    );
    final second = StrokePathGeometry(
      start: firstSegments.last.end,
      segments: secondSegments,
      smoothAnchors: [
        for (final anchor in geometry.smoothAnchors)
          if (anchor >= anchorIndex) anchor - anchorIndex,
      ],
    );
    final splitId = ids.strokeId();
    final splitStroke = stroke.copyWith(
      id: splitId,
      name: '${stroke.name} 2',
      geometry: second,
      animationGeometry: null,
      isFilledShape: false,
      points: _points(second),
      pausePoints: const [],
    );
    final strokeIndex = document.strokes.indexWhere(
      (item) => item.id == strokeId,
    );
    final sectionIndex = section.strokeIds.indexOf(strokeId);
    final strokes = List<ProjectStroke>.of(document.strokes)
      ..replaceRange(strokeIndex, strokeIndex + 1, [
        stroke.copyWith(
          geometry: first,
          animationGeometry: null,
          isFilledShape: false,
          points: _points(first),
        ),
        splitStroke,
      ]);
    final sectionStrokeIds = List<StrokeId>.of(section.strokeIds)
      ..insert(sectionIndex + 1, splitId);
    return DocumentOperationResult.success(
      document: document.copyWith(
        strokes: strokes,
        sections: [
          for (final item in document.sections)
            item.id == section.id
                ? item.copyWith(strokeIds: sectionStrokeIds)
                : item,
        ],
      ),
      affectedScopes: const {
        DocumentScope.paths,
        DocumentScope.strokes,
        DocumentScope.sections,
      },
      summary: DocumentChangeSummary(
        action: 'split-path',
        entityIds: [strokeId.value, splitId.value],
      ),
    );
  }

  DocumentOperationResult setStartNode({
    required ProjectDocument document,
    required StrokeId strokeId,
    required int anchorIndex,
  }) => _geometry(document, strokeId, 'set-start-node', (geometry) {
    if (!geometry.closed || geometry.segments.isEmpty) {
      return null;
    }
    final hasExplicitClosure =
        (geometry.segments.last.end - geometry.start).distance <= 0.000001;
    final segments = <StrokePathSegment>[
      ...geometry.segments,
      if (!hasExplicitClosure) StrokeLineSegment(end: geometry.start),
    ];
    if (anchorIndex <= 0 || anchorIndex >= segments.length) return null;
    final start = segments[anchorIndex - 1].end;
    return StrokePathGeometry(
      start: start,
      segments: [...segments.skip(anchorIndex), ...segments.take(anchorIndex)],
      closed: true,
      smoothAnchors: [
        for (final anchor in geometry.smoothAnchors)
          ((anchor - anchorIndex) % segments.length + segments.length) %
              segments.length,
      ],
    );
  });

  DocumentOperationResult joinWithNext({
    required ProjectDocument document,
    required StrokeId strokeId,
    required StrokeId nextStrokeId,
  }) {
    final first = strokeById(document, strokeId);
    final second = strokeById(document, nextStrokeId);
    if (first == null) return missing(document, 'Stroke', strokeId);
    if (second == null) return missing(document, 'Stroke', nextStrokeId);
    if (first.sectionId != second.sectionId ||
        first.geometry == null ||
        second.geometry == null) {
      return invalid(
        document,
        'Joined paths must share a section and geometry.',
      );
    }
    final bridge =
        (first.geometry!.end - second.geometry!.start).distance > 0.000001;
    final joined = StrokePathGeometry(
      start: first.geometry!.start,
      segments: [
        ...first.geometry!.segments,
        if (bridge) StrokeLineSegment(end: second.geometry!.start),
        ...second.geometry!.segments,
      ],
      smoothAnchors: [
        ...first.geometry!.smoothAnchors,
        for (final anchor in second.geometry!.smoothAnchors)
          anchor + first.geometry!.segments.length + (bridge ? 1 : 0),
      ],
    );
    final section = sectionById(document, first.sectionId)!;
    return DocumentOperationResult.success(
      document: document.copyWith(
        strokes: [
          for (final stroke in document.strokes)
            if (stroke.id == strokeId)
              stroke.copyWith(geometry: joined, points: _points(joined))
            else if (stroke.id != nextStrokeId)
              stroke,
        ],
        sections: [
          for (final item in document.sections)
            item.id == section.id
                ? item.copyWith(
                    strokeIds: item.strokeIds
                        .where((id) => id != nextStrokeId)
                        .toList(),
                  )
                : item,
        ],
      ),
      affectedScopes: const {
        DocumentScope.paths,
        DocumentScope.strokes,
        DocumentScope.sections,
      },
      summary: DocumentChangeSummary(
        action: 'join-paths',
        entityIds: [strokeId.value, nextStrokeId.value],
      ),
    );
  }

  DocumentOperationResult _geometry(
    ProjectDocument document,
    StrokeId id,
    String action,
    StrokePathGeometry? Function(StrokePathGeometry) transform,
  ) {
    final stroke = strokeById(document, id);
    if (stroke == null) return missing(document, 'Stroke', id);
    final geometry = stroke.geometry;
    if (geometry == null) {
      return invalid(document, 'Stroke $id has no editable geometry.');
    }
    final changed = transform(geometry);
    if (changed == null) {
      return invalid(document, 'The requested path node is invalid.');
    }
    return DocumentOperationResult.success(
      document: document.copyWith(
        strokes: [
          for (final item in document.strokes)
            item.id == id
                ? item.copyWith(geometry: changed, points: _points(changed))
                : item,
        ],
      ),
      affectedScopes: const {DocumentScope.paths, DocumentScope.strokes},
      summary: DocumentChangeSummary(action: action, entityIds: [id.value]),
    );
  }

  static StrokePathSegment _join(
    StrokePathSegment incoming,
    StrokePathSegment outgoing,
  ) {
    if (incoming is StrokeCubicSegment || outgoing is StrokeCubicSegment) {
      final control1 = switch (incoming) {
        StrokeCubicSegment(:final control2) => control2,
        StrokeQuadraticSegment(:final control) => control,
        StrokeLineSegment() => incoming.end,
      };
      final control2 = switch (outgoing) {
        StrokeCubicSegment(:final control1) => control1,
        StrokeQuadraticSegment(:final control) => control,
        StrokeLineSegment() => incoming.end,
      };
      return StrokeCubicSegment(
        control1: control1,
        control2: control2,
        end: outgoing.end,
      );
    }
    if (incoming is StrokeQuadraticSegment ||
        outgoing is StrokeQuadraticSegment) {
      final control = incoming is StrokeQuadraticSegment
          ? incoming.control
          : outgoing is StrokeQuadraticSegment
          ? outgoing.control
          : incoming.end;
      return StrokeQuadraticSegment(control: control, end: outgoing.end);
    }
    return StrokeLineSegment(end: outgoing.end);
  }

  static List<DocumentPoint> _points(StrokePathGeometry geometry) => [
    for (final point in geometry.sample()) DocumentPoint(point.dx, point.dy),
  ];

  static StrokePathSegment _moveEndAnchor(
    StrokePathSegment segment,
    Offset destination,
    Offset delta,
  ) => switch (segment) {
    StrokeLineSegment() => StrokeLineSegment(end: destination),
    StrokeQuadraticSegment(:final control) => StrokeQuadraticSegment(
      control: control + delta,
      end: destination,
    ),
    StrokeCubicSegment(:final control1, :final control2) => StrokeCubicSegment(
      control1: control1,
      control2: control2 + delta,
      end: destination,
    ),
  };

  static StrokePathSegment _shiftOutgoingControl(
    StrokePathSegment segment,
    Offset delta,
  ) => switch (segment) {
    StrokeLineSegment() => segment,
    StrokeQuadraticSegment(:final control, :final end) =>
      StrokeQuadraticSegment(control: control + delta, end: end),
    StrokeCubicSegment(:final control1, :final control2, :final end) =>
      StrokeCubicSegment(
        control1: control1 + delta,
        control2: control2,
        end: end,
      ),
  };

  static StrokePathSegment _shiftIncomingControl(
    StrokePathSegment segment,
    Offset delta,
  ) => switch (segment) {
    StrokeLineSegment() => segment,
    StrokeQuadraticSegment(:final control, :final end) =>
      StrokeQuadraticSegment(control: control + delta, end: end),
    StrokeCubicSegment(:final control1, :final control2, :final end) =>
      StrokeCubicSegment(
        control1: control1,
        control2: control2 + delta,
        end: end,
      ),
  };

  static Offset? _incomingControl(StrokePathSegment segment) =>
      switch (segment) {
        StrokeLineSegment() => null,
        StrokeQuadraticSegment(:final control) => control,
        StrokeCubicSegment(:final control2) => control2,
      };

  static Offset? _outgoingControl(StrokePathSegment segment) =>
      switch (segment) {
        StrokeLineSegment() => null,
        StrokeQuadraticSegment(:final control) => control,
        StrokeCubicSegment(:final control1) => control1,
      };

  static StrokePathSegment _replaceIncomingControl(
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

  static StrokePathSegment _replaceOutgoingControl(
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
}
