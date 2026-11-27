@TestOn('vm')
@Tags(['qualification', 'large'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as reference;
import 'package:koni_archive_core/io.dart';
import 'package:koni_zip/koni_zip.dart';
import 'package:test/test.dart';

void main() {
  test(
    '70,000 entries round-trip through Koni and independent readers',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'handdraw-zip64-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final path = '${directory.path}/entry-count.handdraw';
      final sink = await FileByteSink.create(path);
      final writer = const ZipWriteFormat().openWriter(
        sink,
        const ArchiveWriteOptions(compression: ArchiveCompression.stored),
      );
      for (var index = 0; index < 70000; index++) {
        await writer.addBytes(
          ArchiveEntrySpec(
            path: 'entries/e${index.toString().padLeft(5, '0')}',
          ),
          Uint8List(0),
        );
      }
      await writer.close();
      await sink.close();

      final source = await FileByteSource.open(path);
      final reader = await const ZipFormat().openReader(
        source,
        const ArchiveReadOptions(maxEntryCount: 70001),
      );
      expect(reader.entries.length, 70000);
      expect(reader.entries.last.path, 'entries/e69999');
      await reader.close();
      await source.close();

      final unzip = await Process.run('unzip', ['-tqq', path]);
      expect(unzip.exitCode, 0, reason: '${unzip.stderr}');
      final bsdtar = await Process.run('bsdtar', ['-tf', path]);
      expect(bsdtar.exitCode, 0, reason: '${bsdtar.stderr}');
      expect('${bsdtar.stdout}', contains('entries/e69999'));

      final decoded = reference.ZipDecoder().decodeBytes(
        await File(path).readAsBytes(),
        verify: true,
      );
      expect(decoded.length, 70000);
      expect(decoded.last.name, 'entries/e69999');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
