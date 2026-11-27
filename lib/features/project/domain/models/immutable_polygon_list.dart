import 'dart:collection';

/// A deeply immutable polygon collection that can be safely shared by every
/// stroke belonging to the same scene mask.
///
/// Dense Auto Path scenes can contain thousands of strokes. Copying an
/// identical multi-polygon mask into each stroke multiplied memory and project
/// preparation time without adding any visual information.
final class ImmutablePolygonList<T> extends ListBase<List<T>> {
  factory ImmutablePolygonList.freeze(Iterable<List<T>> polygons) {
    if (polygons is ImmutablePolygonList<T>) return polygons;
    return ImmutablePolygonList<T>._(
      List<List<T>>.unmodifiable([
        for (final polygon in polygons) List<T>.unmodifiable(polygon),
      ]),
    );
  }

  const ImmutablePolygonList._(this._polygons);

  final List<List<T>> _polygons;

  @override
  int get length => _polygons.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Polygon masks are immutable.');

  @override
  List<T> operator [](int index) => _polygons[index];

  @override
  void operator []=(int index, List<T> value) =>
      throw UnsupportedError('Polygon masks are immutable.');
}
