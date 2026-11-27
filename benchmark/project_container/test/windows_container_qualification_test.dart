@TestOn('vm')
@Tags(['qualification'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:handdraw_project_container_benchmark/archive_policy.dart';
import 'package:koni_archive_core/io.dart';
import 'package:koni_zip/koni_zip.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Windows creates, fully reads, closes, renames, and deletes a container',
    () async {
      if (!Platform.isWindows) {
        markTestSkipped('Runs on the Windows qualification runner');
        return;
      }
      final directory = await Directory.systemTemp.createTemp(
        'handdraw windows عربي-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final file = File('${directory.path}\\project.handdraw');
      final sink = await FileByteSink.create(file.path);
      final writer = const ZipWriteFormat().openWriter(
        sink,
        const ArchiveWriteOptions(),
      );
      await writer.addStream(
        ArchiveEntrySpec(path: 'asset.bin'),
        Stream.value(Uint8List(64 * 1024 * 1024)),
        size: 64 * 1024 * 1024,
      );
      await writer.close();
      await sink.close();

      final source = await FileByteSource.open(file.path);
      final reader = await const ZipFormat().openReader(
        source,
        const ArchiveReadOptions(maxEntrySize: 65 * 1024 * 1024),
      );
      await reader.openRead(reader.entries.single).drain<void>();
      await reader.close();
      await source.close();

      final renamed = await file.rename('${directory.path}\\renamed.handdraw');
      await renamed.delete();
      expect(await renamed.exists(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('Windows path and case-folding contract rejects ambiguous names', () {
    if (!Platform.isWindows) {
      markTestSkipped('Runs on the Windows qualification runner');
      return;
    }
    const policy = ArchiveSecurityPolicy();
    expect(
      () => policy.validate(const [
        ArchiveEntryDescriptor(
          path: 'manifest.json',
          compressedBytes: 1,
          uncompressedBytes: 1,
        ),
        ArchiveEntryDescriptor(
          path: 'assets/A.svg',
          compressedBytes: 1,
          uncompressedBytes: 1,
        ),
        ArchiveEntryDescriptor(
          path: 'assets/a.svg',
          compressedBytes: 1,
          uncompressedBytes: 1,
        ),
      ]),
      throwsA(isA<ArchiveSecurityException>()),
    );
    for (final path in const [r'C:\project\asset.svg', r'assets\asset.svg']) {
      expect(
        () => policy.validate([
          const ArchiveEntryDescriptor(
            path: 'manifest.json',
            compressedBytes: 1,
            uncompressedBytes: 1,
          ),
          ArchiveEntryDescriptor(
            path: path,
            compressedBytes: 1,
            uncompressedBytes: 1,
          ),
        ]),
        throwsA(isA<ArchiveSecurityException>()),
      );
    }
  });

  test(
    'Windows replacement of an existing destination remains a blocking gate',
    () {},
    skip:
        'Requires the approved ReplaceFileW AtomicFileReplacer in Step 3B; '
        'delete-then-rename is forbidden.',
  );
}
