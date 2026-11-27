import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_session_coordinator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/file_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';

final class _BytesEditorSource implements EditorMemoryAssetStreamSource {
  const _BytesEditorSource(this.bytes);
  @override
  final Uint8List bytes;
  @override
  Future<int> length() async => bytes.length;
  @override
  Stream<Uint8List> openRead() => Stream.value(bytes);
}

void main() {
  late Directory temporary;
  late FileEditorAssetStagingStore staging;
  late _MemoryContainerStore containers;
  late EditorSessionCoordinator coordinator;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('handdraw-session-test-');
    staging = FileEditorAssetStagingStore(temporary);
    containers = _MemoryContainerStore();
    coordinator = EditorSessionCoordinator(
      staging: staging,
      containerStore: containers,
      fingerprints: const CanonicalDocumentFingerprintCalculator(),
      projectIds: SequentialIdGenerator(),
    );
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test('New starts initial revision, empty history, and dirty state', () async {
    final session = await coordinator.createNew();
    expect(session.state.revision.value, 0);
    expect(session.history.undoEntries, isEmpty);
    expect(session.history.isDirty(), isTrue);
    await coordinator.close(session);
  });

  test('Open stages embedded assets and starts clean', () async {
    final bytes = Uint8List.fromList([1, 3, 5, 7]);
    final document = _document(bytes);
    containers.openDocument = document;
    containers.openBytes = {document.assets.single.id: bytes};
    final session = await coordinator.open(
      const ProjectContainerLocation('open'),
    );
    expect(session.state.revision.value, 0);
    expect(session.history.isDirty(), isFalse);
    final lease = await staging.acquire(
      sessionId: session.id,
      assetId: document.assets.single.id,
      kind: StagedAssetReferenceKind.preview,
    );
    expect(await _collect(lease.openRead()), bytes);
    await lease.release();
    await coordinator.close(session);
  });

  test(
    'runtime adoption stages assets and preserves the supplied history',
    () async {
      final bytes = Uint8List.fromList([7, 8, 9]);
      final document = _document(bytes);
      final history = EditorHistory();
      final session = await coordinator.createFromDocument(
        state: EditorDocumentState(document: document),
        history: history,
        embeddedSources: {document.assets.single.id: _BytesEditorSource(bytes)},
      );
      expect(session.history, same(history));
      final lease = await staging.acquire(
        sessionId: session.id,
        assetId: document.assets.single.id,
        kind: StagedAssetReferenceKind.preview,
      );
      expect(await _collect(lease.openRead()), bytes);
      await lease.release();
      await coordinator.close(session);
    },
  );

  test(
    'Duplicate remaps identities, shares immutable content, and is dirty',
    () async {
      final bytes = Uint8List.fromList([2, 4, 6]);
      final document = _document(bytes);
      containers.openDocument = document;
      containers.openBytes = {document.assets.single.id: bytes};
      final original = await coordinator.open(
        const ProjectContainerLocation('open'),
      );
      final duplicate = await coordinator.duplicate(original);
      expect(duplicate.state.document.id, isNot(original.state.document.id));
      expect(
        duplicate.state.document.assets.single.id,
        isNot(original.state.document.assets.single.id),
      );
      expect(
        duplicate.state.document.assets.single.contentHash,
        original.state.document.assets.single.contentHash,
      );
      expect(duplicate.history.isDirty(), isTrue);
      final lease = await staging.acquire(
        sessionId: duplicate.id,
        assetId: duplicate.state.document.assets.single.id,
        kind: StagedAssetReferenceKind.preview,
      );
      expect(await _collect(lease.openRead()), bytes);
      await lease.release();
      await coordinator.close(duplicate);
      await coordinator.close(original);
    },
  );

  test('old save snapshot cannot mark a newer edit clean', () async {
    final bytes = Uint8List.fromList([8, 9]);
    final document = _document(bytes);
    containers.openDocument = document;
    containers.openBytes = {document.assets.single.id: bytes};
    final session = await coordinator.open(
      const ProjectContainerLocation('open'),
    );
    containers.blockSave = Completer<void>();
    final saving = coordinator.save(
      session,
      destination: const ProjectContainerLocation('saved'),
    );
    await containers.saveStarted.future;

    final edited = _commitTitle(session.history, session.state, 'Newer');
    coordinator.publishHistoryState(session, edited);
    containers.blockSave!.complete();
    await saving;
    expect(session.history.isDirty(), isTrue);
    expect(session.target?.path, 'saved');
    await coordinator.close(session);
  });

  test(
    'save race compares current persistence even when history token is unchanged',
    () async {
      final bytes = Uint8List.fromList([41, 42]);
      final document = _document(bytes);
      containers.openDocument = document;
      containers.openBytes = {document.assets.single.id: bytes};
      final session = await coordinator.open(
        const ProjectContainerLocation('open'),
      );
      containers.blockSave = Completer<void>();
      final saving = coordinator.save(session);
      await containers.saveStarted.future;
      coordinator.publishHistoryState(
        session,
        session.state.replace(
          session.state.document.copyWith(
            title: 'out-of-band newer persistence',
          ),
        ),
      );
      containers.blockSave!.complete();
      await saving;
      expect(coordinator.isDirty(session), isTrue);
      await coordinator.close(session);
    },
  );

  test('save lease survives close until save completes', () async {
    final bytes = Uint8List.fromList([10, 11, 12]);
    final document = _document(bytes);
    containers.openDocument = document;
    containers.openBytes = {document.assets.single.id: bytes};
    final session = await coordinator.open(
      const ProjectContainerLocation('open'),
    );
    containers.blockSave = Completer<void>();
    final saving = coordinator.save(session);
    await containers.saveStarted.future;
    await coordinator.close(session);
    expect(
      await Directory('${temporary.path}/${session.id.value}').exists(),
      isTrue,
    );
    containers.blockSave!.complete();
    await saving;
    expect(
      await Directory('${temporary.path}/${session.id.value}').exists(),
      isFalse,
    );
  });

  test(
    'cancelled save releases its leases and preserves the session',
    () async {
      final bytes = Uint8List.fromList([20, 21]);
      final document = _document(bytes);
      containers.openDocument = document;
      containers.openBytes = {document.assets.single.id: bytes};
      final session = await coordinator.open(
        const ProjectContainerLocation('open'),
      );
      final cancellation = _Cancellation()..cancelled = true;
      await expectLater(
        coordinator.save(session, cancellation: cancellation),
        throwsA(
          isA<ProjectContainerException>().having(
            (error) => error.code,
            'code',
            ProjectContainerFailureCode.cancelled,
          ),
        ),
      );
      expect(session.history.isDirty(), isFalse);
      await coordinator.close(session);
      expect(
        await Directory('${temporary.path}/${session.id.value}').exists(),
        isFalse,
      );
    },
  );

  test(
    'relink with identical content is dirty until persistence save',
    () async {
      final bytes = Uint8List.fromList([31, 32, 33]);
      final first = File('${temporary.path}/first.bin');
      final second = File('${temporary.path}/second.bin');
      await first.writeAsBytes(bytes);
      await second.writeAsBytes(bytes);
      final embedded = _document(bytes);
      final external = embedded.assets.single.copyWith(
        storagePolicy: ProjectAssetStoragePolicy.external,
        externalLocator: ExternalAssetLocator(
          pathHint: first.path,
          securityBookmark: 'bookmark-a',
        ),
      );
      containers.openDocument = embedded.copyWith(assets: [external]);
      final session = await coordinator.open(
        const ProjectContainerLocation('external-open'),
      );
      expect(coordinator.isDirty(session), isFalse);
      final relinked = external.copyWith(
        externalLocator: ExternalAssetLocator(
          pathHint: second.path,
          securityBookmark: 'bookmark-b',
        ),
      );
      final edited = _commitAssets(
        session.history,
        session.state,
        session.state.document.copyWith(assets: [relinked]),
      );
      coordinator.publishHistoryState(session, edited);
      // Registration remains bound to the verified original source until the
      // relink operation updates staging in the future operation layer.
      expect(coordinator.isDirty(session), isTrue);
      await coordinator.save(session);
      expect(coordinator.isDirty(session), isFalse);
      await coordinator.close(session);
    },
  );
}

EditorDocumentState _commitTitle(
  EditorHistory history,
  EditorDocumentState state,
  String title,
) {
  history.begin(
    state,
    HistoryTransactionDescriptor(
      operation: HistoryOperationCode.changeSettings,
    ),
  );
  final operation = DocumentOperationResult.success(
    document: state.document.copyWith(title: title),
    affectedScopes: const {DocumentScope.settings},
    summary: DocumentChangeSummary(action: 'change-title'),
  );
  history.addFrom(expectedBase: state.document, operation: operation);
  return history.commit(state).state;
}

EditorDocumentState _commitAssets(
  EditorHistory history,
  EditorDocumentState state,
  ProjectDocument next,
) {
  history.begin(
    state,
    HistoryTransactionDescriptor(operation: HistoryOperationCode.changeAssets),
  );
  history.addFrom(
    expectedBase: state.document,
    operation: DocumentOperationResult.success(
      document: next,
      affectedScopes: const {DocumentScope.assets},
      summary: DocumentChangeSummary(action: 'relink-asset'),
    ),
  );
  return history.commit(state).state;
}

ProjectDocument _document(Uint8List bytes) {
  final assetId = ProjectAssetId('artwork');
  return ProjectDocument(
    id: ProjectId('project'),
    title: 'Project',
    canvas: const ProjectCanvas(width: 1920, height: 1080),
    frameRate: FrameRate.fps30,
    duration: TimelineDuration.fromMicroseconds(1000000),
    artworkAssetId: assetId,
    assets: [
      ProjectAsset(
        id: assetId,
        kind: ProjectAssetKind.artwork,
        originalFileName: 'art.png',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:${sha256.convert(bytes)}',
        mediaType: 'image/png',
        artworkSourceType: ArtworkSourceType.raster,
      ),
    ],
    strokes: const [],
    sections: const [],
    sectionOrder: const [],
    scenes: const [],
    audioTracks: const [],
  );
}

Future<Uint8List> _collect(Stream<Uint8List> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

final class _MemoryContainerStore implements ProjectContainerStore {
  ProjectDocument? openDocument;
  Map<ProjectAssetId, Uint8List> openBytes = {};
  Completer<void>? blockSave;
  Completer<void> saveStarted = Completer<void>();

  @override
  Future<ProjectContainerSession> open(
    ProjectContainerLocation source, {
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  }) async => _MemoryContainerSession(openDocument!, openBytes);

  @override
  Future<void> save({
    required ProjectContainerLocation destination,
    required ProjectDocument document,
    required ProjectAssetSourceCatalog assetSources,
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  }) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await blockSave?.future;
    if (cancellation.isCancelled) {
      throw const ProjectContainerException(
        ProjectContainerFailureCode.cancelled,
        'cancelled',
      );
    }
    for (final asset in document.assets) {
      if (asset.storagePolicy != ProjectAssetStoragePolicy.embedded) continue;
      final source = assetSources.sourceFor(asset.id)!;
      await source.openRead().drain<void>();
    }
  }

  @override
  Future<int> cleanupStaleTemporaryFiles(
    ProjectContainerLocation destination,
  ) async => 0;
}

final class _Cancellation implements ProjectContainerCancellation {
  bool cancelled = false;

  @override
  bool get isCancelled => cancelled;
}

final class _MemoryContainerSession implements ProjectContainerSession {
  _MemoryContainerSession(this.document, this.assets);

  @override
  final ProjectDocument document;
  final Map<ProjectAssetId, Uint8List> assets;

  @override
  Stream<Uint8List> openAsset(ProjectAssetId assetId) async* {
    yield assets[assetId]!;
  }

  @override
  Future<void> close() async {}
}
