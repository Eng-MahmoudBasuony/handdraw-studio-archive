import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:handdraw_studio/features/editor/application/session/document_fingerprint.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';

/// Reuses the manifest projection, removes machine-specific locators, then
/// recursively sorts map keys before hashing UTF-8 canonical JSON.
final class CanonicalDocumentFingerprintCalculator
    implements DocumentFingerprintCalculator {
  const CanonicalDocumentFingerprintCalculator({
    this.codec = const DevelopmentProjectManifestCodec(),
  });

  final DevelopmentProjectManifestCodec codec;
  static const canonicalJson = CanonicalSemanticJsonEncoder();
  static final _caches = Expando<Expando<DocumentFingerprints>>();

  @override
  DocumentFingerprints calculate(ProjectDocument document) {
    // Documents are immutable. Keep only weak keys so history/project closure
    // can release them, and isolate caches for differently configured codecs.
    final cache = _caches[this] ??= Expando<DocumentFingerprints>();
    return cache[document] ??= _calculate(document);
  }

  DocumentFingerprints _calculate(ProjectDocument document) {
    final manifest = codec.encode(document);
    return DocumentFingerprints(
      semantic: DocumentSemanticFingerprint(
        _digest(_semanticProjection(manifest)),
      ),
      persistence: DocumentPersistenceFingerprint(_digest(manifest)),
    );
  }

  String _digest(Object? projection) =>
      'sha256:${sha256.convert(utf8.encode(canonicalJson.encode(projection)))}';

  Object? _semanticProjection(Object? value) {
    if (value is List) {
      return [for (final item in value) _semanticProjection(item)];
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          if (entry.key != 'externalLocator')
            entry.key.toString(): _semanticProjection(entry.value),
      };
    }
    return value;
  }
}

final class CanonicalSemanticJsonEncoder {
  const CanonicalSemanticJsonEncoder();

  String encode(Object? value) => jsonEncode(_canonicalize(value));

  Object? _canonicalize(Object? value) {
    if (value is List) {
      return [for (final item in value) _canonicalize(item)];
    }
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    return value;
  }
}
