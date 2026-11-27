import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

final class FileEditorAssetStagingStore implements EditorAssetStagingStore {
  static final Set<String> _locallyOwnedDirectories = {};
  FileEditorAssetStagingStore(
    this._root, {
    DateTime Function()? now,
    this.staleAge = const Duration(hours: 24),
    this.onSnapshotChunk,
  }) : _now = now ?? DateTime.now;

  final Directory _root;
  final DateTime Function() _now;
  final Duration staleAge;
  final FutureOr<void> Function(File source, int bytesRead)? onSnapshotChunk;
  final Map<EditorSessionId, _StagingSession> _sessions = {};

  @override
  Future<void> createSession(EditorSessionId sessionId) async {
    _validateComponent(sessionId.value, 'session ID');
    if (_sessions.containsKey(sessionId)) return;
    final directoryName = sessionId.value.startsWith('session-')
        ? sessionId.value
        : 'session-${sessionId.value}';
    final directory = Directory('${_root.path}/$directoryName');
    await directory.create(recursive: true);
    final ownership = File(
      '${directory.path}/.owner.lock',
    ).openSync(mode: FileMode.append);
    try {
      ownership.lockSync(FileLock.exclusive);
    } catch (_) {
      ownership.closeSync();
      throw const AssetStagingException(
        AssetStagingFailureCode.sessionMismatch,
        'The staging session directory is owned by another process.',
      );
    }
    _sessions[sessionId] = _StagingSession(directory, ownership);
    _locallyOwnedDirectories.add(directory.absolute.path);
  }

  @override
  Future<void> stageEmbedded(StageEmbeddedAssetRequest request) async {
    final session = _session(request.sessionId);
    _requireCanonicalHash(request.asset);
    if (request.asset.storagePolicy != ProjectAssetStoragePolicy.embedded) {
      throw const AssetStagingException(
        AssetStagingFailureCode.invalidSource,
        'Only embedded assets can be copied into staging.',
      );
    }
    _validateComponent(request.asset.id.value, 'asset ID');
    if (session.assets.containsKey(request.asset.id)) {
      throw AssetStagingException(
        AssetStagingFailureCode.invalidSource,
        'Asset ${request.asset.id} is already staged.',
      );
    }
    final expectedLength = await request.source.length();
    final target = File(
      '${session.directory.path}/${request.asset.id.value}.asset',
    );
    final temporary = File('${target.path}.tmp');
    IOSink? sink;
    try {
      sink = temporary.openWrite();
      final digest = _SingleDigestSink();
      final hashInput = sha256.startChunkedConversion(digest);
      var written = 0;
      await for (final chunk in request.source.openRead()) {
        written += chunk.length;
        hashInput.add(chunk);
        sink.add(chunk);
      }
      hashInput.close();
      await sink.flush();
      await sink.close();
      sink = null;
      final actualHash = 'sha256:${digest.single}';
      if (written != expectedLength ||
          actualHash != request.asset.contentHash) {
        throw AssetStagingException(
          actualHash != request.asset.contentHash
              ? AssetStagingFailureCode.hashMismatch
              : AssetStagingFailureCode.sourceChanged,
          'Embedded asset ${request.asset.id} changed or failed hash validation.',
        );
      }
      if (await target.exists()) await target.delete();
      await temporary.rename(target.path);
      session.assets[request.asset.id] = _StagedAssetRecord.embedded(
        request.asset,
        target,
        written,
      );
    } catch (error) {
      await sink?.close();
      if (await temporary.exists()) await temporary.delete();
      if (error is AssetStagingException) rethrow;
      throw AssetStagingException(
        AssetStagingFailureCode.storageFailure,
        'Embedded asset ${request.asset.id} could not be staged.',
        error,
      );
    }
  }

  @override
  Future<void> registerExternal(RegisterExternalAssetRequest request) async {
    final session = _session(request.sessionId);
    _requireCanonicalHash(request.asset);
    final locator = request.asset.externalLocator;
    if (request.asset.storagePolicy != ProjectAssetStoragePolicy.external ||
        locator == null ||
        locator.pathHint.trim().isEmpty) {
      throw const AssetStagingException(
        AssetStagingFailureCode.invalidSource,
        'An external asset requires a validated locator.',
      );
    }
    final source = File(locator.pathHint);
    if (session.assets.containsKey(request.asset.id)) {
      throw AssetStagingException(
        AssetStagingFailureCode.invalidSource,
        'Asset ${request.asset.id} is already registered.',
      );
    }
    if (!await source.exists()) {
      throw AssetStagingException(
        AssetStagingFailureCode.missingAsset,
        'External asset ${request.asset.id} is unavailable.',
      );
    }
    session.assets[request.asset.id] = _StagedAssetRecord.external(
      request.asset,
      source,
    );
  }

  @override
  Future<StagedAssetLease> acquire({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  }) async {
    final session = _session(sessionId);
    final record = session.assets[assetId];
    if (record == null) {
      throw AssetStagingException(
        AssetStagingFailureCode.missingAsset,
        'Asset $assetId does not belong to session ${sessionId.value}.',
      );
    }
    final snapshot = await _validateReadable(record);
    record.retain(kind);
    return _FileStagedAssetLease(
      store: this,
      sessionId: sessionId,
      record: record,
      kind: kind,
      length: snapshot.length,
      modified: snapshot.modified,
    );
  }

  @override
  Future<StagedAssetLease> acquireVerifiedSnapshot({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
    AssetSnapshotCancellation cancellation = const NeverCancelAssetSnapshot(),
  }) async {
    final session = _session(sessionId);
    final record = session.assets[assetId];
    if (record == null) {
      throw AssetStagingException(
        AssetStagingFailureCode.missingAsset,
        'Asset $assetId is unavailable.',
      );
    }
    if (record.embedded) {
      return acquire(sessionId: sessionId, assetId: assetId, kind: kind);
    }
    final operationDirectory = Directory('${session.directory.path}/verified');
    await operationDirectory.create();
    final nonce =
        '${DateTime.now().microsecondsSinceEpoch}-${session.nextSnapshot++}';
    final temporary = File(
      '${operationDirectory.path}/${assetId.value}-$nonce.tmp',
    );
    final snapshot = File(
      '${operationDirectory.path}/${assetId.value}-$nonce.snapshot',
    );
    IOSink? sink;
    RandomAccessFile? sourceHandle;
    try {
      final before = await record.file.stat();
      sourceHandle = await record.file.open();
      sink = temporary.openWrite();
      final digestSink = _SingleDigestSink();
      final hashInput = sha256.startChunkedConversion(digestSink);
      var written = 0;
      while (true) {
        if (cancellation.isCancelled) {
          throw const AssetStagingException(
            AssetStagingFailureCode.cancelled,
            'Verified snapshot was cancelled.',
          );
        }
        final chunk = await sourceHandle.read(64 * 1024);
        if (chunk.isEmpty) break;
        written += chunk.length;
        await onSnapshotChunk?.call(record.file, written);
        hashInput.add(chunk);
        sink.add(chunk);
      }
      hashInput.close();
      await sink.flush();
      await sink.close();
      sink = null;
      await sourceHandle.close();
      sourceHandle = null;
      final after = await record.file.stat();
      if (before.size != after.size ||
          before.modified != after.modified ||
          written != before.size) {
        throw AssetStagingException(
          AssetStagingFailureCode.externalAssetChangedDuringRead,
          'External asset $assetId changed while its verified snapshot was created.',
        );
      }
      if ('sha256:${digestSink.single}' != record.asset.contentHash) {
        throw AssetStagingException(
          AssetStagingFailureCode.externalAssetContentMismatch,
          'External asset $assetId does not match its persisted content hash.',
        );
      }
      await temporary.rename(snapshot.path);
      record.retain(kind);
      return _VerifiedFileLease(
        store: this,
        sessionId: sessionId,
        record: record,
        kind: kind,
        snapshot: snapshot,
        length: written,
      );
    } catch (error) {
      await sink?.close();
      await sourceHandle?.close();
      if (await temporary.exists()) await temporary.delete();
      if (await snapshot.exists()) await snapshot.delete();
      if (error is AssetStagingException) rethrow;
      throw AssetStagingException(
        AssetStagingFailureCode.storageFailure,
        'Could not create verified snapshot for $assetId.',
        error,
      );
    }
  }

  @override
  void retain({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  }) {
    final record = _session(sessionId).assets[assetId];
    if (record == null) {
      throw AssetStagingException(
        AssetStagingFailureCode.missingAsset,
        'Asset $assetId cannot be retained before staging.',
      );
    }
    record.retain(kind);
  }

  @override
  void releaseReference({
    required EditorSessionId sessionId,
    required ProjectAssetId assetId,
    required StagedAssetReferenceKind kind,
  }) {
    final session = _sessions[sessionId];
    final record = session?.assets[assetId];
    if (session == null || record == null) return;
    record.release(kind);
    _cleanupIfUnusedSync(sessionId, session, record);
  }

  @override
  Future<void> disposeSession(EditorSessionId sessionId) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    session.disposed = true;
    for (final record in session.assets.values.toList()) {
      await _cleanupIfUnused(sessionId, session, record);
    }
    await _deleteSessionIfEmpty(sessionId, session);
  }

  @override
  Future<int> cleanupStaleSessions() async {
    if (!await _root.exists()) return 0;
    final cutoff = _now().subtract(staleAge);
    var removed = 0;
    await for (final entity in _root.list(followLinks: false)) {
      if (entity is! Directory ||
          !RegExp(
            r'^session-[A-Za-z0-9._-]+$',
          ).hasMatch(entity.uri.pathSegments.where((e) => e.isNotEmpty).last) ||
          _sessions.values.any(
            (session) => session.directory.path == entity.path,
          ) ||
          _locallyOwnedDirectories.contains(entity.absolute.path)) {
        continue;
      }
      if (!(await entity.stat()).modified.isBefore(cutoff)) continue;
      final lockFile = File('${entity.path}/.owner.lock');
      if (!await lockFile.exists()) continue;
      RandomAccessFile? ownership;
      try {
        ownership = await lockFile.open(mode: FileMode.append);
        await ownership.lock(FileLock.exclusive);
        await entity.delete(recursive: true);
        removed++;
      } on FileSystemException {
        // A live owner or unsupported locking means cleanup must be skipped.
      } finally {
        try {
          await ownership?.unlock();
        } catch (_) {}
        await ownership?.close();
      }
    }
    return removed;
  }

  _StagingSession _session(EditorSessionId id) {
    final session = _sessions[id];
    if (session == null) {
      throw AssetStagingException(
        AssetStagingFailureCode.sessionMismatch,
        'Unknown staging session ${id.value}.',
      );
    }
    if (session.disposed) {
      throw AssetStagingException(
        AssetStagingFailureCode.sessionClosed,
        'Staging session ${id.value} is closing.',
      );
    }
    return session;
  }

  Future<_FileSnapshot> _validateReadable(_StagedAssetRecord record) async {
    if (!await record.file.exists()) {
      throw AssetStagingException(
        AssetStagingFailureCode.missingAsset,
        'Asset ${record.asset.id} is unavailable.',
      );
    }
    final before = await record.file.stat();
    final digest = await sha256.bind(record.file.openRead()).first;
    final after = await record.file.stat();
    if (before.size != after.size || before.modified != after.modified) {
      throw AssetStagingException(
        AssetStagingFailureCode.sourceChanged,
        'Asset ${record.asset.id} changed while it was acquired.',
      );
    }
    if ('sha256:$digest' != record.asset.contentHash) {
      throw AssetStagingException(
        AssetStagingFailureCode.hashMismatch,
        'Asset ${record.asset.id} no longer matches its content hash.',
      );
    }
    return _FileSnapshot(after.size, after.modified);
  }

  Future<void> _releaseLease(
    EditorSessionId sessionId,
    _StagedAssetRecord record,
    StagedAssetReferenceKind kind,
  ) async {
    final session = _sessions[sessionId];
    if (session == null) return;
    record.release(kind);
    await _cleanupIfUnused(sessionId, session, record);
  }

  Future<void> _cleanupIfUnused(
    EditorSessionId sessionId,
    _StagingSession session,
    _StagedAssetRecord record,
  ) async {
    if (record.referenceCount > 0) return;
    session.assets.remove(record.asset.id);
    if (record.embedded && await record.file.exists()) {
      await record.file.delete();
    }
    await _deleteSessionIfEmpty(sessionId, session);
  }

  void _cleanupIfUnusedSync(
    EditorSessionId sessionId,
    _StagingSession session,
    _StagedAssetRecord record,
  ) {
    if (record.referenceCount > 0) return;
    session.assets.remove(record.asset.id);
    if (record.embedded && record.file.existsSync()) {
      record.file.deleteSync();
    }
    if (session.disposed && session.assets.isEmpty) {
      _sessions.remove(sessionId);
      _locallyOwnedDirectories.remove(session.directory.absolute.path);
      session.ownership.unlockSync();
      session.ownership.closeSync();
      if (session.directory.existsSync()) {
        session.directory.deleteSync(recursive: true);
      }
    }
  }

  Future<void> _deleteSessionIfEmpty(
    EditorSessionId sessionId,
    _StagingSession session,
  ) async {
    if (!session.disposed ||
        session.assets.isNotEmpty ||
        !identical(_sessions[sessionId], session)) {
      return;
    }
    _sessions.remove(sessionId);
    _locallyOwnedDirectories.remove(session.directory.absolute.path);
    session.ownership.unlockSync();
    session.ownership.closeSync();
    if (await session.directory.exists()) {
      await session.directory.delete(recursive: true);
    }
  }

  void _requireCanonicalHash(ProjectAsset asset) {
    if (!RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(asset.contentHash)) {
      throw AssetStagingException(
        AssetStagingFailureCode.invalidSource,
        'Asset ${asset.id} requires a canonical SHA-256 hash.',
      );
    }
  }

  void _validateComponent(String value, String label) {
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value)) {
      throw AssetStagingException(
        AssetStagingFailureCode.invalidSource,
        'Invalid $label.',
      );
    }
  }
}

final class _StagingSession {
  _StagingSession(this.directory, this.ownership);

  final Directory directory;
  final RandomAccessFile ownership;
  int nextSnapshot = 0;
  final Map<ProjectAssetId, _StagedAssetRecord> assets = {};
  bool disposed = false;
}

final class _VerifiedFileLease implements StagedAssetLease {
  _VerifiedFileLease({
    required this.store,
    required this.sessionId,
    required this.record,
    required this.kind,
    required this.snapshot,
    required this.length,
  });
  final FileEditorAssetStagingStore store;
  final _StagedAssetRecord record;
  final File snapshot;
  bool _released = false;
  @override
  ProjectAssetId get assetId => record.asset.id;
  @override
  final EditorSessionId sessionId;
  @override
  final StagedAssetReferenceKind kind;
  @override
  final int length;
  @override
  Stream<Uint8List> openRead() async* {
    if (_released) {
      throw const AssetStagingException(
        AssetStagingFailureCode.sessionClosed,
        'The verified lease is released.',
      );
    }
    await for (final chunk in snapshot.openRead()) {
      yield Uint8List.fromList(chunk);
    }
  }

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    if (await snapshot.exists()) await snapshot.delete();
    await store._releaseLease(sessionId, record, kind);
  }
}

final class _StagedAssetRecord {
  _StagedAssetRecord.embedded(this.asset, this.file, this.knownLength)
    : embedded = true;

  _StagedAssetRecord.external(this.asset, this.file)
    : embedded = false,
      knownLength = null;

  final ProjectAsset asset;
  final File file;
  final bool embedded;
  final int? knownLength;
  final Map<StagedAssetReferenceKind, int> references = {};

  int get referenceCount => references.values.fold(0, (a, b) => a + b);

  void retain(StagedAssetReferenceKind kind) {
    references[kind] = (references[kind] ?? 0) + 1;
  }

  void release(StagedAssetReferenceKind kind) {
    final count = references[kind] ?? 0;
    if (count <= 1) {
      references.remove(kind);
    } else {
      references[kind] = count - 1;
    }
  }
}

final class _FileSnapshot {
  const _FileSnapshot(this.length, this.modified);

  final int length;
  final DateTime modified;
}

final class _FileStagedAssetLease implements StagedAssetLease {
  _FileStagedAssetLease({
    required this._store,
    required this.sessionId,
    required this._record,
    required this.kind,
    required this.length,
    required this._modified,
  });

  final FileEditorAssetStagingStore _store;
  final _StagedAssetRecord _record;
  final DateTime _modified;
  bool _released = false;

  @override
  ProjectAssetId get assetId => _record.asset.id;

  @override
  final EditorSessionId sessionId;

  @override
  final StagedAssetReferenceKind kind;

  @override
  final int length;

  @override
  Stream<Uint8List> openRead() async* {
    if (_released) {
      throw const AssetStagingException(
        AssetStagingFailureCode.sessionClosed,
        'The asset lease is released.',
      );
    }
    final stat = await _record.file.stat();
    if (stat.size != length || stat.modified != _modified) {
      throw AssetStagingException(
        AssetStagingFailureCode.sourceChanged,
        'Asset ${_record.asset.id} changed after acquisition.',
      );
    }
    await for (final chunk in _record.file.openRead()) {
      yield Uint8List.fromList(chunk);
    }
  }

  @override
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _store._releaseLease(sessionId, _record, kind);
  }
}

final class _SingleDigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get single {
    final value = _digest;
    if (value == null) throw StateError('SHA-256 conversion did not finish.');
    return value;
  }

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}
