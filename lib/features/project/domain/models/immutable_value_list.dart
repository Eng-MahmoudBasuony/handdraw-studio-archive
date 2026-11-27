import 'dart:collection';

/// A small deeply-owned immutable list wrapper that preserves identity when it
/// is passed through model constructors and `copyWith` calls.
///
/// Values stored here must themselves be immutable value objects. The wrapper
/// is intentionally JSON-agnostic and remains a normal [List] to every codec.
final class ImmutableValueList<T> extends ListBase<T> {
  factory ImmutableValueList.freeze(Iterable<T> values) {
    if (values is ImmutableValueList<T>) return values;
    return ImmutableValueList._(List<T>.unmodifiable(values));
  }

  ImmutableValueList._(this._values);

  final List<T> _values;

  @override
  int get length => _values.length;

  @override
  set length(int value) => throw UnsupportedError('Value lists are immutable.');

  @override
  T operator [](int index) => _values[index];

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('Value lists are immutable.');
}
