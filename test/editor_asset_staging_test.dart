import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/infrastructure/file_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

void main() {
  late Directory temporary;
  late FileEditorAssetStagingStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('handdraw-staging-test-');
    store = FileEditorAssetStagingStore(temporary);
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'embedded import stages with streaming hash and remains acquirable',
    () async {
      const session = EditorSessionId('session-a');
      final bytes = Uint8List.fromList(
        List.generate(4096, (index) => index % 251),
      );
      final asset = _embedded('asset-a', bytes);
      await store.createSession(session);
      await store.stageEmbedded(
        StageEmbeddedAssetRequest(
          sessionId: session,
          asset: asset,
          source: _MemorySource(bytes, chunkSize: 127),
        ),
      );
      final lease = await store.acquire(
        sessionId: session,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.preview,
      );
      expect(await _collect(lease.openRead()), bytes);
      await lease.release();
    },
  );

  test(
    'preview and export leases survive session close independently',
    () async {
      const session = EditorSessionId('session-leases');
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final asset = _embedded('asset-leases', bytes);
      await store.createSession(session);
      await store.stageEmbedded(
        StageEmbeddedAssetRequest(
          sessionId: session,
          asset: asset,
          source: _MemorySource(bytes),
        ),
      );
      final preview = await store.acquire(
        sessionId: session,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.preview,
      );
      final export = await store.acquire(
        sessionId: session,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.export,
      );
      await store.disposeSession(session);
      await preview.release();
      expect(await _collect(export.openRead()), bytes);
      expect(
        await Directory('${temporary.path}/${session.value}').exists(),
        isTrue,
      );
      await export.release();
      expect(
        await Directory('${temporary.path}/${session.value}').exists(),
        isFalse,
      );
    },
  );

  test(
    'external mismatch and mutation after acquire are typed conflicts',
    () async {
      const session = EditorSessionId('session-external');
      final source = File('${temporary.path}/external.bin');
      await source.writeAsBytes([4, 5, 6]);
      final asset = ProjectAsset(
        id: ProjectAssetId('external'),
        kind: ProjectAssetKind.other,
        originalFileName: 'external.bin',
        storagePolicy: ProjectAssetStoragePolicy.external,
        contentHash: _hash([4, 5, 6]),
        externalLocator: ExternalAssetLocator(pathHint: source.path),
      );
      await store.createSession(session);
      await store.registerExternal(
        RegisterExternalAssetRequest(sessionId: session, asset: asset),
      );
      store.retain(
        sessionId: session,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.activeDocument,
      );
      final lease = await store.acquire(
        sessionId: session,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.preview,
      );
      await source.writeAsBytes([9, 9, 9, 9]);
      await expectLater(
        lease.openRead().drain<void>(),
        throwsA(
          isA<AssetStagingException>().having(
            (error) => error.code,
            'code',
            AssetStagingFailureCode.sourceChanged,
          ),
        ),
      );
      await lease.release();
      await expectLater(
        store.acquire(
          sessionId: session,
          assetId: asset.id,
          kind: StagedAssetReferenceKind.preview,
        ),
        throwsA(
          isA<AssetStagingException>().having(
            (error) => error.code,
            'code',
            AssetStagingFailureCode.hashMismatch,
          ),
        ),
      );
      store.releaseReference(
        sessionId: session,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.activeDocument,
      );
    },
  );

  test(
    'sessions are isolated and cleanup respects live ownership locks',
    () async {
      const first = EditorSessionId('session-first');
      const second = EditorSessionId('session-second');
      final bytes = Uint8List.fromList([7, 8]);
      final asset = _embedded('private', bytes);
      await store.createSession(first);
      await store.createSession(second);
      await store.stageEmbedded(
        StageEmbeddedAssetRequest(
          sessionId: first,
          asset: asset,
          source: _MemorySource(bytes),
        ),
      );
      await expectLater(
        store.acquire(
          sessionId: second,
          assetId: asset.id,
          kind: StagedAssetReferenceKind.preview,
        ),
        throwsA(isA<AssetStagingException>()),
      );
      final competingStore = FileEditorAssetStagingStore(
        temporary,
        now: () => DateTime.now().add(const Duration(days: 3)),
      );
      expect(await competingStore.cleanupStaleSessions(), 0);
      expect(
        await Directory('${temporary.path}/${first.value}').exists(),
        isTrue,
      );

      await store.disposeSession(first);
      await store.disposeSession(second);

      final stale = Directory('${temporary.path}/session-stale-orphan');
      await stale.create();
      await File('${stale.path}/.owner.lock').create();
      final futureStore = FileEditorAssetStagingStore(
        temporary,
        now: () => DateTime.now().add(const Duration(days: 3)),
      );
      expect(await futureStore.cleanupStaleSessions(), 1);
      expect(await stale.exists(), isFalse);
    },
  );

  test(
    'verified external snapshot detects mutation during read even with same size and mtime',
    () async {
      const session = EditorSessionId('session-race');
      final original = Uint8List(128 * 1024)..fillRange(0, 128 * 1024, 7);
      final source = File('${temporary.path}/race.bin');
      await source.writeAsBytes(original);
      final preservedTime = await source.lastModified();
      var mutated = false;
      store = FileEditorAssetStagingStore(
        temporary,
        onSnapshotChunk: (file, read) async {
          if (mutated || read < 64 * 1024) return;
          mutated = true;
          final replacement = Uint8List(128 * 1024)
            ..fillRange(0, 128 * 1024, 9);
          await file.writeAsBytes(replacement, flush: true);
          await file.setLastModified(preservedTime);
        },
      );
      final asset = _external('race', source, _hash(original));
      await store.createSession(session);
      await store.registerExternal(
        RegisterExternalAssetRequest(sessionId: session, asset: asset),
      );
      await expectLater(
        store.acquireVerifiedSnapshot(
          sessionId: session,
          assetId: asset.id,
          kind: StagedAssetReferenceKind.export,
        ),
        throwsA(
          isA<AssetStagingException>().having(
            (e) => e.code,
            'code',
            anyOf(
              AssetStagingFailureCode.externalAssetChangedDuringRead,
              AssetStagingFailureCode.externalAssetContentMismatch,
            ),
          ),
        ),
      );
    },
  );

  test(
    'verified external snapshot rejects content changed before reading',
    () async {
      const session = EditorSessionId('session-before-read');
      final source = File('${temporary.path}/before-read.bin');
      await source.writeAsBytes([1, 2, 3]);
      final asset = _external('before-read', source, _hash([1, 2, 3]));
      await store.createSession(session);
      await store.registerExternal(
        RegisterExternalAssetRequest(sessionId: session, asset: asset),
      );
      await source.writeAsBytes([3, 2, 1]);
      await expectLater(
        store.acquireVerifiedSnapshot(
          sessionId: session,
          assetId: asset.id,
          kind: StagedAssetReferenceKind.export,
        ),
        throwsA(
          isA<AssetStagingException>().having(
            (e) => e.code,
            'code',
            AssetStagingFailureCode.externalAssetContentMismatch,
          ),
        ),
      );
    },
  );

  test('verified snapshot cancellation removes temporary files', () async {
    const session = EditorSessionId('session-cancel-snapshot');
    final bytes = Uint8List(128 * 1024);
    final source = File('${temporary.path}/cancel.bin');
    await source.writeAsBytes(bytes);
    final cancellation = _SnapshotCancellation();
    store = FileEditorAssetStagingStore(
      temporary,
      onSnapshotChunk: (_, _) => cancellation.cancelled = true,
    );
    final asset = _external('cancel', source, _hash(bytes));
    await store.createSession(session);
    await store.registerExternal(
      RegisterExternalAssetRequest(sessionId: session, asset: asset),
    );
    await expectLater(
      store.acquireVerifiedSnapshot(
        sessionId: session,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.save,
        cancellation: cancellation,
      ),
      throwsA(
        isA<AssetStagingException>().having(
          (e) => e.code,
          'code',
          AssetStagingFailureCode.cancelled,
        ),
      ),
    );
    final verified = Directory('${temporary.path}/${session.value}/verified');
    expect(await verified.list().toList(), isEmpty);
  });

  test(
    'save and export verified leases are independent stable snapshots',
    () async {
      const session = EditorSessionId('session-parallel-snapshots');
      final bytes = Uint8List.fromList([1, 4, 9, 16]);
      final source = File('${temporary.path}/parallel.bin');
      await source.writeAsBytes(bytes);
      final asset = _external('parallel', source, _hash(bytes));
      await store.createSession(session);
      await store.registerExternal(
        RegisterExternalAssetRequest(sessionId: session, asset: asset),
      );
      final leases = await Future.wait([
        store.acquireVerifiedSnapshot(
          sessionId: session,
          assetId: asset.id,
          kind: StagedAssetReferenceKind.save,
        ),
        store.acquireVerifiedSnapshot(
          sessionId: session,
          assetId: asset.id,
          kind: StagedAssetReferenceKind.export,
        ),
      ]);
      await source.writeAsBytes([8, 8, 8, 8]);
      expect(await _collect(leases[0].openRead()), bytes);
      expect(await _collect(leases[1].openRead()), bytes);
      await leases[0].release();
      expect(await _collect(leases[1].openRead()), bytes);
      await leases[1].release();
    },
  );

  test(
    'streams a 500MB embedded source without readAsBytes',
    () async {
      const session = EditorSessionId('session-large');
      const length = 500 * 1024 * 1024;
      final pattern = Uint8List(1024 * 1024);
      final digest = _hashRepeated(pattern, 500);
      final asset = ProjectAsset(
        id: ProjectAssetId('large'),
        kind: ProjectAssetKind.other,
        originalFileName: 'large.bin',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: digest,
      );
      await store.createSession(session);
      await store.stageEmbedded(
        StageEmbeddedAssetRequest(
          sessionId: session,
          asset: asset,
          source: _GeneratedSource(length, pattern),
        ),
      );
    },
    skip: !const bool.fromEnvironment('HANDDRAW_RUN_500MB_STAGING'),
  );
}

ProjectAsset _embedded(String id, Uint8List bytes) => ProjectAsset(
  id: ProjectAssetId(id),
  kind: ProjectAssetKind.other,
  originalFileName: '$id.bin',
  storagePolicy: ProjectAssetStoragePolicy.embedded,
  contentHash: _hash(bytes),
);

ProjectAsset _external(String id, File file, String hash) => ProjectAsset(
  id: ProjectAssetId(id),
  kind: ProjectAssetKind.other,
  originalFileName: '$id.bin',
  storagePolicy: ProjectAssetStoragePolicy.external,
  contentHash: hash,
  externalLocator: ExternalAssetLocator(pathHint: file.path),
);

final class _SnapshotCancellation implements AssetSnapshotCancellation {
  bool cancelled = false;
  @override
  bool get isCancelled => cancelled;
}

String _hash(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

String _hashRepeated(Uint8List pattern, int count) {
  final sink = _DigestSink();
  final input = sha256.startChunkedConversion(sink);
  for (var index = 0; index < count; index++) {
    input.add(pattern);
  }
  input.close();
  return 'sha256:${sink.value}';
}

Future<Uint8List> _collect(Stream<Uint8List> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

final class _MemorySource implements EditorAssetStreamSource {
  const _MemorySource(this.bytes, {this.chunkSize = 1024});

  final Uint8List bytes;
  final int chunkSize;

  @override
  Future<int> length() async => bytes.length;

  @override
  Stream<Uint8List> openRead() async* {
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      yield Uint8List.sublistView(
        bytes,
        offset,
        (offset + chunkSize).clamp(0, bytes.length),
      );
    }
  }
}

final class _GeneratedSource implements EditorAssetStreamSource {
  const _GeneratedSource(this.byteLength, this.pattern);

  final int byteLength;
  final Uint8List pattern;

  @override
  Future<int> length() async => byteLength;

  @override
  Stream<Uint8List> openRead() async* {
    for (var written = 0; written < byteLength; written += pattern.length) {
      yield pattern;
    }
  }
}

final class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value => _digest!;

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}
