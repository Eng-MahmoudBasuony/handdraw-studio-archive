import 'dart:io';
import 'dart:typed_data';

import 'package:koni_archive_core/io.dart';
import 'package:koni_zip/koni_zip.dart';

Future<void> main(List<String> arguments) async {
  final output = File(arguments.single);
  final sink = await FileByteSink.create(output.path);
  final writer = const ZipWriteFormat().openWriter(
    sink,
    const ArchiveWriteOptions(),
  );
  await writer.addBytes(
    ArchiveEntrySpec(path: 'manifest.json'),
    Uint8List.fromList(const [1, 2, 3]),
  );
  await writer.close();
  await sink.close();

  final source = await FileByteSource.open(output.path);
  final reader = await const ZipFormat().openReader(
    source,
    const ArchiveReadOptions(),
  );
  final entry = reader.entries.singleWhere(
    (candidate) => candidate.path == 'manifest.json',
  );
  await reader.openRead(entry).drain<void>();
  await reader.close();
  await source.close();
  await output.delete();
}
