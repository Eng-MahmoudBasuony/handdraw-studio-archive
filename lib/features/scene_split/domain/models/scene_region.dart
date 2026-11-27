import 'dart:ui';

/// A normalized, editable mask proposed before Auto Path is executed.
///
/// Automatic regions retain their disconnected component fragments so masking
/// follows the visible artwork rather than exposing a rectangular crop. Manual
/// regions use [polygon], which is also suitable for a precise lasso.
final class SceneRegion {
  SceneRegion({
    required this.id,
    required this.name,
    required Iterable<Offset> polygon,
    Iterable<Rect> fragments = const [],
    Iterable<List<Offset>> additionalPolygons = const [],
    this.automatic = false,
  }) : polygon = List.unmodifiable(polygon),
       fragments = List.unmodifiable(fragments),
       additionalPolygons = List.unmodifiable([
         for (final item in additionalPolygons) List<Offset>.unmodifiable(item),
       ]);

  final String id;
  final String name;
  final List<Offset> polygon;
  final List<Rect> fragments;
  final List<List<Offset>> additionalPolygons;
  final bool automatic;

  Rect get bounds {
    final source = <Offset>[
      ...polygon,
      for (final item in additionalPolygons) ...item,
      for (final fragment in fragments) ...[
        fragment.topLeft,
        fragment.bottomRight,
      ],
    ];
    if (source.isEmpty) return Rect.zero;
    var left = source.first.dx;
    var top = source.first.dy;
    var right = left;
    var bottom = top;
    for (final point in source.skip(1)) {
      left = point.dx < left ? point.dx : left;
      top = point.dy < top ? point.dy : top;
      right = point.dx > right ? point.dx : right;
      bottom = point.dy > bottom ? point.dy : bottom;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  bool contains(Offset point) {
    if (fragments.isNotEmpty) {
      if (fragments.any((fragment) => fragment.contains(point))) return true;
    }
    return maskPolygons.any((item) => _polygonContains(item, point));
  }

  List<List<Offset>> get maskPolygons => List.unmodifiable([
    // Automatic proposals keep a union bounds polygon for selection/labels,
    // but the mask itself must use only the disconnected alpha fragments.
    if (fragments.isEmpty && polygon.length >= 3) polygon,
    ...additionalPolygons.where((item) => item.length >= 3),
    for (final fragment in fragments) rectPolygon(fragment),
  ]);

  static bool _polygonContains(List<Offset> polygon, Offset point) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (
      var current = 0, previous = polygon.length - 1;
      current < polygon.length;
      previous = current++
    ) {
      final a = polygon[current];
      final b = polygon[previous];
      if ((a.dy > point.dy) == (b.dy > point.dy)) continue;
      final x = (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (point.dx < x) inside = !inside;
    }
    return inside;
  }

  SceneRegion copyWith({
    String? id,
    String? name,
    List<Offset>? polygon,
    List<Rect>? fragments,
    List<List<Offset>>? additionalPolygons,
    bool? automatic,
  }) => SceneRegion(
    id: id ?? this.id,
    name: name ?? this.name,
    polygon: polygon ?? this.polygon,
    fragments: fragments ?? this.fragments,
    additionalPolygons: additionalPolygons ?? this.additionalPolygons,
    automatic: automatic ?? this.automatic,
  );
}

List<Offset> rectPolygon(Rect rect) => [
  rect.topLeft,
  rect.topRight,
  rect.bottomRight,
  rect.bottomLeft,
];
