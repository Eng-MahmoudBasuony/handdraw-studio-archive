import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_limits.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/koni_project_container_store.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:koni_archive_core/io.dart';
import 'package:koni_zip/koni_zip.dart';

void main() {
  late Directory directory;
  late Uint8List assetBytes;
  late ProjectDocument document;
  late Uint8List manifestBytes;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('handdraw-consistency-');
    assetBytes = Uint8List.fromList(utf8.encode('<svg><path/></svg>'));
    document = _document(assetBytes);
    manifestBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(const DevelopmentProjectManifestCodec().encode(document)),
      ),
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'one declared embedded asset maps to exactly one deterministic entry',
    () async {
      final file = File('${directory.path}/valid.handdraw');
      await _writeContainer(file, manifestBytes, {
        'assets/artwork/artwork-a.svg': assetBytes,
      });

      final session = await const KoniProjectContainerStore().open(
        ProjectContainerLocation(file.path),
      );
      expect(session.document.assets.single.id, ProjectAssetId('artwork-a'));
      await session.close();
    },
  );

  for (final variant in <String, Map<String, Uint8List> Function(Uint8List)>{
    'an undeclared extra entry': (bytes) => {
      'assets/artwork/artwork-a.svg': bytes,
      'metadata/unapproved.json': Uint8List.fromList(const [0x7b, 0x7d]),
    },
    'a missing declared entry': (_) => const {},
    'an entry inconsistent with asset kind/media type': (bytes) => {
      'assets/hands/artwork-a.png': bytes,
    },
  }.entries) {
    test('open rejects ${variant.key}', () async {
      final file = File('${directory.path}/membership.handdraw');
      await _writeContainer(file, manifestBytes, variant.value(assetBytes));

      await expectLater(
        const KoniProjectContainerStore().open(
          ProjectContainerLocation(file.path),
        ),
        throwsA(_failure(ProjectContainerFailureCode.invalidContainer)),
      );
    });
  }

  test('manifest SHA must match the raw bytes with a valid ZIP CRC', () async {
    final file = File('${directory.path}/sha.handdraw');
    await _writeContainer(file, manifestBytes, {
      'assets/artwork/artwork-a.svg': Uint8List.fromList(
        utf8.encode('<svg>changed</svg>'),
      ),
    });

    await expectLater(
      const KoniProjectContainerStore().open(
        ProjectContainerLocation(file.path),
      ),
      throwsA(_failure(ProjectContainerFailureCode.contentMismatch)),
    );
  });

  test(
    'manifest size is rejected before malformed JSON can be parsed',
    () async {
      final file = File('${directory.path}/large-manifest.handdraw');
      await _writeContainer(file, Uint8List(64), const {});
      const store = KoniProjectContainerStore(
        limits: ProjectContainerLimits(maxManifestBytes: 32),
      );

      await expectLater(
        store.open(ProjectContainerLocation(file.path)),
        throwsA(
          isA<ProjectContainerException>()
              .having(
                (error) => error.code,
                'code',
                ProjectContainerFailureCode.invalidContainer,
              )
              .having(
                (error) => error.message,
                'message',
                contains('exactly one bounded manifest'),
              ),
        ),
      );
    },
  );

  test('multiple manifest entries are rejected', () async {
    final file = File('${directory.path}/duplicate-manifest.handdraw');
    final sink = await FileByteSink.create(file.path);
    final writer = const ZipWriteFormat().openWriter(
      sink,
      const ArchiveWriteOptions(),
    );
    try {
      for (var index = 0; index < 2; index++) {
        await writer.addBytes(
          ArchiveEntrySpec(path: 'manifest.json'),
          manifestBytes,
        );
      }
      await writer.close();
    } finally {
      await sink.close();
    }

    await expectLater(
      const KoniProjectContainerStore().open(
        ProjectContainerLocation(file.path),
      ),
      throwsA(_failure(ProjectContainerFailureCode.invalidContainer)),
    );
  });
}

Matcher _failure(ProjectContainerFailureCode code) =>
    isA<ProjectContainerException>().having(
      (error) => error.code,
      'code',
      code,
    );

Future<void> _writeContainer(
  File file,
  Uint8List manifest,
  Map<String, Uint8List> assets,
) async {
  final sink = await FileByteSink.create(file.path);
  final writer = const ZipWriteFormat().openWriter(
    sink,
    const ArchiveWriteOptions(),
  );
  try {
    await writer.addBytes(
      ArchiveEntrySpec(
        path: 'manifest.json',
        compression: ArchiveCompression.stored,
      ),
      manifest,
    );
    for (final entry in assets.entries) {
      await writer.addBytes(
        ArchiveEntrySpec(
          path: entry.key,
          compression: ArchiveCompression.stored,
        ),
        entry.value,
      );
    }
    await writer.close();
  } finally {
    await sink.close();
  }
}

ProjectDocument _document(Uint8List bytes) {
  final assetId = ProjectAssetId('artwork-a');
  return ProjectDocument(
    id: ProjectId('consistency-project'),
    title: 'Consistency',
    canvas: const ProjectCanvas(width: 1920, height: 1080),
    frameRate: FrameRate.fps30,
    duration: TimelineDuration.fromMicroseconds(1000000),
    artworkAssetId: assetId,
    assets: [
      ProjectAsset(
        id: assetId,
        kind: ProjectAssetKind.artwork,
        originalFileName: 'art.svg',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:${sha256.convert(bytes)}',
        mediaType: 'image/svg+xml',
        artworkSourceType: ArtworkSourceType.svg,
      ),
    ],
    strokes: const [],
    sections: const [],
    sectionOrder: const [],
    scenes: const [],
    audioTracks: const [],
  );
}
