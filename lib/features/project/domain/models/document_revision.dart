final class DocumentRevision implements Comparable<DocumentRevision> {
  const DocumentRevision._(this.value);

  factory DocumentRevision(int value) {
    if (value < 0) {
      throw RangeError.value(
        value,
        'value',
        'Document revision cannot be negative.',
      );
    }
    return DocumentRevision._(value);
  }

  static const initial = DocumentRevision._(0);

  final int value;

  DocumentRevision get next => DocumentRevision._(value + 1);

  @override
  int compareTo(DocumentRevision other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      other is DocumentRevision && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
