import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('large-payload benchmark code never reads a whole binary file', () {
    final packageRoot = Directory.current;
    final sources = <File>[
      ...Directory(
        p.join(packageRoot.path, 'bin'),
      ).listSync(recursive: true).whereType<File>(),
      ...Directory(
        p.join(packageRoot.path, 'lib'),
      ).listSync(recursive: true).whereType<File>(),
    ].where((file) => file.path.endsWith('.dart'));

    for (final source in sources) {
      final text = source.readAsStringSync();
      expect(text, isNot(contains('.readAsBytes(')), reason: source.path);
      expect(text, isNot(contains('.readAsBytesSync(')), reason: source.path);
    }
  });

  test('benchmark dependencies stay isolated from the production app', () {
    final productionPubspec =
        File(
          p.normalize(
            p.join(Directory.current.path, '..', '..', 'pubspec.yaml'),
          ),
        ).readAsStringSync();

    expect(productionPubspec, isNot(contains('\n  koni_archive:')));
    expect(productionPubspec, isNot(contains('\n  archive:')));
  });
}
