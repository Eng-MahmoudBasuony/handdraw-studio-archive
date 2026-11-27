import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/atomic_file_replacer.dart';

void main() {
  test(
    'platform replacement policy is explicit and never delete-then-rename',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'handdraw-atomic-policy-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final destination = File('${directory.path}/project.handdraw');
      final temporary = File('${destination.path}.tmp.test');
      await destination.writeAsString('old', flush: true);
      await temporary.writeAsString('new', flush: true);

      const replacer = QualifiedAtomicFileReplacer();
      if (Platform.isWindows) {
        await expectLater(
          replacer.replace(temporary: temporary, destination: destination),
          throwsA(
            isA<ProjectContainerException>().having(
              (error) => error.code,
              'code',
              ProjectContainerFailureCode.unsupportedAtomicReplacementPlatform,
            ),
          ),
        );
        expect(await destination.readAsString(), 'old');
        expect(await temporary.readAsString(), 'new');
      } else {
        await replacer.replace(temporary: temporary, destination: destination);
        expect(await destination.readAsString(), 'new');
        expect(await temporary.exists(), isFalse);
      }
    },
  );
}
