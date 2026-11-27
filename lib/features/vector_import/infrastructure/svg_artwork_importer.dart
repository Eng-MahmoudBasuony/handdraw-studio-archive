import 'dart:convert';
import 'dart:isolate';

import 'package:handdraw_studio/features/path_document/domain/repositories/artwork_importer.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_artwork_import.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_artwork_parser.dart';

class SvgArtworkImporter implements ArtworkImporter<SvgArtworkImport> {
  const SvgArtworkImporter({this.parser = const SvgArtworkParser()});

  final SvgArtworkParser parser;

  @override
  bool supports(ArtworkSource source) =>
      source.extension.toLowerCase() == 'svg';

  @override
  Future<SvgArtworkImport> import(ArtworkSource source) async {
    if (!supports(source)) {
      throw UnsupportedError('SvgArtworkImporter only accepts SVG sources.');
    }
    final decoded = utf8.decode(source.bytes);
    final transferred = await Isolate.run(
      () => parser.parse(decoded).toTransferJson(),
    );
    return SvgArtworkImport.fromTransferJson(transferred);
  }
}
