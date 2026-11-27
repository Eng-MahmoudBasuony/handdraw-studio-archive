import 'dart:io';
import 'dart:typed_data';

import 'package:handdraw_project_container_benchmark/archive_policy.dart';
import 'package:koni_archive/io.dart';
import 'package:test/test.dart';

void main() {
  test('writer rejects unsafe paths by default', () async {
    final directory = await Directory.systemTemp.createTemp('koni-path-');
    addTearDown(() => directory.delete(recursive: true));
    final writer = await createArchiveFile(
      '${directory.path}/unsafe.zip',
      format: const ZipWriteFormat(),
    );
    await expectLater(
      writer.addBytes(
        ArchiveEntrySpec(path: '../escape'),
        Uint8List.fromList(const [1]),
      ),
      throwsArgumentError,
    );
    await writer.close();
  });

  test('consumer policy rejects duplicate manifests from a real ZIP', () async {
    final directory = await Directory.systemTemp.createTemp('koni-duplicate-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/duplicate.zip';
    final writer = await createArchiveFile(
      path,
      format: const ZipWriteFormat(),
    );
    for (var index = 0; index < 2; index++) {
      await writer.addBytes(
        ArchiveEntrySpec(path: 'manifest.json'),
        Uint8List.fromList([index]),
      );
    }
    await writer.close();

    final archive = await openArchiveFile(path);
    addTearDown(archive.close);
    final descriptors = [
      for (final entry in archive.entries)
        ArchiveEntryDescriptor(
          path: entry.path,
          compressedBytes: entry.compressedSize ?? entry.uncompressedSize,
          uncompressedBytes: entry.uncompressedSize,
        ),
    ];
    expect(
      () => const ArchiveSecurityPolicy().validate(descriptors),
      throwsA(isA<ArchiveSecurityException>()),
    );
  });

  test('corrupted central directory fails without extracting', () async {
    final directory = await Directory.systemTemp.createTemp('koni-corrupt-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/corrupt.zip';
    final writer = await createArchiveFile(
      path,
      format: const ZipWriteFormat(),
    );
    await writer.addBytes(
      ArchiveEntrySpec(path: 'manifest.json'),
      Uint8List.fromList(const [1, 2, 3]),
    );
    await writer.close();
    final file = File(path);
    final handle = await file.open(mode: FileMode.append);
    final length = await handle.length();
    await handle.truncate(length - 10);
    await handle.close();

    await expectLater(openArchiveFile(path), throwsA(isA<ArchiveException>()));
  });

  test(
    'writer selects a ZIP64 local header for a declared large entry',
    () async {
      final directory = await Directory.systemTemp.createTemp('koni-zip64-');
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/zip64-probe.zip';
      final writer = await createArchiveFile(
        path,
        format: const ZipWriteFormat(),
      );
      await expectLater(
        writer.addStream(
          ArchiveEntrySpec(
            path: 'assets/audio/large.m4a',
            compression: ArchiveCompression.stored,
          ),
          const Stream<Uint8List>.empty(),
          size: 0x100000000,
        ),
        throwsA(isA<ArchiveException>()),
      );
      await writer.close();

      final chunks = await File(path).openRead(0, 30).toList();
      final header = Uint8List.fromList(
        chunks.expand((chunk) => chunk).toList(),
      );
      final versionNeeded = header[4] | (header[5] << 8);
      final extraLength = header[28] | (header[29] << 8);
      expect(versionNeeded, 45);
      expect(extraLength, greaterThanOrEqualTo(20));
    },
  );
}
