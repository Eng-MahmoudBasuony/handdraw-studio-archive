import 'dart:typed_data';

class ArtworkSource {
  const ArtworkSource({
    required this.path,
    required this.bytes,
    required this.extension,
  });

  final String path;
  final Uint8List bytes;
  final String extension;
}

abstract interface class ArtworkImporter<T> {
  bool supports(ArtworkSource source);

  Future<T> import(ArtworkSource source);
}
