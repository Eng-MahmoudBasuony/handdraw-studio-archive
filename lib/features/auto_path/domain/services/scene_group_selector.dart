import 'dart:ui';

import 'package:handdraw_smart_path/handdraw_smart_path.dart';

/// Resolves a freehand canvas enclosure into complete Auto Path sections.
///
/// Selection works on sections rather than individual sampled points so a
/// user can never accidentally split a glyph, shape, or connector path while
/// arranging a complex scene.
class SceneGroupSelector {
  const SceneGroupSelector();

  List<String> select({
    required List<Offset> enclosure,
    required List<SmartPathSection> sections,
  }) {
    if (enclosure.length < 3) return const [];
    final polygonBounds = _bounds(enclosure);
    final selected = <String>[];
    for (final section in sections) {
      if (section.mode == SmartSectionMode.ignore ||
          section.role == SmartSectionRole.globalDecoration) {
        continue;
      }
      final sectionBounds = section.bounds;
      if (!polygonBounds.overlaps(sectionBounds) &&
          !polygonBounds.contains(sectionBounds.center)) {
        continue;
      }
      if (_contains(enclosure, sectionBounds.center) ||
          _contains(enclosure, sectionBounds.topLeft) ||
          _contains(enclosure, sectionBounds.topRight) ||
          _contains(enclosure, sectionBounds.bottomLeft) ||
          _contains(enclosure, sectionBounds.bottomRight)) {
        selected.add(section.id);
      }
    }
    return List.unmodifiable(selected);
  }

  bool _contains(List<Offset> polygon, Offset point) {
    var inside = false;
    for (
      var current = 0, previous = polygon.length - 1;
      current < polygon.length;
      previous = current++
    ) {
      final a = polygon[current];
      final b = polygon[previous];
      final crosses = (a.dy > point.dy) != (b.dy > point.dy);
      if (!crosses) continue;
      final intersectionX =
          (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (point.dx < intersectionX) inside = !inside;
    }
    return inside;
  }

  Rect _bounds(List<Offset> points) {
    var left = points.first.dx;
    var right = left;
    var top = points.first.dy;
    var bottom = top;
    for (final point in points.skip(1)) {
      if (point.dx < left) left = point.dx;
      if (point.dx > right) right = point.dx;
      if (point.dy < top) top = point.dy;
      if (point.dy > bottom) bottom = point.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }
}
