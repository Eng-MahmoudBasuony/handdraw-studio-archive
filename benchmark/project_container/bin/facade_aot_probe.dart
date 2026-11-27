import 'dart:io';
import 'dart:typed_data';

import 'package:koni_archive/io.dart';

Future<void> main(List<String> arguments) async {
  final output = File(arguments.single);
  final writer = await createArchiveFile(
    output.path,
    format: const ZipWriteFormat(),
  );
  await writer.addBytes(
    ArchiveEntrySpec(path: 'manifest.json'),
    Uint8List.fromList(const [1, 2, 3]),
  );
  await writer.close();

  final archive = await openArchiveFile(output.path);
  await archive.openReadPath('manifest.json').drain<void>();
  await archive.close();
  await output.delete();
}
