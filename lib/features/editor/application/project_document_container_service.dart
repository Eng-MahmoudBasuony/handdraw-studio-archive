import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';

/// Application-level Save/Open orchestration for the source-of-truth document.
///
/// Opening returns a new immutable state only after the complete container and
/// every embedded asset have passed validation. Callers keep the current state
/// unchanged if this operation fails and own the returned session lifetime.
final class OpenedProjectDocument {
  const OpenedProjectDocument({required this.state, required this.session});

  final EditorDocumentState state;
  final ProjectContainerSession session;
}

final class ProjectDocumentContainerService {
  const ProjectDocumentContainerService({required this.store});

  final ProjectContainerStore store;

  Future<void> save({
    required ProjectContainerLocation destination,
    required EditorDocumentState state,
    required ProjectAssetSourceCatalog assetSources,
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  }) => store.save(
    destination: destination,
    document: state.document,
    assetSources: assetSources,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  Future<OpenedProjectDocument> open(
    ProjectContainerLocation source, {
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  }) async {
    final session = await store.open(
      source,
      cancellation: cancellation,
      onProgress: onProgress,
    );
    return OpenedProjectDocument(
      state: EditorDocumentState(document: session.document),
      session: session,
    );
  }
}
