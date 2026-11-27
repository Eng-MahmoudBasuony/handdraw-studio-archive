import 'dart:convert';
import 'dart:io';

import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';

/// Development-only plain manifest storage.
///
/// This is not the future archive container. The codec is injected and remains
/// independently testable; this class owns only UTF-8 JSON File IO.
final class DevelopmentProjectFileService {
  const DevelopmentProjectFileService({
    this.codec = const DevelopmentProjectManifestCodec(),
  });

  final DevelopmentProjectManifestCodec codec;

  Future<void> save(File file, EditorDocumentState state) async {
    final manifest = codec.encode(state.document);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      encoding: utf8,
      flush: true,
    );
  }

  Future<EditorDocumentState> open(File file) async {
    final raw = jsonDecode(await file.readAsString(encoding: utf8));
    if (raw is! Map) {
      throw const FormatException('Project manifest root must be an object.');
    }
    final document = codec.decode(
      raw.map((key, value) => MapEntry(key.toString(), value)),
    );
    return EditorDocumentState(document: document);
  }
}
