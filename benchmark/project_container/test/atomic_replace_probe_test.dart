import 'dart:convert';
import 'dart:io';

import 'package:handdraw_project_container_benchmark/atomic_replace_probe.dart';
import 'package:test/test.dart';

void main() {
  test('same-parent replacement overwrites only after validation', () async {
    final directory = await Directory.systemTemp.createTemp('atomic-probe-');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/project.handdraw');
    await destination.writeAsString('old', flush: true);

    await const AtomicReplaceProbe().replace(
      destination: destination,
      write: (temporary) => temporary.writeAsString('new', flush: true),
      validate: (candidate) async => await candidate.readAsString() == 'new',
    );

    expect(await destination.readAsString(), 'new');
    expect(directory.listSync().whereType<File>().map((file) => file.path), [
      destination.path,
    ]);
  });

  test(
    'failed validation preserves destination and cleans temporary',
    () async {
      final directory = await Directory.systemTemp.createTemp('atomic-probe-');
      addTearDown(() => directory.delete(recursive: true));
      final destination = File('${directory.path}/project.handdraw');
      await destination.writeAsString('old', flush: true);

      await expectLater(
        const AtomicReplaceProbe().replace(
          destination: destination,
          write: (temporary) => temporary.writeAsString('broken', flush: true),
          validate: (_) async => false,
        ),
        throwsFormatException,
      );

      expect(await destination.readAsString(), 'old');
      expect(directory.listSync().whereType<File>().map((file) => file.path), [
        destination.path,
      ]);
    },
  );

  test('stale same-target temporary files are recoverable', () async {
    final directory = await Directory.systemTemp.createTemp('atomic-probe-');
    addTearDown(() => directory.delete(recursive: true));
    final stale = File('${directory.path}/project.handdraw.tmp.1.old');
    await stale.writeAsBytes(utf8.encode('stale'));
    await stale.setLastModified(
      DateTime.now().subtract(const Duration(days: 2)),
    );

    final removed = await const AtomicReplaceProbe().cleanupStaleTemps(
      directory,
      destinationName: 'project.handdraw',
      olderThan: const Duration(days: 1),
    );

    expect(removed, 1);
    expect(await stale.exists(), isFalse);
  });
}
