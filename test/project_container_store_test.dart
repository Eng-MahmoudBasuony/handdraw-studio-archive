import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/project_document_container_service.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_limits.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/asset_entry_naming_policy.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/atomic_file_replacer.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/file_project_asset_source.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/koni_project_container_store.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/raw_zip_entry_scanner.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('handdraw-store-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'save/open round-trip streams exact assets and closes all handles',
    () async {
      final fixture = _fixture();
      final destination = File('${directory.path}/lesson.handdraw');
      final progress = <ProjectContainerStage>[];
      const store = KoniProjectContainerStore();

      await store.save(
        destination: ProjectContainerLocation(destination.path),
        document: fixture.document,
        assetSources: fixture.catalog,
        onProgress: (value) => progress.add(value.stage),
      );

      expect(await destination.openRead(0, 2).first, [0x50, 0x4b]);
      final records = await const RawZipEntryScanner().scan(destination);
      expect(records.map((entry) => entry.path), {
        'manifest.json',
        'assets/artwork/artwork-a.svg',
        'assets/hands/hand-a.png',
      });
      expect(
        records
            .singleWhere((entry) => entry.path.endsWith('.svg'))
            .compressionMethod,
        8,
      );
      expect(
        records
            .singleWhere((entry) => entry.path.endsWith('.png'))
            .compressionMethod,
        0,
      );

      final session = await store.open(
        ProjectContainerLocation(destination.path),
      );
      expect(session.document.id, fixture.document.id);
      expect(
        session.document.assets.map((asset) => asset.id),
        fixture.document.assets.map((asset) => asset.id),
      );
      expect(
        await _collect(session.openAsset(ProjectAssetId('artwork-a'))),
        fixture.artworkBytes,
      );
      expect(
        await _collect(session.openAsset(ProjectAssetId('hand-a'))),
        fixture.handBytes,
      );
      await session.close();
      await destination.rename('${destination.path}.closed');

      expect(
        progress,
        containsAllInOrder([
          ProjectContainerStage.validating,
          ProjectContainerStage.writing,
          ProjectContainerStage.verifying,
          ProjectContainerStage.replacing,
        ]),
      );
    },
  );

  test(
    'development manifest stores metadata without payloads or containerPath',
    () async {
      final fixture = _fixture();
      final destination = File('${directory.path}/metadata.handdraw');
      const store = KoniProjectContainerStore();
      await store.save(
        destination: ProjectContainerLocation(destination.path),
        document: fixture.document,
        assetSources: fixture.catalog,
      );

      final session = await store.open(
        ProjectContainerLocation(destination.path),
      );
      expect(session.document.assets, hasLength(2));
      await session.close();

      final bytes = await destination.readAsBytes();
      final printable = ascii.decode(bytes, allowInvalid: true);
      expect(printable, isNot(contains('<svg')));
      expect(printable, isNot(contains('containerPath')));
      expect(printable.toLowerCase(), isNot(contains('base64')));
    },
  );

  test(
    'content mismatch preserves existing destination and removes temp',
    () async {
      final fixture = _fixture(
        expectedArtworkHash: _hash(utf8.encode('wrong')),
      );
      final destination = File('${directory.path}/existing.handdraw');
      await destination.writeAsString('last known good');

      await expectLater(
        const KoniProjectContainerStore().save(
          destination: ProjectContainerLocation(destination.path),
          document: fixture.document,
          assetSources: fixture.catalog,
        ),
        throwsA(_failure(ProjectContainerFailureCode.contentMismatch)),
      );

      expect(await destination.readAsString(), 'last known good');
      expect(await _temporaryFilesFor(destination), isEmpty);
    },
  );

  test(
    'application Save/Open publishes state only after verified open',
    () async {
      final fixture = _fixture();
      final destination = ProjectContainerLocation(
        '${directory.path}/application.handdraw',
      );
      const store = KoniProjectContainerStore();
      const service = ProjectDocumentContainerService(store: store);

      await service.save(
        destination: destination,
        state: EditorDocumentState(document: fixture.document),
        assetSources: fixture.catalog,
      );
      final opened = await service.open(destination);

      expect(opened.state.document.id, fixture.document.id);
      expect(opened.state.revision.value, 0);
      await opened.session.close();
    },
  );

  test(
    'atomic replacement failure preserves old project and cleans temp',
    () async {
      final fixture = _fixture();
      final destination = File('${directory.path}/existing.handdraw');
      await destination.writeAsString('old project');
      final store = KoniProjectContainerStore(
        atomicReplacer: const _FailingAtomicReplacer(),
      );

      await expectLater(
        store.save(
          destination: ProjectContainerLocation(destination.path),
          document: fixture.document,
          assetSources: fixture.catalog,
        ),
        throwsA(_failure(ProjectContainerFailureCode.storageFailure)),
      );

      expect(await destination.readAsString(), 'old project');
      expect(await _temporaryFilesFor(destination), isEmpty);
    },
  );

  test(
    'unsupported atomic platform fails before directory or source access',
    () async {
      final fixture = _fixture();
      final source = _TrackingSource(fixture.artworkBytes);
      final destination = File(
        '${directory.path}/must-not-exist/project.handdraw',
      );
      final store = KoniProjectContainerStore(
        atomicReplacer: const _UnsupportedAtomicReplacer(),
      );

      await expectLater(
        store.save(
          destination: ProjectContainerLocation(destination.path),
          document: fixture.document,
          assetSources: MapProjectAssetSourceCatalog({
            ProjectAssetId('artwork-a'): source,
            ProjectAssetId('hand-a'): _MemorySource(fixture.handBytes),
          }),
        ),
        throwsA(isA<UnsupportedAtomicReplacementPlatform>()),
      );

      expect(source.lengthRead, isFalse);
      expect(source.streamOpened, isFalse);
      expect(await destination.parent.exists(), isFalse);
    },
  );

  test(
    'qualified replacement atomically overwrites an existing project',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('Windows is blocked pending the ReplaceFileW adapter.');
        return;
      }
      final fixture = _fixture();
      final destination = File('${directory.path}/overwrite.handdraw');
      await destination.writeAsString('old project');

      await const KoniProjectContainerStore().save(
        destination: ProjectContainerLocation(destination.path),
        document: fixture.document,
        assetSources: fixture.catalog,
      );

      expect(await destination.openRead(0, 2).first, [0x50, 0x4b]);
      expect(await _temporaryFilesFor(destination), isEmpty);
    },
  );

  test(
    'cancellation during Deflate/SHA preserves the saved checkpoint',
    () async {
      final fixture = _fixture();
      final cancellation = _MutableCancellation();
      final destination = File('${directory.path}/cancelled.handdraw');
      await destination.writeAsString('saved checkpoint');
      final source = _MemorySource(
        fixture.artworkBytes,
        chunkSize: 4,
        afterChunk: (index) {
          if (index == 1) cancellation.cancel();
        },
      );
      final catalog = MapProjectAssetSourceCatalog({
        ProjectAssetId('artwork-a'): source,
        ProjectAssetId('hand-a'): _MemorySource(fixture.handBytes),
      });

      await expectLater(
        const KoniProjectContainerStore().save(
          destination: ProjectContainerLocation(destination.path),
          document: fixture.document,
          assetSources: catalog,
          cancellation: cancellation,
        ),
        throwsA(_failure(ProjectContainerFailureCode.cancelled)),
      );

      expect(await destination.readAsString(), 'saved checkpoint');
      expect(await _temporaryFilesFor(destination), isEmpty);
    },
  );

  test(
    'cancellation before the first entry creates no temporary file',
    () async {
      final fixture = _fixture();
      final cancellation = _MutableCancellation()..cancel();
      final destination = File(
        '${directory.path}/cancel-before-entry.handdraw',
      );
      await destination.writeAsString('saved checkpoint');

      await expectLater(
        const KoniProjectContainerStore().save(
          destination: ProjectContainerLocation(destination.path),
          document: fixture.document,
          assetSources: fixture.catalog,
          cancellation: cancellation,
        ),
        throwsA(_failure(ProjectContainerFailureCode.cancelled)),
      );

      expect(await destination.readAsString(), 'saved checkpoint');
      expect(await _temporaryFilesFor(destination), isEmpty);
    },
  );

  test(
    'cancellation during a Store entry preserves the saved checkpoint',
    () async {
      final fixture = _fixture();
      final cancellation = _MutableCancellation();
      final destination = File('${directory.path}/cancel-store.handdraw');
      await destination.writeAsString('saved checkpoint');
      final catalog = MapProjectAssetSourceCatalog({
        ProjectAssetId('artwork-a'): _MemorySource(fixture.artworkBytes),
        ProjectAssetId('hand-a'): _MemorySource(
          fixture.handBytes,
          chunkSize: 4,
          afterChunk: (index) {
            if (index == 1) cancellation.cancel();
          },
        ),
      });

      await expectLater(
        const KoniProjectContainerStore().save(
          destination: ProjectContainerLocation(destination.path),
          document: fixture.document,
          assetSources: catalog,
          cancellation: cancellation,
        ),
        throwsA(_failure(ProjectContainerFailureCode.cancelled)),
      );

      expect(await destination.readAsString(), 'saved checkpoint');
      expect(await _temporaryFilesFor(destination), isEmpty);
    },
  );

  test(
    'cancellation during verification SHA closes the archive handles',
    () async {
      final fixture = _fixture();
      final cancellation = _MutableCancellation();
      final destination = File('${directory.path}/cancel-verify.handdraw');
      await destination.writeAsString('saved checkpoint');

      await expectLater(
        const KoniProjectContainerStore().save(
          destination: ProjectContainerLocation(destination.path),
          document: fixture.document,
          assetSources: fixture.catalog,
          cancellation: cancellation,
          onProgress: (progress) {
            if (progress.stage == ProjectContainerStage.verifying &&
                progress.completedBytes > 0) {
              cancellation.cancel();
            }
          },
        ),
        throwsA(_failure(ProjectContainerFailureCode.cancelled)),
      );

      expect(await destination.readAsString(), 'saved checkpoint');
      expect(await _temporaryFilesFor(destination), isEmpty);
    },
  );

  test(
    'cancellation after writer close and before replace preserves old file',
    () async {
      final fixture = _fixture();
      final cancellation = _MutableCancellation();
      final destination = File('${directory.path}/cancel-replace.handdraw');
      await destination.writeAsString('saved checkpoint');

      await expectLater(
        const KoniProjectContainerStore().save(
          destination: ProjectContainerLocation(destination.path),
          document: fixture.document,
          assetSources: fixture.catalog,
          cancellation: cancellation,
          onProgress: (progress) {
            if (progress.stage == ProjectContainerStage.replacing) {
              cancellation.cancel();
            }
          },
        ),
        throwsA(_failure(ProjectContainerFailureCode.cancelled)),
      );

      expect(await destination.readAsString(), 'saved checkpoint');
      expect(await _temporaryFilesFor(destination), isEmpty);
    },
  );

  test('same-size source mutation is detected by streamed SHA-256', () async {
    final fixture = _fixture();
    final destination = File('${directory.path}/mutated-source.handdraw');
    await destination.writeAsString('saved checkpoint');
    final catalog = MapProjectAssetSourceCatalog({
      ProjectAssetId('artwork-a'): _SameLengthMutatingSource(
        fixture.artworkBytes,
      ),
      ProjectAssetId('hand-a'): _MemorySource(fixture.handBytes),
    });

    await expectLater(
      const KoniProjectContainerStore().save(
        destination: ProjectContainerLocation(destination.path),
        document: fixture.document,
        assetSources: catalog,
      ),
      throwsA(_failure(ProjectContainerFailureCode.contentMismatch)),
    );

    expect(await destination.readAsString(), 'saved checkpoint');
    expect(await _temporaryFilesFor(destination), isEmpty);
  });

  test(
    'runtime guards reject entry count and size before opening streams',
    () async {
      final fixture = _fixture();
      final destination = ProjectContainerLocation(
        '${directory.path}/guarded.handdraw',
      );
      final countStore = KoniProjectContainerStore(
        limits: const ProjectContainerLimits(maxEntryCount: 2),
      );
      await expectLater(
        countStore.save(
          destination: destination,
          document: fixture.document,
          assetSources: fixture.catalog,
        ),
        throwsA(_failure(ProjectContainerFailureCode.limitExceeded)),
      );

      final oversizedCatalog = MapProjectAssetSourceCatalog({
        ProjectAssetId('artwork-a'): const _DeclaredLengthSource(101),
        ProjectAssetId('hand-a'): _MemorySource(fixture.handBytes),
      });
      final sizeStore = KoniProjectContainerStore(
        limits: const ProjectContainerLimits(maxEntryBytes: 100),
      );
      await expectLater(
        sizeStore.save(
          destination: destination,
          document: fixture.document,
          assetSources: oversizedCatalog,
        ),
        throwsA(_failure(ProjectContainerFailureCode.limitExceeded)),
      );
    },
  );

  test('open rejects corrupt containers with typed failure', () async {
    final corrupt = File('${directory.path}/corrupt.handdraw');
    await corrupt.writeAsString('not a ZIP');

    await expectLater(
      const KoniProjectContainerStore().open(
        ProjectContainerLocation(corrupt.path),
      ),
      throwsA(_failure(ProjectContainerFailureCode.invalidContainer)),
    );
  });

  test(
    'CRC corruption is rejected before a document session is published',
    () async {
      final fixture = _fixture();
      final destination = File('${directory.path}/crc.handdraw');
      const store = KoniProjectContainerStore();
      await store.save(
        destination: ProjectContainerLocation(destination.path),
        document: fixture.document,
        assetSources: fixture.catalog,
      );
      await _corruptStoredEntry(destination, 'assets/hands/hand-a.png');

      await expectLater(
        store.open(ProjectContainerLocation(destination.path)),
        throwsA(_failure(ProjectContainerFailureCode.invalidContainer)),
      );
    },
  );

  test('asset source failures use stable public error mapping', () async {
    final fixture = _fixture();
    final catalog = MapProjectAssetSourceCatalog({
      ProjectAssetId('artwork-a'): const _ThrowingSource(),
      ProjectAssetId('hand-a'): _MemorySource(fixture.handBytes),
    });

    await expectLater(
      const KoniProjectContainerStore().save(
        destination: ProjectContainerLocation(
          '${directory.path}/source-failure.handdraw',
        ),
        document: fixture.document,
        assetSources: catalog,
      ),
      throwsA(_failure(ProjectContainerFailureCode.storageFailure)),
    );
  });

  test('cleanup removes only stale temporary siblings', () async {
    final destination = File('${directory.path}/lesson.handdraw');
    final stale = File('${destination.path}.tmp.1.1');
    final fresh = File('${destination.path}.tmp.1.2');
    final unrelated = File('${directory.path}/other.tmp.1.1');
    await stale.writeAsString('stale');
    await fresh.writeAsString('fresh');
    await unrelated.writeAsString('keep');
    await stale.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );

    final removed = await const KoniProjectContainerStore()
        .cleanupStaleTemporaryFiles(ProjectContainerLocation(destination.path));

    expect(removed, 1);
    expect(await stale.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(await unrelated.exists(), isTrue);
  });

  test('container dependencies stay pinned behind infrastructure boundary', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('koni_archive_core: 0.9.0'));
    expect(pubspec, contains('koni_zip: 0.9.0'));
    expect(pubspec, contains('crypto: 3.0.7'));

    for (final root in [
      Directory('lib/features/project/domain'),
      Directory('lib/features/project/application'),
    ]) {
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        expect(
          file.readAsStringSync(),
          isNot(contains('package:koni_')),
          reason: file.path,
        );
      }
    }
  });

  test('production container adapter has no whole-file read shortcut', () {
    final directory = Directory(
      'lib/features/project/infrastructure/container',
    );
    for (final file in directory.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final source = file.readAsStringSync();
      expect(source, isNot(contains('.readAsBytes(')), reason: file.path);
      expect(source, isNot(contains('.readAsBytesSync(')), reason: file.path);
    }
  });

  test('entry naming is deterministic and independent from filenames', () {
    final fixture = _fixture();
    const naming = AssetEntryNamingPolicy();
    final original = fixture.document.assets.first;
    final renamed = original.copyWith(originalFileName: '../../renamed.exe');

    expect(naming.map(original).path, naming.map(renamed).path);
    expect(naming.map(original).path, 'assets/artwork/artwork-a.svg');
  });
}

Matcher _failure(ProjectContainerFailureCode code) =>
    isA<ProjectContainerException>().having(
      (error) => error.code,
      'code',
      code,
    );

Future<Uint8List> _collect(Stream<Uint8List> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

Future<List<File>> _temporaryFilesFor(File destination) async => destination
    .parent
    .list()
    .where(
      (entity) =>
          entity is File && entity.path.startsWith('${destination.path}.tmp.'),
    )
    .cast<File>()
    .toList();

String _hash(List<int> bytes) => 'sha256:${sha256.convert(bytes)}';

Future<void> _corruptStoredEntry(File file, String path) async {
  final bytes = await file.readAsBytes();
  final name = ascii.encode(path);
  var nameOffset = -1;
  for (var offset = 30; offset <= bytes.length - name.length; offset++) {
    var matches = true;
    for (var index = 0; index < name.length; index++) {
      if (bytes[offset + index] != name[index]) {
        matches = false;
        break;
      }
    }
    if (matches &&
        bytes[offset - 30] == 0x50 &&
        bytes[offset - 29] == 0x4b &&
        bytes[offset - 28] == 0x03 &&
        bytes[offset - 27] == 0x04) {
      nameOffset = offset;
      break;
    }
  }
  if (nameOffset < 0) throw StateError('Local ZIP entry not found: $path');
  final header = nameOffset - 30;
  final extraLength = bytes[header + 28] | (bytes[header + 29] << 8);
  final dataOffset = nameOffset + name.length + extraLength;
  bytes[dataOffset] ^= 0xff;
  await file.writeAsBytes(bytes, flush: true);
}

_ContainerFixture _fixture({String? expectedArtworkHash}) {
  final artworkBytes = Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0L1 1"/></svg>',
    ),
  );
  final handBytes = Uint8List.fromList(
    List<int>.generate(256, (index) => index),
  );
  final artworkId = ProjectAssetId('artwork-a');
  final handId = ProjectAssetId('hand-a');
  final document = ProjectDocument(
    id: ProjectId('project-store-a'),
    title: 'Container fixture',
    canvas: const ProjectCanvas(width: 1920, height: 1080),
    frameRate: FrameRate.fps30,
    duration: TimelineDuration.fromMicroseconds(1000000),
    artworkAssetId: artworkId,
    assets: [
      ProjectAsset(
        id: artworkId,
        kind: ProjectAssetKind.artwork,
        originalFileName: 'drawing.svg',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: expectedArtworkHash ?? _hash(artworkBytes),
        mediaType: 'image/svg+xml',
        artworkSourceType: ArtworkSourceType.svg,
      ),
      ProjectAsset(
        id: handId,
        kind: ProjectAssetKind.hand,
        originalFileName: 'hand.png',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: _hash(handBytes),
        mediaType: 'image/png',
      ),
    ],
    strokes: const [],
    sections: const [],
    sectionOrder: const [],
    scenes: const [],
    audioTracks: const [],
  );
  return _ContainerFixture(
    document,
    artworkBytes,
    handBytes,
    MapProjectAssetSourceCatalog({
      artworkId: _MemorySource(artworkBytes),
      handId: _MemorySource(handBytes),
    }),
  );
}

final class _ContainerFixture {
  const _ContainerFixture(
    this.document,
    this.artworkBytes,
    this.handBytes,
    this.catalog,
  );

  final ProjectDocument document;
  final Uint8List artworkBytes;
  final Uint8List handBytes;
  final ProjectAssetSourceCatalog catalog;
}

final class _MemorySource implements ProjectAssetByteSource {
  const _MemorySource(this.bytes, {this.chunkSize = 32, this.afterChunk});

  final Uint8List bytes;
  final int chunkSize;
  final void Function(int index)? afterChunk;

  @override
  Future<int> length() async => bytes.length;

  @override
  Stream<Uint8List> openRead() async* {
    var index = 0;
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      yield Uint8List.sublistView(bytes, offset, end);
      afterChunk?.call(index++);
    }
  }
}

final class _DeclaredLengthSource implements ProjectAssetByteSource {
  const _DeclaredLengthSource(this.declaredLength);

  final int declaredLength;

  @override
  Future<int> length() async => declaredLength;

  @override
  Stream<Uint8List> openRead() => const Stream.empty();
}

final class _ThrowingSource implements ProjectAssetByteSource {
  const _ThrowingSource();

  @override
  Future<int> length() async => 1;

  @override
  Stream<Uint8List> openRead() => Stream.error(StateError('source failed'));
}

final class _SameLengthMutatingSource implements ProjectAssetByteSource {
  _SameLengthMutatingSource(this.original);

  final Uint8List original;

  @override
  Future<int> length() async => original.length;

  @override
  Stream<Uint8List> openRead() async* {
    final split = original.length ~/ 2;
    yield Uint8List.sublistView(original, 0, split);
    final changed = Uint8List.fromList(original.sublist(split));
    changed[changed.length ~/ 2] ^= 0xff;
    yield changed;
  }
}

final class _TrackingSource implements ProjectAssetByteSource {
  _TrackingSource(this.bytes);

  final Uint8List bytes;
  var lengthRead = false;
  var streamOpened = false;

  @override
  Future<int> length() async {
    lengthRead = true;
    return bytes.length;
  }

  @override
  Stream<Uint8List> openRead() {
    streamOpened = true;
    return Stream.value(bytes);
  }
}

final class _MutableCancellation implements ProjectContainerCancellation {
  var _cancelled = false;

  void cancel() => _cancelled = true;

  @override
  bool get isCancelled => _cancelled;
}

final class _FailingAtomicReplacer implements AtomicFileReplacer {
  const _FailingAtomicReplacer();

  @override
  void ensureSupported() {}

  @override
  Future<void> replace({required File temporary, required File destination}) {
    throw const ProjectContainerException(
      ProjectContainerFailureCode.storageFailure,
      'Injected replacement failure.',
    );
  }
}

final class _UnsupportedAtomicReplacer implements AtomicFileReplacer {
  const _UnsupportedAtomicReplacer();

  @override
  void ensureSupported() {
    throw const UnsupportedAtomicReplacementPlatform('Injected platform.');
  }

  @override
  Future<void> replace({required File temporary, required File destination}) {
    throw StateError('replace must not be reached');
  }
}
