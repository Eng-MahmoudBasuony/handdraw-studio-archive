import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_limits.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/raw_zip_entry_scanner.dart';
import 'package:koni_archive_core/io.dart';
import 'package:koni_zip/koni_zip.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('handdraw-raw-zip-');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('rejects case-folded duplicate entry names', () async {
    final file = File('${directory.path}/duplicate.zip');
    await _writeZip(file, (writer) async {
      await writer.addBytes(
        ArchiveEntrySpec(path: 'manifest.json'),
        Uint8List(1),
      );
      await writer.addBytes(
        ArchiveEntrySpec(path: 'MANIFEST.JSON'),
        Uint8List(1),
      );
    });

    await expectLater(
      const RawZipEntryScanner().scan(file),
      throwsA(_failure(ProjectContainerFailureCode.invalidContainer)),
    );
  });

  test('rejects encryption before attempting extraction', () async {
    final file = File('${directory.path}/encrypted.zip');
    await _writeZip(
      file,
      (writer) => writer.addBytes(
        ArchiveEntrySpec(path: 'manifest.json'),
        Uint8List(16),
      ),
      options: const ArchiveWriteOptions(password: 'secret'),
    );

    await expectLater(
      const RawZipEntryScanner().scan(file),
      throwsA(_failure(ProjectContainerFailureCode.unsupportedFeature)),
    );
  });

  test('rejects symbolic links before attempting extraction', () async {
    final file = File('${directory.path}/symlink.zip');
    await _writeZip(file, (writer) async {
      await writer.addEntry(
        ArchiveEntrySpec(
          path: 'manifest.json',
          type: ArchiveEntryType.symlink,
          linkTarget: '../outside',
        ),
      );
    });

    await expectLater(
      const RawZipEntryScanner().scan(file),
      throwsA(_failure(ProjectContainerFailureCode.unsupportedFeature)),
    );
  });

  test('rejects high compression-ratio entries using metadata only', () async {
    final file = File('${directory.path}/ratio.zip');
    await _writeZip(file, (writer) async {
      await writer.addBytes(
        ArchiveEntrySpec(
          path: 'manifest.json',
          compression: ArchiveCompression.stored,
        ),
        Uint8List.fromList(const [0x7b, 0x7d]),
      );
      await writer.addBytes(
        ArchiveEntrySpec(
          path: 'assets/other/bomb.bin',
          compression: ArchiveCompression.deflate,
        ),
        Uint8List(64 * 1024),
      );
    });

    await expectLater(
      const RawZipEntryScanner(
        limits: ProjectContainerLimits(maxCompressionRatio: 10),
      ).scan(file),
      throwsA(_failure(ProjectContainerFailureCode.limitExceeded)),
    );
  });

  test(
    'rejects trailing data rather than accepting an ambiguous container',
    () async {
      final file = File('${directory.path}/trailing.zip');
      await _writeZip(file, (writer) async {
        await writer.addBytes(
          ArchiveEntrySpec(path: 'manifest.json'),
          Uint8List.fromList(const [0x7b, 0x7d]),
        );
      });
      await file.writeAsBytes(const [1, 2, 3], mode: FileMode.append);

      await expectLater(
        const RawZipEntryScanner().scan(file),
        throwsA(_failure(ProjectContainerFailureCode.invalidContainer)),
      );
    },
  );

  test('archive, aggregate, and entry byte limits are independent', () async {
    final file = File('${directory.path}/independent-limits.zip');
    await _writeZip(file, (writer) async {
      await writer.addBytes(
        ArchiveEntrySpec(
          path: 'manifest.json',
          compression: ArchiveCompression.stored,
        ),
        Uint8List(10),
      );
      await writer.addBytes(
        ArchiveEntrySpec(
          path: 'assets/other/a.bin',
          compression: ArchiveCompression.stored,
        ),
        Uint8List(10),
      );
    });

    await expectLater(
      const RawZipEntryScanner(
        limits: ProjectContainerLimits(maxArchiveBytes: 1),
      ).scan(file),
      throwsA(_failure(ProjectContainerFailureCode.limitExceeded)),
    );
    await expectLater(
      const RawZipEntryScanner(
        limits: ProjectContainerLimits(
          maxArchiveBytes: 4096,
          maxEntryBytes: 10,
          maxUncompressedBytes: 15,
        ),
      ).scan(file),
      throwsA(_failure(ProjectContainerFailureCode.limitExceeded)),
    );
    await expectLater(
      const RawZipEntryScanner(
        limits: ProjectContainerLimits(
          maxArchiveBytes: 4096,
          maxEntryBytes: 9,
          maxUncompressedBytes: 4096,
        ),
      ).scan(file),
      throwsA(_failure(ProjectContainerFailureCode.limitExceeded)),
    );
  });

  test('allowed compression methods come only from central limits', () async {
    final file = File('${directory.path}/compression-policy.zip');
    await _writeZip(file, (writer) async {
      await writer.addBytes(
        ArchiveEntrySpec(
          path: 'manifest.json',
          compression: ArchiveCompression.deflate,
        ),
        Uint8List.fromList(const [0x7b, 0x7d]),
      );
    });

    await expectLater(
      const RawZipEntryScanner(
        limits: ProjectContainerLimits(
          allowedCompressionMethods: {ProjectContainerCompressionMethod.store},
        ),
      ).scan(file),
      throwsA(_failure(ProjectContainerFailureCode.unsupportedFeature)),
    );
  });
}

Matcher _failure(ProjectContainerFailureCode code) =>
    isA<ProjectContainerException>().having(
      (error) => error.code,
      'code',
      code,
    );

Future<void> _writeZip(
  File file,
  Future<void> Function(ArchiveWriter writer) build, {
  ArchiveWriteOptions options = const ArchiveWriteOptions(),
}) async {
  final sink = await FileByteSink.create(file.path);
  final writer = const ZipWriteFormat().openWriter(sink, options);
  try {
    await build(writer);
    await writer.close();
  } finally {
    await sink.close();
  }
}
