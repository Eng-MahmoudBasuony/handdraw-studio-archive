import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

/// Deterministic staging implementation for Flutter's fake-async test runtime.
/// Production uses [FileEditorAssetStagingStore] so large assets stay off heap.
final class MemoryEditorAssetStagingStore implements EditorAssetStagingStore {
  final Map<EditorSessionId, Map<ProjectAssetId, _MemoryRecord>> _sessions = {};

  @override
  Future<void> createSession(EditorSessionId sessionId) async {
    _sessions.putIfAbsent(sessionId, () => {});
  }

  @override
  Future<void> stageEmbedded(StageEmbeddedAssetRequest request) async {
    final records = _requireSession(request.sessionId);
    final bytes = request.source is EditorMemoryAssetStreamSource
        ? (request.source as EditorMemoryAssetStreamSource).bytes
        : await _collect(request.source.openRead());
    _verify(request.asset, bytes);
    records[request.asset.id] = _MemoryRecord(request.asset, bytes);
  }

  @override
  Future<void> registerExternal(RegisterExternalAssetRequest request) async {
    _requireSession(request.sessionId)[request.asset.id] = _MemoryRecord(
      request.asset,
      Uint8List(0),
    );
  }

  @override
  Future<StagedAssetLease> acquire({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  }) async {
    final record = _record(sessionId, assetId)..retain(kind);
    return _MemoryLease(this, sessionId, record, kind);
  }

  @override
  Future<StagedAssetLease> acquireVerifiedSnapshot({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
    AssetSnapshotCancellation cancellation = const NeverCancelAssetSnapshot(),
  }) => acquire(sessionId: sessionId, assetId: assetId, kind: kind);

  @override
  void retain({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  }) => _record(sessionId, assetId).retain(kind);

  @override
  void releaseReference({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  }) {
    final record = _sessions[sessionId]?[assetId];
    record?.release(kind);
  }

  @override
  Future<void> disposeSession(EditorSessionId sessionId) async {
    _sessions.remove(sessionId);
  }

  @override
  Future<int> cleanupStaleSessions() async => 0;

  Map<ProjectAssetId, _MemoryRecord> _requireSession(EditorSessionId id) {
    final records = _sessions[id];
    if (records == null) {
      throw const AssetStagingException(
        AssetStagingFailureCode.sessionClosed,
        'The staging session is unavailable.',
      );
    }
    return records;
  }

  _MemoryRecord _record(EditorSessionId sessionId, ProjectAssetId assetId) {
    final record = _requireSession(sessionId)[assetId];
    if (record == null) {
      throw AssetStagingException(
        AssetStagingFailureCode.missingAsset,
        'Asset $assetId is not staged.',
      );
    }
    return record;
  }

  void _verify(ProjectAsset asset, Uint8List bytes) {
    final actual = 'sha256:${sha256.convert(bytes)}';
    if (actual != asset.contentHash) {
      throw AssetStagingException(
        AssetStagingFailureCode.hashMismatch,
        'Asset ${asset.id} failed staging hash validation.',
      );
    }
  }

  Future<void> _release(
    EditorSessionId sessionId,
    _MemoryRecord record,
    StagedAssetReferenceKind kind,
  ) async {
    if (_sessions[sessionId]?[record.asset.id] == record) record.release(kind);
  }
}

final class _MemoryRecord {
  _MemoryRecord(this.asset, Uint8List bytes)
    : bytes = Uint8List.fromList(bytes);

  final ProjectAsset asset;
  final Uint8List bytes;
  final Map<StagedAssetReferenceKind, int> references = {};

  void retain(StagedAssetReferenceKind kind) =>
      references.update(kind, (value) => value + 1, ifAbsent: () => 1);

  void release(StagedAssetReferenceKind kind) {
    final count = references[kind] ?? 0;
    if (count <= 1) {
      references.remove(kind);
    } else {
      references[kind] = count - 1;
    }
  }
}

final class _MemoryLease implements StagedAssetLease {
  _MemoryLease(this.store, this.sessionId, this.record, this.kind);

  final MemoryEditorAssetStagingStore store;
  final _MemoryRecord record;
  @override
  final EditorSessionId sessionId;
  @override
  final StagedAssetReferenceKind kind;
  bool _released = false;

  @override
  ProjectAssetId get assetId => record.asset.id;
  @override
  int get length => record.bytes.length;
  @override
  Stream<Uint8List> openRead() => Stream.value(record.bytes);
  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await store._release(sessionId, record, kind);
  }
}

Future<Uint8List> _collect(Stream<Uint8List> source) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in source) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}
