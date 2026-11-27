import 'dart:typed_data';

import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

final class ProjectContainerLocation {
  const ProjectContainerLocation(this.path);

  final String path;
}

abstract interface class ProjectAssetByteSource {
  Future<int> length();

  Stream<Uint8List> openRead();
}

abstract interface class ProjectAssetSourceCatalog {
  ProjectAssetByteSource? sourceFor(ProjectAssetId assetId);
}

enum ProjectContainerStage {
  validating,
  writing,
  verifying,
  replacing,
  opening,
}

final class ProjectContainerProgress {
  const ProjectContainerProgress({
    required this.stage,
    required this.completedBytes,
    required this.totalBytes,
    this.assetId,
  });

  final ProjectContainerStage stage;
  final int completedBytes;
  final int totalBytes;
  final ProjectAssetId? assetId;
}

/// Reports uncompressed bytes. Values are monotonic within one [stage] and may
/// reset when the operation advances to the next stage. Observer exceptions do
/// not fail a storage operation.
typedef ProjectContainerProgressCallback =
    void Function(ProjectContainerProgress progress);

/// Cancellation is cooperative at stream chunks and entry boundaries. Once an
/// already-verified temporary file enters the atomic replacement call, that
/// indivisible replacement is allowed to complete.
abstract interface class ProjectContainerCancellation {
  bool get isCancelled;
}

final class NeverCancelProjectContainer
    implements ProjectContainerCancellation {
  const NeverCancelProjectContainer();

  @override
  bool get isCancelled => false;
}

enum ProjectContainerFailureCode {
  cancelled,
  invalidDocument,
  invalidContainer,
  unsupportedFeature,
  limitExceeded,
  missingAssetSource,
  contentMismatch,
  storageFailure,
  unsupportedAtomicReplacementPlatform,
}

class ProjectContainerException implements Exception {
  const ProjectContainerException(this.code, this.message, [this.cause]);

  final ProjectContainerFailureCode code;
  final String message;
  final Object? cause;

  @override
  String toString() => 'ProjectContainerException(${code.name}): $message';
}

final class UnsupportedAtomicReplacementPlatform
    extends ProjectContainerException {
  const UnsupportedAtomicReplacementPlatform([String? message])
    : super(
        ProjectContainerFailureCode.unsupportedAtomicReplacementPlatform,
        message ??
            'Project saving is not supported on this platform because atomic '
                'replacement is unavailable.',
      );
}

abstract interface class ProjectContainerSession {
  ProjectDocument get document;

  /// Opens a bounded archive-backed stream. The session must remain open until
  /// all consumers finish, then [close] must be called by its owner.
  Stream<Uint8List> openAsset(ProjectAssetId assetId);

  Future<void> close();
}

abstract interface class ProjectContainerWriter {
  Future<void> save({
    required ProjectContainerLocation destination,
    required ProjectDocument document,
    required ProjectAssetSourceCatalog assetSources,
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  });
}

abstract interface class ProjectContainerReader {
  Future<ProjectContainerSession> open(
    ProjectContainerLocation source, {
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  });

  Future<int> cleanupStaleTemporaryFiles(ProjectContainerLocation destination);
}

abstract interface class ProjectContainerStore
    implements ProjectContainerWriter, ProjectContainerReader {}
