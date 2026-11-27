import 'dart:typed_data';
import 'dart:math';

import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/session/document_fingerprint.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/application/session/staging_history_asset_retention.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_duplicator.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_factory.dart';

abstract interface class EditorSessionIdGenerator {
  EditorSessionId next();
}

final class IncrementingEditorSessionIdGenerator
    implements EditorSessionIdGenerator {
  int _next = 1;

  @override
  EditorSessionId next() => EditorSessionId('session-${_next++}');
}

final class UniqueEditorSessionIdGenerator implements EditorSessionIdGenerator {
  UniqueEditorSessionIdGenerator({Random? random})
    : _random = random ?? Random.secure();

  final Random _random;

  @override
  EditorSessionId next() {
    final time = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final entropy = List.generate(
      4,
      (_) => _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0'),
    ).join();
    return EditorSessionId('session-$time-$entropy');
  }
}

final class EditorSession {
  EditorSession._({
    required this.id,
    required this.state,
    required this.history,
    this.target,
  }) : activeAssetIds = state.document.assets.map((asset) => asset.id).toSet();

  final EditorSessionId id;
  EditorDocumentState state;
  final EditorHistory history;
  ProjectContainerLocation? target;
  final Set<ProjectAssetId> activeAssetIds;
  bool _closed = false;

  bool get isClosed => _closed;
}

final class EditorSessionCoordinator {
  EditorSessionCoordinator({
    required this.staging,
    required this.containerStore,
    required this.fingerprints,
    required this.projectIds,
    EditorSessionIdGenerator? sessionIds,
    this.factory = const ProjectDocumentFactory(),
    this.duplicator = const ProjectDocumentDuplicator(),
  }) : sessionIds = sessionIds ?? UniqueEditorSessionIdGenerator();

  final EditorAssetStagingStore staging;
  final ProjectContainerStore containerStore;
  final DocumentFingerprintCalculator fingerprints;
  final IdGenerator projectIds;
  final EditorSessionIdGenerator sessionIds;
  final ProjectDocumentFactory factory;
  final ProjectDocumentDuplicator duplicator;

  Future<EditorSession> createNew({String title = 'Untitled Project'}) async {
    final document = factory.createEmpty(ids: projectIds, title: title);
    return _createSession(document, clean: false);
  }

  /// Creates a runtime session around an already-authored canonical document.
  /// Used by import and by the initial editor bootstrap without routing through
  /// a legacy project representation.
  Future<EditorSession> createFromDocument({
    required EditorDocumentState state,
    Map<ProjectAssetId, EditorAssetStreamSource> embeddedSources = const {},
    EditorHistory? history,
    ProjectContainerLocation? target,
    bool clean = false,
  }) => _createSession(
    state.document,
    clean: clean,
    state: state,
    history: history,
    target: target,
    stage: (id) => _stageDocumentAssets(
      sessionId: id,
      document: state.document,
      embeddedSources: embeddedSources,
    ),
  );

  Future<EditorSession> open(ProjectContainerLocation source) async {
    final container = await containerStore.open(source);
    try {
      final session = await _createSession(
        container.document,
        clean: false,
        stage: (id) => _stageOpenedAssets(id, container),
        target: source,
      );
      _markCurrentSaved(session);
      return session;
    } finally {
      await container.close();
    }
  }

  Future<EditorSession> duplicate(EditorSession source, {String? title}) async {
    _requireOpen(source);
    final duplicate = duplicator.duplicate(
      source.state.document,
      ids: projectIds,
      title: title,
    );
    return _createSession(
      duplicate,
      clean: false,
      stage: (id) => _stageDuplicateAssets(
        sourceSession: source,
        destinationSessionId: id,
        duplicate: duplicate,
      ),
    );
  }

  void publishHistoryState(EditorSession session, EditorDocumentState state) {
    _requireOpen(session);
    session.state = state;
  }

  Future<void> synchronizeDocumentAssets(
    EditorSession session, {
    required EditorDocumentState state,
    Map<ProjectAssetId, EditorAssetStreamSource> embeddedSources = const {},
  }) async {
    _requireOpen(session);
    final nextIds = state.document.assets.map((asset) => asset.id).toSet();
    for (final asset in state.document.assets) {
      if (session.activeAssetIds.contains(asset.id)) continue;
      await _stageDocumentAssets(
        sessionId: session.id,
        document: state.document.copyWith(assets: [asset]),
        embeddedSources: embeddedSources,
      );
      staging.retain(
        sessionId: session.id,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.activeDocument,
      );
      session.activeAssetIds.add(asset.id);
    }
    for (final removed in session.activeAssetIds.difference(nextIds).toList()) {
      staging.releaseReference(
        sessionId: session.id,
        assetId: removed,
        kind: StagedAssetReferenceKind.activeDocument,
      );
      session.activeAssetIds.remove(removed);
    }
    session.state = state;
  }

  bool isDirty(EditorSession session) {
    _requireOpen(session);
    final persistence = fingerprints
        .calculate(session.state.document)
        .persistence
        .value;
    return session.history.isDirty(currentFingerprint: persistence);
  }

  Future<void> save(
    EditorSession session, {
    ProjectContainerLocation? destination,
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
  }) async {
    _requireOpen(session);
    final target = destination ?? session.target;
    if (target == null) {
      throw ArgumentError('A destination is required for the first save.');
    }
    final stateSnapshot = session.state;
    final fingerprint = fingerprints
        .calculate(stateSnapshot.document)
        .persistence;
    final saveSnapshot = session.history.captureSaveSnapshot(fingerprint.value);
    final leases = <ProjectAssetId, StagedAssetLease>{};
    try {
      for (final asset in stateSnapshot.document.assets) {
        leases[asset.id] =
            asset.storagePolicy == ProjectAssetStoragePolicy.external
            ? await staging.acquireVerifiedSnapshot(
                sessionId: session.id,
                assetId: asset.id,
                kind: StagedAssetReferenceKind.save,
                cancellation: _ProjectSnapshotCancellation(cancellation),
              )
            : await staging.acquire(
                sessionId: session.id,
                assetId: asset.id,
                kind: StagedAssetReferenceKind.save,
              );
      }
      await containerStore.save(
        destination: target,
        document: stateSnapshot.document,
        assetSources: _LeaseAssetCatalog(leases),
        cancellation: cancellation,
      );
      session.target = target;
      session.history.markSaved(saveSnapshot);
    } finally {
      for (final lease in leases.values) {
        await lease.release();
      }
    }
  }

  Future<void> close(EditorSession session, {bool clearHistory = true}) async {
    if (session._closed) return;
    session._closed = true;
    for (final assetId in session.activeAssetIds) {
      staging.releaseReference(
        sessionId: session.id,
        assetId: assetId,
        kind: StagedAssetReferenceKind.activeDocument,
      );
    }
    if (clearHistory) session.history.clear();
    await staging.disposeSession(session.id);
  }

  Future<EditorSession> _createSession(
    ProjectDocument document, {
    required bool clean,
    EditorDocumentState? state,
    EditorHistory? history,
    Future<void> Function(EditorSessionId id)? stage,
    ProjectContainerLocation? target,
  }) async {
    final id = sessionIds.next();
    await staging.createSession(id);
    try {
      await stage?.call(id);
      for (final asset in document.assets) {
        staging.retain(
          sessionId: id,
          assetId: asset.id,
          kind: StagedAssetReferenceKind.activeDocument,
        );
      }
      final retention = StagingHistoryAssetRetention(
        sessionId: id,
        staging: staging,
      );
      final session = EditorSession._(
        id: id,
        state: state ?? EditorDocumentState(document: document),
        history: history ?? EditorHistory(assetRetention: retention),
        target: target,
      );
      if (clean) _markCurrentSaved(session);
      return session;
    } catch (_) {
      await staging.disposeSession(id);
      rethrow;
    }
  }

  Future<void> _stageDocumentAssets({
    required EditorSessionId sessionId,
    required ProjectDocument document,
    required Map<ProjectAssetId, EditorAssetStreamSource> embeddedSources,
  }) async {
    for (final asset in document.assets) {
      if (asset.storagePolicy == ProjectAssetStoragePolicy.external) {
        await staging.registerExternal(
          RegisterExternalAssetRequest(sessionId: sessionId, asset: asset),
        );
        continue;
      }
      final source = embeddedSources[asset.id];
      if (source == null) {
        throw AssetStagingException(
          AssetStagingFailureCode.missingAsset,
          'Embedded asset ${asset.id} has no runtime source.',
        );
      }
      await staging.stageEmbedded(
        StageEmbeddedAssetRequest(
          sessionId: sessionId,
          asset: asset,
          source: source,
        ),
      );
    }
  }

  Future<void> _stageOpenedAssets(
    EditorSessionId sessionId,
    ProjectContainerSession container,
  ) async {
    for (final asset in container.document.assets) {
      if (asset.storagePolicy == ProjectAssetStoragePolicy.embedded) {
        await staging.stageEmbedded(
          StageEmbeddedAssetRequest(
            sessionId: sessionId,
            asset: asset,
            source: _ContainerAssetSource(container, asset),
          ),
        );
      } else {
        await staging.registerExternal(
          RegisterExternalAssetRequest(sessionId: sessionId, asset: asset),
        );
      }
    }
  }

  Future<void> _stageDuplicateAssets({
    required EditorSession sourceSession,
    required EditorSessionId destinationSessionId,
    required ProjectDocument duplicate,
  }) async {
    final sourceAssets = sourceSession.state.document.assets;
    for (var index = 0; index < sourceAssets.length; index++) {
      final sourceAsset = sourceAssets[index];
      final duplicateAsset = duplicate.assets[index];
      if (sourceAsset.storagePolicy == ProjectAssetStoragePolicy.external) {
        await staging.registerExternal(
          RegisterExternalAssetRequest(
            sessionId: destinationSessionId,
            asset: duplicateAsset,
          ),
        );
        continue;
      }
      final lease = await staging.acquire(
        sessionId: sourceSession.id,
        assetId: sourceAsset.id,
        kind: StagedAssetReferenceKind.save,
      );
      try {
        await staging.stageEmbedded(
          StageEmbeddedAssetRequest(
            sessionId: destinationSessionId,
            asset: duplicateAsset,
            source: _LeaseStreamSource(lease),
          ),
        );
      } finally {
        await lease.release();
      }
    }
  }

  void _markCurrentSaved(EditorSession session) {
    final fingerprint = fingerprints
        .calculate(session.state.document)
        .persistence;
    session.history.markSaved(
      session.history.captureSaveSnapshot(fingerprint.value),
    );
  }

  void _requireOpen(EditorSession session) {
    if (session.isClosed) {
      throw StateError('The editor session is closed.');
    }
  }
}

final class _ProjectSnapshotCancellation implements AssetSnapshotCancellation {
  const _ProjectSnapshotCancellation(this.source);
  final ProjectContainerCancellation source;
  @override
  bool get isCancelled => source.isCancelled;
}

final class _ContainerAssetSource implements EditorAssetStreamSource {
  const _ContainerAssetSource(this.container, this.asset);

  final ProjectContainerSession container;
  final ProjectAsset asset;

  @override
  Future<int> length() async {
    var total = 0;
    await for (final chunk in container.openAsset(asset.id)) {
      total += chunk.length;
    }
    return total;
  }

  @override
  Stream<Uint8List> openRead() => container.openAsset(asset.id);
}

final class _LeaseStreamSource implements EditorAssetStreamSource {
  const _LeaseStreamSource(this.lease);

  final StagedAssetLease lease;

  @override
  Future<int> length() async => lease.length;

  @override
  Stream<Uint8List> openRead() => lease.openRead();
}

final class _LeaseAssetCatalog implements ProjectAssetSourceCatalog {
  const _LeaseAssetCatalog(this.leases);

  final Map<ProjectAssetId, StagedAssetLease> leases;

  @override
  ProjectAssetByteSource? sourceFor(ProjectAssetId assetId) {
    final lease = leases[assetId];
    return lease == null ? null : _ProjectLeaseByteSource(lease);
  }
}

final class _ProjectLeaseByteSource implements ProjectAssetByteSource {
  const _ProjectLeaseByteSource(this.lease);

  final StagedAssetLease lease;

  @override
  Future<int> length() async => lease.length;

  @override
  Stream<Uint8List> openRead() => lease.openRead();
}
