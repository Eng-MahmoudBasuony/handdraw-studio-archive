import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

enum SemanticRegionKind {
  text,
  raster,
  vector,
  strokeGroup,
  scene,
  mixed,
  unknown,
}

final class SemanticWorldBounds {
  const SemanticWorldBounds(this.left, this.top, this.right, this.bottom)
    : assert(right >= left),
      assert(bottom >= top);
  final double left;
  final double top;
  final double right;
  final double bottom;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;
  bool get isEmpty => right == left || bottom == top;
  bool intersects(SemanticWorldBounds other) =>
      left < other.right &&
      right > other.left &&
      top < other.bottom &&
      bottom > other.top;
  SemanticWorldBounds union(SemanticWorldBounds other) => SemanticWorldBounds(
    left < other.left ? left : other.left,
    top < other.top ? top : other.top,
    right > other.right ? right : other.right,
    bottom > other.bottom ? bottom : other.bottom,
  );
  SemanticWorldBounds inflate(double value) => SemanticWorldBounds(
    left - value,
    top - value,
    right + value,
    bottom + value,
  );
}

final class SemanticRegion {
  const SemanticRegion({
    required this.id,
    required this.target,
    required this.kind,
    required this.geometricBounds,
    required this.visualBounds,
    required this.direction,
    required this.directionProvenance,
    required this.metadata,
  });
  final String id;
  final SemanticTargetReference target;
  final SemanticRegionKind kind;
  final SemanticWorldBounds geometricBounds;
  final SemanticWorldBounds visualBounds;
  final KnownTextDirection direction;
  final DirectionProvenance directionProvenance;
  final EntitySemanticMetadata? metadata;
}

final class SemanticContainmentEdge {
  const SemanticContainmentEdge(this.parentRegionId, this.childRegionId);
  final String parentRegionId;
  final String childRegionId;
}

final class SemanticOrderingEdge {
  const SemanticOrderingEdge(this.beforeRegionId, this.afterRegionId);
  final String beforeRegionId;
  final String afterRegionId;
}

final class SemanticAdjacencyEdge {
  const SemanticAdjacencyEdge(
    this.firstRegionId,
    this.secondRegionId,
    this.distanceSquared,
  );
  final String firstRegionId;
  final String secondRegionId;
  final double distanceSquared;
}

final class SemanticAttentionEvent {
  const SemanticAttentionEvent({
    required this.time,
    required this.regionIds,
    required this.activeBounds,
    this.strokeId,
    this.sectionId,
    this.sceneId,
  });
  final TimelineTime time;
  final List<String> regionIds;
  final SemanticWorldBounds activeBounds;
  final StrokeId? strokeId;
  final SectionId? sectionId;
  final SceneId? sceneId;
}

enum HandFootprintProvenance { configuredAsset, presetEstimate, unknown }

final class HandFootprintDescriptor {
  const HandFootprintDescriptor({
    required this.provenance,
    this.screenScale,
    this.penTipX,
    this.penTipY,
  });
  final HandFootprintProvenance provenance;
  final double? screenScale;
  final double? penTipX;
  final double? penTipY;
}

abstract interface class SemanticSpatialIndex {
  List<SemanticRegion> intersections(SemanticWorldBounds bounds);
  SemanticRegion? nearest(double x, double y);
  List<SemanticRegion> inScene(SceneId sceneId);
  List<SemanticRegion> inInterval(TimelineTime start, TimelineTime end);
  List<SemanticRegion> readingCandidates(SemanticWorldBounds bounds);
}

final class LinearSemanticSpatialIndex implements SemanticSpatialIndex {
  LinearSemanticSpatialIndex(
    List<SemanticRegion> regions,
    List<SemanticContainmentEdge> containment,
    List<SemanticAttentionEvent> attentionEvents,
  ) : _regions = List.unmodifiable(regions),
      _containment = List.unmodifiable(containment),
      _attentionEvents = List.unmodifiable(attentionEvents);
  final List<SemanticRegion> _regions;
  final List<SemanticContainmentEdge> _containment;
  final List<SemanticAttentionEvent> _attentionEvents;
  @override
  List<SemanticRegion> intersections(SemanticWorldBounds bounds) =>
      List.unmodifiable(
        _regions.where((region) => region.visualBounds.intersects(bounds)),
      );
  @override
  SemanticRegion? nearest(double x, double y) {
    SemanticRegion? result;
    var best = double.infinity;
    for (final region in _regions) {
      final dx = region.visualBounds.centerX - x;
      final dy = region.visualBounds.centerY - y;
      final distance = dx * dx + dy * dy;
      if (distance < best) {
        best = distance;
        result = region;
      }
    }
    return result;
  }

  @override
  List<SemanticRegion> inScene(SceneId sceneId) {
    final scene = 'scene:${sceneId.value}';
    final sectionIds = _containment
        .where((edge) => edge.parentRegionId == scene)
        .map((edge) => edge.childRegionId)
        .toSet();
    final childIds = _containment
        .where((edge) => sectionIds.contains(edge.parentRegionId))
        .map((edge) => edge.childRegionId)
        .toSet();
    return List.unmodifiable(
      _regions.where(
        (region) =>
            childIds.contains(region.id) ||
            sectionIds.contains(region.id) ||
            region.id == scene,
      ),
    );
  }

  @override
  List<SemanticRegion> inInterval(TimelineTime start, TimelineTime end) {
    if (end.compareTo(start) <= 0) return const [];
    final ids = _attentionEvents
        .where(
          (event) =>
              event.time.compareTo(start) >= 0 && event.time.compareTo(end) < 0,
        )
        .expand((event) => event.regionIds)
        .toSet();
    return List.unmodifiable(
      _regions.where((region) => ids.contains(region.id)),
    );
  }

  @override
  List<SemanticRegion> readingCandidates(SemanticWorldBounds bounds) {
    final result = intersections(
      bounds,
    ).where((region) => region.kind == SemanticRegionKind.text).toList();
    result.sort((a, b) {
      final vertical = a.geometricBounds.top.compareTo(b.geometricBounds.top);
      if (vertical != 0) return vertical;
      return a.direction == KnownTextDirection.rtl
          ? b.geometricBounds.left.compareTo(a.geometricBounds.left)
          : a.geometricBounds.left.compareTo(b.geometricBounds.left);
    });
    return List.unmodifiable(result);
  }
}

final class CompiledSemanticRegionGraph {
  CompiledSemanticRegionGraph({
    required this.dependencyKey,
    required this.worldWidth,
    required this.worldHeight,
    required List<SemanticRegion> regions,
    required List<SemanticContainmentEdge> containment,
    required List<SemanticOrderingEdge> drawingOrder,
    required List<SemanticAdjacencyEdge> adjacency,
    required List<SemanticAttentionEvent> attentionEvents,
    required this.handFootprint,
  }) : regions = List.unmodifiable(regions),
       containment = List.unmodifiable(containment),
       drawingOrder = List.unmodifiable(drawingOrder),
       adjacency = List.unmodifiable(adjacency),
       attentionEvents = List.unmodifiable(attentionEvents),
       spatialIndex = LinearSemanticSpatialIndex(
         regions,
         containment,
         attentionEvents,
       );
  final String dependencyKey;
  final double worldWidth;
  final double worldHeight;
  final List<SemanticRegion> regions;
  final List<SemanticContainmentEdge> containment;
  final List<SemanticOrderingEdge> drawingOrder;
  final List<SemanticAdjacencyEdge> adjacency;
  final List<SemanticAttentionEvent> attentionEvents;
  final HandFootprintDescriptor handFootprint;
  final SemanticSpatialIndex spatialIndex;
}
