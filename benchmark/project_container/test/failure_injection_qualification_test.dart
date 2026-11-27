@TestOn('vm')
@Tags(['qualification'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:handdraw_project_container_benchmark/qualification_write_probe.dart';
import 'package:koni_archive_core/io.dart';
import 'package:koni_zip/koni_zip.dart';
import 'package:test/test.dart';

void main() {
  late Directory sandbox;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('handdraw-failure-');
  });
  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  for (final compression in const [
    ArchiveCompression.stored,
    ArchiveCompression.deflate,
  ]) {
    test(
      'cancellation cleans $compression candidate and releases handle',
      () async {
        final candidate = File('${sandbox.path}/cancel.handdraw');
        final first = Uint8List(1024);
        final stream =
            (() async* {
              yield first;
              throw const _InjectedCancellation();
            })();
        await expectLater(
          const QualificationWriteProbe().writeCandidate(
            candidate: candidate,
            content: stream,
            size: 2048,
            expectedSha256: sha256.convert(Uint8List(2048)).toString(),
            compression: compression,
          ),
          throwsA(isA<_InjectedCancellation>()),
        );
        expect(await candidate.exists(), isFalse);
        await File(candidate.path).writeAsString('handle released');
        await candidate.delete();
      },
    );
  }

  test(
    'source read failure and post-close failure leave no candidate',
    () async {
      final candidate = File('${sandbox.path}/failure.handdraw');
      await expectLater(
        const QualificationWriteProbe().writeCandidate(
          candidate: candidate,
          content: Stream.error(const _InjectedSourceFailure()),
          size: 1,
          expectedSha256: sha256.convert(const <int>[0]).toString(),
          compression: ArchiveCompression.stored,
        ),
        throwsA(isA<_InjectedSourceFailure>()),
      );
      expect(await candidate.exists(), isFalse);

      final bytes = Uint8List.fromList(const [1, 2, 3]);
      await expectLater(
        const QualificationWriteProbe().writeCandidate(
          candidate: candidate,
          content: Stream.value(bytes),
          size: bytes.length,
          expectedSha256: sha256.convert(bytes).toString(),
          compression: ArchiveCompression.deflate,
          afterArchiveClosed: () => throw const _InjectedReplaceFailure(),
        ),
        throwsA(isA<_InjectedReplaceFailure>()),
      );
      expect(await candidate.exists(), isFalse);
    },
  );

  test('hash mismatch and same-size source mutation fail closed', () async {
    final candidate = File('${sandbox.path}/hash.handdraw');
    final source = File('${sandbox.path}/asset.bin');
    final original = Uint8List.fromList(List.generate(4096, (i) => i & 0xff));
    await source.writeAsBytes(original);

    Stream<Uint8List> changingSource() async* {
      final handle = await source.open();
      try {
        yield Uint8List.fromList(await handle.read(2048));
        final changed = Uint8List.fromList(original)..[3000] ^= 0xff;
        await source.writeAsBytes(changed, flush: true);
        await handle.setPosition(2048);
        yield Uint8List.fromList(await handle.read(2048));
      } finally {
        await handle.close();
      }
    }

    await expectLater(
      const QualificationWriteProbe().writeCandidate(
        candidate: candidate,
        content: changingSource(),
        size: original.length,
        expectedSha256: sha256.convert(original).toString(),
        compression: ArchiveCompression.stored,
      ),
      throwsA(isA<QualificationContentMismatch>()),
    );
    expect(await candidate.exists(), isFalse);
  });

  test(
    'simulated disk-full closes the sink and returns typed failure',
    () async {
      final sink = FailingByteSink(failAfterBytes: 80);
      final writer = const ZipWriteFormat().openWriter(
        sink,
        const ArchiveWriteOptions(),
      );
      await expectLater(
        writer.addBytes(ArchiveEntrySpec(path: 'asset.bin'), Uint8List(4096)),
        throwsA(isA<InjectedStorageFailure>()),
      );
      try {
        await writer.close();
      } catch (_) {
        // A full device may also reject the central directory.
      }
      await sink.close();
      expect(sink.isClosed, isTrue);
    },
  );

  test('permission denied is surfaced without leaving an archive', () async {
    if (Platform.isWindows) {
      markTestSkipped('POSIX permission probe; Windows is covered by CI plan');
      return;
    }
    final denied = Directory('${sandbox.path}/denied');
    await denied.create();
    await Process.run('chmod', ['0555', denied.path]);
    addTearDown(() => Process.run('chmod', ['0755', denied.path]));
    final candidate = File('${denied.path}/candidate.handdraw');
    await expectLater(
      FileByteSink.create(candidate.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await candidate.exists(), isFalse);
  });
}

final class _InjectedCancellation implements Exception {
  const _InjectedCancellation();
}

final class _InjectedSourceFailure implements Exception {
  const _InjectedSourceFailure();
}

final class _InjectedReplaceFailure implements Exception {
  const _InjectedReplaceFailure();
}
