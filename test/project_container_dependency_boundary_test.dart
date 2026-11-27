import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Koni packages and ZIP implementation types stay in container infrastructure',
    () {
      const allowedDirectory = 'lib/features/project/infrastructure/container/';
      final forbiddenImports = RegExp(
        r'''package:koni_(?:zip|archive_core)(?:/[^'\"]*)?''',
      );
      final forbiddenTypes = RegExp(
        r'\b(?:ArchiveReader|ArchiveWriter|ArchiveEntry|ArchiveEntrySpec|'
        r'ArchiveCompression|ArchiveReadOptions|ArchiveWriteOptions|'
        r'ZipFormat|ZipWriteFormat|FileByteSource|FileByteSink)\b',
      );

      for (final file in Directory(
        'lib',
      ).listSync(recursive: true, followLinks: false).whereType<File>()) {
        if (!file.path.endsWith('.dart') ||
            file.path.startsWith(allowedDirectory)) {
          continue;
        }
        final source = file.readAsStringSync();
        expect(source, isNot(matches(forbiddenImports)), reason: file.path);
        expect(source, isNot(matches(forbiddenTypes)), reason: file.path);
      }
    },
  );
}
