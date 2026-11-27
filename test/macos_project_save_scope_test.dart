import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/macos_atomic_file_replacer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'native atomic save retains destination until commit and releases scope after failure',
    () async {
      if (!Platform.isMacOS) return;
      final directory = await Directory.systemTemp.createTemp('scoped-save');
      final destination = File('${directory.path}/destination.koni');
      await destination.writeAsString('previous');
      final staged = File('${directory.path}/staged.koni');
      final calls = <String>[];
      const channel = MethodChannel('handdraw_studio/exporter');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'prepareProjectSave') return staged.path;
            if (call.method == 'commitProjectSave') {
              throw PlatformException(code: 'disk-full');
            }
            return null;
          });
      try {
        const adapter = MacosAtomicFileReplacer();
        final temporary = await adapter.prepare(destination);
        await temporary.writeAsString('candidate');
        await expectLater(
          adapter.replace(temporary: temporary, destination: destination),
          throwsA(isA<PlatformException>()),
        );
        await adapter.finish(temporary);
        expect(await destination.readAsString(), 'previous');
        expect(calls, [
          'prepareProjectSave',
          'commitProjectSave',
          'finishProjectSave',
        ]);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      }
    },
  );
}
