/// An actionable local preparation failure; unrelated to Codex quota or planning.
final class ImagePartsFailure implements Exception {
  const ImagePartsFailure(this.code, {this.partName});
  final String code;
  final String? partName;
  @override
  String toString() => 'ImagePartsFailure($code)';
}
