import 'package:handdraw_studio/features/editor/application/transactions/document_transaction_coordinator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';

/// Compares only manifest fields represented by the operation's affected
/// scopes. It avoids hashing or serializing unrelated document fragments.
final class CanonicalScopedDocumentChangeDetector
    implements ScopedDocumentChangeDetector {
  const CanonicalScopedDocumentChangeDetector({
    this.codec = const DevelopmentProjectManifestCodec(),
  });

  final DevelopmentProjectManifestCodec codec;
  static const _canonical = CanonicalSemanticJsonEncoder();

  @override
  bool hasChanges(
    ProjectDocument before,
    ProjectDocument after,
    Set<DocumentScope> scopes,
  ) {
    if (scopes.isEmpty) return false;
    final beforeProject =
        codec.encode(before)['project']! as Map<String, Object?>;
    final afterProject =
        codec.encode(after)['project']! as Map<String, Object?>;
    final keys = <String>{for (final scope in scopes) ..._keys(scope)};
    final beforeProjection = {for (final key in keys) key: beforeProject[key]};
    final afterProjection = {for (final key in keys) key: afterProject[key]};
    return _canonical.encode(beforeProjection) !=
        _canonical.encode(afterProjection);
  }
}

Set<String> _keys(DocumentScope scope) => switch (scope) {
  DocumentScope.strokes ||
  DocumentScope.paths ||
  DocumentScope.masks => const {'strokes'},
  DocumentScope.sections || DocumentScope.timing => const {'sections'},
  DocumentScope.ordering => const {'sectionOrder'},
  DocumentScope.scenes => const {'scenes'},
  DocumentScope.assets => const {
    'assets',
    'artworkAssetId',
    'artworkPlacement',
  },
  DocumentScope.audio => const {'audioTracks', 'voiceGuide', 'durationUs'},
  DocumentScope.canvas => const {'canvas', 'frameRate', 'durationUs'},
  DocumentScope.hand => const {'hand'},
  DocumentScope.export => const {'export'},
  DocumentScope.settings => const {
    'id',
    'title',
    'motion',
    'writingSound',
    'autoDirectorSettings',
    'pathProcessing',
  },
  DocumentScope.camera => const {'cameraTrack'},
  DocumentScope.semantic => const {'contentMetadata'},
};
