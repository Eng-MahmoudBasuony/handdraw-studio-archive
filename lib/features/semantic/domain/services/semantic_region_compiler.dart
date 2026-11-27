import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

/// Deterministic, side-effect-free compiler. It never reads playback, selection,
/// UI, camera, or decoded runtime resources.
final class SemanticRegionCompiler {
  const SemanticRegionCompiler();

  String dependencyKey(ProjectDocument document) {
    final buffer = StringBuffer()
      ..write('canvas:${document.canvas.width}x${document.canvas.height};')
      ..write('locale:${document.contentMetadata.projectLocaleHint ?? ''};')
      ..write(
        'hand:${document.handConfiguration.assetId?.value}:${document.handConfiguration.presetId}:${document.handConfiguration.scale}:${document.handConfiguration.rotationDegrees}:${document.handConfiguration.flipX}:${document.handConfiguration.penTip.x},${document.handConfiguration.penTip.y};',
      );
    for (final asset in [
      ...document.assets,
    ]..sort((a, b) => a.id.value.compareTo(b.id.value))) {
      buffer.write(
        'asset:${asset.id.value}:${asset.kind.name}:${asset.artworkSourceType?.name}:${asset.contentHash};',
      );
    }
    for (final sectionId in document.sectionOrder) {
      buffer.write('order:${sectionId.value};');
    }
    for (final stroke in [
      ...document.strokes,
    ]..sort((a, b) => a.id.value.compareTo(b.id.value))) {
      buffer
        ..write(
          'stroke:${stroke.id.value}:${stroke.sectionId.value}:${stroke.hidden}:${stroke.revealWidth};',
        )
        ..writeAll(stroke.points.map((point) => '${point.x},${point.y};'));
    }
    for (final section in [
      ...document.sections,
    ]..sort((a, b) => a.id.value.compareTo(b.id.value))) {
      buffer
        ..write('section:${section.id.value};')
        ..writeAll(section.strokeIds.map((id) => '${id.value},'))
        ..write(
          'timing:${section.timing.animationDuration?.microseconds}:${section.timing.pauseBefore.microseconds}:${section.timing.pauseAfter.microseconds}:${section.timing.transitionAfter.microseconds}:${section.timing.speedMultiplier};',
        );
    }
    for (final scene in [
      ...document.scenes,
    ]..sort((a, b) => a.id.value.compareTo(b.id.value))) {
      buffer
        ..write('scene:${scene.id.value};')
        ..writeAll(scene.sectionIds.map((id) => '${id.value},'));
    }
    for (final entity in [
      ...document.contentMetadata.entities,
    ]..sort((a, b) => a.target.stableKey.compareTo(b.target.stableKey))) {
      final text = entity.textMetadata;
      buffer.write(
        'meta:${entity.target.stableKey}:${entity.contentRole?.name}:${entity.importance.name}:${entity.keepTogether}:${entity.cameraExcluded}:${entity.textSensitive}:${entity.minimumPreferredZoom?.value}:${text?.originalText}:${text?.direction.name}:${text?.directionProvenance.name}:${text?.languageHint}:${text?.fontSize}:${text?.lineCount}:${text?.sourceKind.name}:${text?.sourceProvenance};',
      );
    }
    if (document.artworkPlacement case final placement?) {
      final rect = placement.destination;
      buffer.write(
        'artwork:${rect.left}:${rect.top}:${rect.right}:${rect.bottom}:${placement.mode.name};',
      );
    }
    return _fnv1a64(buffer.toString());
  }

  CompiledSemanticRegionGraph compile(ProjectDocument document) {
    final metadata = {
      for (final item in document.contentMetadata.entities)
        item.target.stableKey: item,
    };
    final regions = <SemanticRegion>[];
    final byId = <String, SemanticRegion>{};
    final containment = <SemanticContainmentEdge>[];
    final ordering = <SemanticOrderingEdge>[];
    final strokeById = {
      for (final stroke in document.strokes) stroke.id: stroke,
    };

    for (final stroke in document.strokes) {
      final bounds = _strokeBounds(stroke, document);
      if (bounds == null) continue;
      final target = SemanticTargetReference.stroke(stroke.id);
      final item = metadata[target.stableKey];
      final direction = _resolveDirection(
        item?.textMetadata,
        document.contentMetadata.projectLocaleHint,
      );
      final trustedText =
          item?.textMetadata != null &&
          const {
            TextSourceKind.nativeText,
            TextSourceKind.svgText,
            TextSourceKind.importerSupplied,
            TextSourceKind.userDeclared,
          }.contains(item!.textMetadata!.sourceKind);
      final region = SemanticRegion(
        id: target.stableKey,
        target: target,
        kind: trustedText ? SemanticRegionKind.text : SemanticRegionKind.vector,
        geometricBounds: bounds,
        visualBounds: bounds.inflate(
          (stroke.revealWidth ?? document.motionConfiguration.revealWidth) / 2,
        ),
        direction: direction.direction,
        directionProvenance: direction.provenance,
        metadata: item,
      );
      regions.add(region);
      byId[region.id] = region;
    }

    final orderedSections = [
      ...document.sectionOrder
          .map(
            (id) =>
                document.sections.where((value) => value.id == id).firstOrNull,
          )
          .whereType<ProjectSection>(),
      ...document.sections.where(
        (value) => !document.sectionOrder.contains(value.id),
      ),
    ];
    String? previousDrawingRegion;
    for (final section in orderedSections) {
      final children = section.strokeIds
          .map((id) => byId['stroke:${id.value}'])
          .whereType<SemanticRegion>()
          .toList();
      final bounds = _union(children.map((value) => value.geometricBounds));
      if (bounds == null) continue;
      final target = SemanticTargetReference.section(section.id);
      final region = SemanticRegion(
        id: target.stableKey,
        target: target,
        kind: SemanticRegionKind.strokeGroup,
        geometricBounds: bounds,
        visualBounds: _union(children.map((value) => value.visualBounds))!,
        direction: KnownTextDirection.unknown,
        directionProvenance: DirectionProvenance.unknown,
        metadata: metadata[target.stableKey],
      );
      regions.add(region);
      byId[region.id] = region;
      for (final child in children) {
        containment.add(SemanticContainmentEdge(region.id, child.id));
        if (previousDrawingRegion != null) {
          ordering.add(SemanticOrderingEdge(previousDrawingRegion, child.id));
        }
        previousDrawingRegion = child.id;
      }
    }

    for (final scene in document.scenes) {
      final children = scene.sectionIds
          .map((id) => byId['section:${id.value}'])
          .whereType<SemanticRegion>()
          .toList();
      final bounds = _union(children.map((value) => value.geometricBounds));
      if (bounds == null) continue;
      final target = SemanticTargetReference.scene(scene.id);
      final region = SemanticRegion(
        id: target.stableKey,
        target: target,
        kind: SemanticRegionKind.scene,
        geometricBounds: bounds,
        visualBounds: _union(children.map((value) => value.visualBounds))!,
        direction: KnownTextDirection.unknown,
        directionProvenance: DirectionProvenance.unknown,
        metadata: metadata[target.stableKey],
      );
      regions.add(region);
      byId[region.id] = region;
      for (final child in children) {
        containment.add(SemanticContainmentEdge(region.id, child.id));
      }
    }

    final artwork = document.assets
        .where(
          (asset) =>
              asset.id == document.artworkAssetId &&
              asset.artworkSourceType == ArtworkSourceType.raster,
        )
        .firstOrNull;
    if (artwork != null) {
      final target = SemanticTargetReference.asset(artwork.id);
      final bounds = SemanticWorldBounds(
        0,
        0,
        document.canvas.width.toDouble(),
        document.canvas.height.toDouble(),
      );
      regions.add(
        SemanticRegion(
          id: target.stableKey,
          target: target,
          kind: SemanticRegionKind.raster,
          geometricBounds: bounds,
          visualBounds: bounds,
          direction: KnownTextDirection.unknown,
          directionProvenance: DirectionProvenance.unknown,
          metadata: metadata[target.stableKey],
        ),
      );
    }

    regions.sort((a, b) => a.id.compareTo(b.id));
    final adjacency = _adjacency(
      regions
          .where(
            (value) =>
                value.kind != SemanticRegionKind.scene &&
                value.kind != SemanticRegionKind.strokeGroup,
          )
          .toList(),
    );
    return CompiledSemanticRegionGraph(
      dependencyKey: dependencyKey(document),
      worldWidth: document.canvas.width.toDouble(),
      worldHeight: document.canvas.height.toDouble(),
      regions: regions,
      containment: containment,
      drawingOrder: ordering,
      adjacency: adjacency,
      attentionEvents: _attentionEvents(
        document,
        orderedSections,
        byId,
        strokeById,
      ),
      handFootprint: _handFootprint(document),
    );
  }
}

final class SemanticRegionGraphCache {
  SemanticRegionGraphCache({this.compiler = const SemanticRegionCompiler()});
  final SemanticRegionCompiler compiler;
  final Map<String, CompiledSemanticRegionGraph> _values = {};
  int compilationCount = 0;
  CompiledSemanticRegionGraph compile(ProjectDocument document) {
    final key = compiler.dependencyKey(document);
    return compileWithDependencyKey(document, key);
  }

  /// Separates dependency traversal from the O(1) cache lookup so callers
  /// that already own a revision/key can avoid proving validity twice.
  CompiledSemanticRegionGraph compileWithDependencyKey(
    ProjectDocument document,
    String dependencyKey,
  ) {
    return _values[dependencyKey] ??= (() {
      compilationCount++;
      return compiler.compile(document);
    })();
  }

  CompiledSemanticRegionGraph? lookup(String dependencyKey) =>
      _values[dependencyKey];

  void clear() => _values.clear();
}

SemanticWorldBounds? _strokeBounds(
  ProjectStroke stroke,
  ProjectDocument document,
) {
  final points = stroke.points;
  if (points.isEmpty || stroke.hidden) return null;
  var left = double.infinity,
      top = double.infinity,
      right = -double.infinity,
      bottom = -double.infinity;
  for (final point in points) {
    final destination = document.artworkPlacement?.destination;
    final x = destination == null
        ? point.x * document.canvas.width
        : destination.left + point.x * (destination.right - destination.left);
    final y = destination == null
        ? point.y * document.canvas.height
        : destination.top + point.y * (destination.bottom - destination.top);
    if (!x.isFinite || !y.isFinite) continue;
    if (x < left) left = x;
    if (x > right) right = x;
    if (y < top) top = y;
    if (y > bottom) bottom = y;
  }
  if (!left.isFinite) return null;
  return SemanticWorldBounds(left, top, right, bottom);
}

SemanticWorldBounds? _union(Iterable<SemanticWorldBounds> values) {
  SemanticWorldBounds? result;
  for (final value in values) {
    result = result == null ? value : result.union(value);
  }
  return result;
}

({KnownTextDirection direction, DirectionProvenance provenance})
_resolveDirection(ImportedTextMetadata? text, String? locale) {
  if (text != null && text.direction != KnownTextDirection.unknown) {
    return (direction: text.direction, provenance: text.directionProvenance);
  }
  final known = text?.originalText;
  if (known != null) {
    final rtl = RegExp(r'[\u0590-\u08ff]').hasMatch(known);
    final ltr = RegExp(r'[A-Za-z]').hasMatch(known);
    if (rtl || ltr) {
      return (
        direction: rtl && ltr
            ? KnownTextDirection.mixed
            : rtl
            ? KnownTextDirection.rtl
            : KnownTextDirection.ltr,
        provenance: DirectionProvenance.inferredFromKnownText,
      );
    }
    if (known.trim().isNotEmpty) {
      return (
        direction: KnownTextDirection.neutral,
        provenance: DirectionProvenance.inferredFromKnownText,
      );
    }
  }
  if (locale != null) {
    return (
      direction:
          RegExp(r'^(ar|fa|he|ur)(-|$)', caseSensitive: false).hasMatch(locale)
          ? KnownTextDirection.rtl
          : KnownTextDirection.ltr,
      provenance: DirectionProvenance.projectFallback,
    );
  }
  return (
    direction: KnownTextDirection.unknown,
    provenance: DirectionProvenance.unknown,
  );
}

List<SemanticAdjacencyEdge> _adjacency(List<SemanticRegion> regions) {
  final result = <SemanticAdjacencyEdge>[];
  for (var i = 0; i < regions.length; i++) {
    SemanticRegion? nearest;
    var best = double.infinity;
    for (var j = 0; j < regions.length; j++) {
      if (i == j) continue;
      final dx =
          regions[i].geometricBounds.centerX -
          regions[j].geometricBounds.centerX;
      final dy =
          regions[i].geometricBounds.centerY -
          regions[j].geometricBounds.centerY;
      final d = dx * dx + dy * dy;
      if (d < best) {
        best = d;
        nearest = regions[j];
      }
    }
    if (nearest != null && regions[i].id.compareTo(nearest.id) < 0) {
      result.add(SemanticAdjacencyEdge(regions[i].id, nearest.id, best));
    }
  }
  return result;
}

List<SemanticAttentionEvent> _attentionEvents(
  ProjectDocument document,
  List<ProjectSection> sections,
  Map<String, SemanticRegion> byId,
  Map<StrokeId, ProjectStroke> strokeById,
) {
  final result = <SemanticAttentionEvent>[];
  var timeUs = document.timeline.leadingHold.microseconds;
  for (final section in sections) {
    timeUs += section.timing.pauseBefore.microseconds;
    final sectionRegion = byId['section:${section.id.value}'];
    final scene = document.scenes
        .where((value) => value.sectionIds.contains(section.id))
        .firstOrNull;
    if (sectionRegion != null) {
      final count = section.strokeIds.isEmpty ? 1 : section.strokeIds.length;
      final durationUs =
          section.timing.animationDuration?.microseconds ??
          document.motionConfiguration.drawingDuration.microseconds;
      for (var i = 0; i < section.strokeIds.length; i++) {
        final stroke = strokeById[section.strokeIds[i]];
        final strokeRegion = byId['stroke:${section.strokeIds[i].value}'];
        if (stroke != null && strokeRegion != null) {
          result.add(
            SemanticAttentionEvent(
              time: TimelineTime.fromMicroseconds(
                timeUs + durationUs * i ~/ count,
              ),
              regionIds: List.unmodifiable([
                strokeRegion.id,
                sectionRegion.id,
                if (scene != null) 'scene:${scene.id.value}',
              ]),
              activeBounds: strokeRegion.visualBounds,
              strokeId: stroke.id,
              sectionId: section.id,
              sceneId: scene?.id,
            ),
          );
        }
      }
      timeUs += durationUs;
    }
    timeUs +=
        section.timing.pauseAfter.microseconds +
        section.timing.transitionAfter.microseconds;
  }
  return List.unmodifiable(result);
}

HandFootprintDescriptor _handFootprint(ProjectDocument document) {
  final hand = document.handConfiguration;
  if (hand.assetId == null && hand.presetId == null) {
    return const HandFootprintDescriptor(
      provenance: HandFootprintProvenance.unknown,
    );
  }
  return HandFootprintDescriptor(
    provenance: hand.assetId != null
        ? HandFootprintProvenance.configuredAsset
        : HandFootprintProvenance.presetEstimate,
    screenScale: hand.scale,
    penTipX: hand.penTip.x,
    penTipY: hand.penTip.y,
  );
}

String _fnv1a64(String input) {
  var hash = 0xcbf29ce484222325;
  for (final value in input.codeUnits) {
    hash ^= value;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}
