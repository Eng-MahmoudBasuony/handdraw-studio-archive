import 'dart:typed_data';

import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

extension type const EditorSessionId(String value) {}

enum StagedAssetReferenceKind { activeDocument, history, preview, export, save }

enum AssetStagingFailureCode {
  missingAsset,
  hashMismatch,
  sourceChanged,
  sessionMismatch,
  sessionClosed,
  invalidSource,
  storageFailure,
  externalAssetChangedDuringRead,
  externalAssetContentMismatch,
  cancelled,
}

final class AssetStagingException implements Exception {
  const AssetStagingException(this.code, this.message, [this.cause]);

  final AssetStagingFailureCode code;
  final String message;
  final Object? cause;
}

abstract interface class EditorAssetStreamSource {
  Future<int> length();
  Stream<Uint8List> openRead();
}

abstract interface class EditorMemoryAssetStreamSource
    implements EditorAssetStreamSource {
  Uint8List get bytes;
}

final class StageEmbeddedAssetRequest {
  const StageEmbeddedAssetRequest({
    required this.sessionId,
    required this.asset,
    required this.source,
  });

  final EditorSessionId sessionId;
  final ProjectAsset asset;
  final EditorAssetStreamSource source;
}

final class RegisterExternalAssetRequest {
  const RegisterExternalAssetRequest({
    required this.sessionId,
    required this.asset,
  });

  final EditorSessionId sessionId;
  final ProjectAsset asset;
}

abstract interface class StagedAssetLease {
  ProjectAssetId get assetId;
  EditorSessionId get sessionId;
  StagedAssetReferenceKind get kind;
  int get length;
  Stream<Uint8List> openRead();
  Future<void> release();
}

abstract interface class AssetSnapshotCancellation {
  bool get isCancelled;
}

final class NeverCancelAssetSnapshot implements AssetSnapshotCancellation {
  const NeverCancelAssetSnapshot();
  @override
  bool get isCancelled => false;
}

abstract interface class ExternalAssetSnapshotProvider {
  Future<StagedAssetLease> acquireVerifiedSnapshot({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
    AssetSnapshotCancellation cancellation = const NeverCancelAssetSnapshot(),
  });
}

abstract interface class EditorAssetStagingStore
    implements ExternalAssetSnapshotProvider {
  Future<void> createSession(EditorSessionId sessionId);

  Future<void> stageEmbedded(StageEmbeddedAssetRequest request);

  Future<void> registerExternal(RegisterExternalAssetRequest request);

  Future<StagedAssetLease> acquire({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  });

  void retain({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  });

  void releaseReference({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  });

  Future<void> disposeSession(EditorSessionId sessionId);

  Future<int> cleanupStaleSessions();
}
