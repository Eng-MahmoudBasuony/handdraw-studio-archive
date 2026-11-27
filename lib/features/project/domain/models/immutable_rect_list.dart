import 'dart:collection';
import 'dart:ui';

/// An immutable rectangle collection that can be shared by dense path sets.
///
/// Auto Path commonly applies the same text-exclusion mask to thousands of
/// shape strokes. Keeping one canonical list avoids duplicating those Rects,
/// while [contentHash] lets renderer batch keys reuse the exact deep hash.
final class ImmutableRectList extends ListBase<Rect> {
  factory ImmutableRectList.freeze(Iterable<Rect> rects) {
    if (rects is ImmutableRectList) return rects;
    if (rects.isEmpty) return _empty;
    return ImmutableRectList._(List<Rect>.unmodifiable(rects));
  }

  ImmutableRectList._(this._rects);

  static final _empty = ImmutableRectList._(const <Rect>[]);

  final List<Rect> _rects;

  late final int contentHash = Object.hashAll(_rects);

  @override
  int get length => _rects.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Rectangle collections are immutable.');

  @override
  Rect operator [](int index) => _rects[index];

  @override
  void operator []=(int index, Rect value) =>
      throw UnsupportedError('Rectangle collections are immutable.');
}
