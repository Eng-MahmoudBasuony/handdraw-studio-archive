import 'package:handdraw_studio/features/project/domain/models/document_revision.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

/// Immutable ownership boundary for the persistent editor document.
///
/// Selection, playback, loading, decoded images, and caches remain separate
/// view/runtime state. Every document replacement advances the revision so
/// derived read models can be cached without becoming stale.
final class EditorDocumentState {
  const EditorDocumentState({
    required this.document,
    this.revision = DocumentRevision.initial,
  });

  final ProjectDocument document;
  final DocumentRevision revision;

  /// Runtime-only revision change. Persistent codecs never serialize it.
  EditorDocumentState replace(ProjectDocument next) =>
      EditorDocumentState(document: next, revision: revision.next);
}
