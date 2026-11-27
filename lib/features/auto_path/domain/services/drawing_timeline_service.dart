import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_smart_path/handdraw_smart_path.dart';

import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

class DrawingTimelineRange {
  const DrawingTimelineRange({
    required this.sectionId,
    required this.startSeconds,
    required this.endSeconds,
    required this.isEstimate,
  });

  final String sectionId;
  final double startSeconds;
  final double endSeconds;
  final bool isEstimate;

  double get durationSeconds => math.max(0, endSeconds - startSeconds);
}

/// A top-level timeline node. Ungrouped sections contain one ID; scenes contain
/// every member and move atomically while remaining editable when expanded.
class DrawingTimelineNode {
  const DrawingTimelineNode.section(String sectionId)
    : key = 'section:$sectionId',
      scene = null,
      sectionIds = const [];

  DrawingTimelineNode.scene(DrawingSceneGroup group)
    : key = 'scene:${group.id}',
      scene = group,
      sectionIds = group.sectionIds;

  final String key;
  final DrawingSceneGroup? scene;
  final List<String> sectionIds;

  bool get isScene => scene != null;

  String get singleSectionId => key.substring('section:'.length);

  List<String> get allSectionIds =>
      isScene ? sectionIds : <String>[singleSectionId];
}

/// Pure ordering and grouping operations for the Auto Path timeline.
///
/// The service owns no Flutter state, which keeps drag/drop, Auto Arrange,
/// Preview, and export ordering independently testable.
class DrawingTimelineService {
  const DrawingTimelineService();

  List<DrawingTimelineRange> resolveRanges({
    required HandDrawProject project,
    required List<String> order,
    required List<SmartPathSection> smartSections,
  }) {
    if (project.strokes.isNotEmpty) {
      return List.unmodifiable([
        for (final span in projectTimelineSectionSpans(project))
          DrawingTimelineRange(
            sectionId: span.sectionId,
            startSeconds: span.startSeconds,
            endSeconds: span.endSeconds,
            isEstimate: false,
          ),
      ]);
    }
    if (order.isEmpty) return const [];

    final sectionsById = {
      for (final section in smartSections) section.id: section,
    };
    final weights = <double>[
      for (final id in order) _sectionWeight(sectionsById[id]),
    ];
    final totalWeight = weights.fold<double>(0, (sum, value) => sum + value);
    final duration = math.max(0.001, project.durationSeconds);
    var cursor = 0.0;
    return List.unmodifiable([
      for (var index = 0; index < order.length; index++)
        DrawingTimelineRange(
          sectionId: order[index],
          startSeconds: cursor,
          endSeconds: cursor += duration * weights[index] / totalWeight,
          isEstimate: true,
        ),
    ]);
  }

  Rect? resolveSectionBounds({
    required String sectionId,
    required List<SmartPathSection> smartSections,
    required List<DrawingStroke> strokes,
  }) {
    for (final section in smartSections) {
      if (section.id == sectionId) return section.bounds;
    }
    Rect? result;
    for (final stroke in strokes) {
      final key = stroke.sectionId ?? 'stroke:${stroke.id}';
      if (key != sectionId) continue;
      final bounds = stroke.clipBounds ?? _strokeBounds(stroke);
      if (bounds == null) continue;
      result = result == null ? bounds : result.expandToInclude(bounds);
    }
    return result;
  }

  double _sectionWeight(SmartPathSection? section) {
    if (section == null) return 1;
    var length = 0.0;
    for (final path in section.paths) {
      for (var index = 1; index < path.points.length; index++) {
        length += (path.points[index] - path.points[index - 1]).distance;
      }
    }
    return math.max(0.03, length);
  }

  Rect? _strokeBounds(DrawingStroke stroke) {
    if (stroke.points.isEmpty) return null;
    var bounds = Rect.fromPoints(stroke.points.first, stroke.points.first);
    for (final point in stroke.points.skip(1)) {
      bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
    }
    return bounds;
  }

  List<String> resolveOrder({
    required Iterable<String> availableSectionIds,
    required Iterable<String> preferredOrder,
  }) {
    final available = availableSectionIds.toSet();
    final seen = <String>{};
    return List.unmodifiable([
      for (final id in preferredOrder)
        if (available.contains(id) && seen.add(id)) id,
      for (final id in availableSectionIds)
        if (seen.add(id)) id,
    ]);
  }

  List<DrawingSceneGroup> sanitizeGroups({
    required Iterable<DrawingSceneGroup> groups,
    required Iterable<String> availableSectionIds,
  }) {
    final available = availableSectionIds.toSet();
    final claimed = <String>{};
    return List.unmodifiable([
      for (final group in groups)
        if (group.sectionIds
                .where((id) => available.contains(id) && claimed.add(id))
                .toList(growable: false)
            case final members when members.isNotEmpty)
          group.copyWith(sectionIds: members),
    ]);
  }

  List<DrawingTimelineNode> buildNodes({
    required List<String> order,
    required List<DrawingSceneGroup> groups,
  }) {
    final groupBySection = <String, DrawingSceneGroup>{};
    for (final group in groups) {
      for (final id in group.sectionIds) {
        groupBySection[id] = group;
      }
    }
    final insertedGroups = <String>{};
    final nodes = <DrawingTimelineNode>[];
    for (final id in order) {
      final group = groupBySection[id];
      if (group == null) {
        nodes.add(DrawingTimelineNode.section(id));
      } else if (insertedGroups.add(group.id)) {
        final memberIds = group.sectionIds.toSet();
        nodes.add(
          DrawingTimelineNode.scene(
            group.copyWith(
              sectionIds: order
                  .where(memberIds.contains)
                  .toList(growable: false),
            ),
          ),
        );
      }
    }
    return List.unmodifiable(nodes);
  }

  List<String> reorderNode({
    required List<String> order,
    required List<DrawingSceneGroup> groups,
    required String draggedKey,
    required String targetKey,
  }) {
    final nodes = buildNodes(order: order, groups: groups).toList();
    final from = nodes.indexWhere((node) => node.key == draggedKey);
    final to = nodes.indexWhere((node) => node.key == targetKey);
    if (from < 0 || to < 0 || from == to) return order;
    final moved = nodes.removeAt(from);
    nodes.insert(to, moved);
    return List.unmodifiable(nodes.expand((node) => node.allSectionIds));
  }

  /// Moves one or more top-level timeline nodes to an insertion slot while
  /// preserving their existing relative order. Slots are expressed against
  /// the original node list: zero is before the first node and `length` is
  /// after the last node.
  List<String> reorderNodes({
    required List<String> order,
    required List<DrawingSceneGroup> groups,
    required Iterable<String> draggedKeys,
    required int insertionIndex,
  }) {
    final nodes = buildNodes(order: order, groups: groups);
    final requested = draggedKeys.toSet();
    final moved = nodes
        .where((node) => requested.contains(node.key))
        .toList(growable: false);
    if (moved.isEmpty) return order;

    final slot = insertionIndex.clamp(0, nodes.length);
    final movedBeforeSlot = nodes
        .take(slot)
        .where((node) => requested.contains(node.key))
        .length;
    final retained = nodes
        .where((node) => !requested.contains(node.key))
        .toList();
    final adjustedSlot = (slot - movedBeforeSlot).clamp(0, retained.length);
    retained.insertAll(adjustedSlot, moved);
    return List.unmodifiable(retained.expand((node) => node.allSectionIds));
  }

  List<String> reorderSceneMember({
    required List<String> order,
    required DrawingSceneGroup scene,
    required String draggedSectionId,
    required String targetSectionId,
  }) {
    if (!scene.sectionIds.contains(draggedSectionId) ||
        !scene.sectionIds.contains(targetSectionId) ||
        draggedSectionId == targetSectionId) {
      return order;
    }
    final sceneIds = scene.sectionIds.toSet();
    final members = order.where(sceneIds.contains).toList();
    final moved = members.removeAt(members.indexOf(draggedSectionId));
    members.insert(members.indexOf(targetSectionId), moved);
    final memberSet = members.toSet();
    final first = order.indexWhere(memberSet.contains);
    if (first < 0) return order;
    final result = order.where((id) => !memberSet.contains(id)).toList();
    result.insertAll(first.clamp(0, result.length), members);
    return List.unmodifiable(result);
  }

  ({List<String> order, DrawingSceneGroup group}) createGroup({
    required List<String> order,
    required Iterable<String> selectedSectionIds,
    required String id,
    required String name,
  }) {
    final selected = selectedSectionIds.toSet();
    final members = order.where(selected.contains).toList(growable: false);
    if (members.isEmpty) {
      throw ArgumentError('A scene requires at least one timeline section.');
    }
    final first = order.indexWhere(selected.contains);
    final reordered = order.where((id) => !selected.contains(id)).toList();
    reordered.insertAll(first.clamp(0, reordered.length), members);
    return (
      order: List.unmodifiable(reordered),
      group: DrawingSceneGroup(id: id, name: name, sectionIds: members),
    );
  }
}
