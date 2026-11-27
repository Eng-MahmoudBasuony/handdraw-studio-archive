import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:koni_archive_core/io.dart';
import 'package:koni_zip/koni_zip.dart';

final class QualificationContentMismatch implements Exception {
  const QualificationContentMismatch(this.expected, this.actual);

  final String expected;
  final String actual;
}

/// Qualification-only probe for the cleanup and integrity contract expected
/// from the future Project Store. It deliberately does not replace a project.
final class QualificationWriteProbe {
  const QualificationWriteProbe();

  Future<void> writeCandidate({
    required File candidate,
    required Stream<Uint8List> content,
    required int size,
    required String expectedSha256,
    required ArchiveCompression compression,
    Future<void> Function()? afterArchiveClosed,
  }) async {
    FileByteSink? sink;
    ArchiveWriter? writer;
    final digestOutput = AccumulatorSink<Digest>();
    final digestSink = sha256.startChunkedConversion(digestOutput);
    try {
      sink = await FileByteSink.create(candidate.path);
      writer = const ZipWriteFormat().openWriter(
        sink,
        const ArchiveWriteOptions(),
      );
      await writer.addStream(
        ArchiveEntrySpec(path: 'asset.bin', compression: compression),
        _hashing(content, digestSink),
        size: size,
      );
      await writer.close();
      writer = null;
      await sink.close();
      sink = null;
      final actual = digestOutput.events.single.toString();
      if (actual != expectedSha256) {
        throw QualificationContentMismatch(expectedSha256, actual);
      }
      await afterArchiveClosed?.call();
    } finally {
      try {
        await writer?.close();
      } catch (_) {
        // Preserve the triggering error; cleanup is best-effort after a
        // writer has already failed while consuming its source.
      }
      try {
        await sink?.close();
      } catch (_) {
        // Same rule for a failed storage device.
      }
      if (await candidate.exists()) await candidate.delete();
    }
  }

  Stream<Uint8List> _hashing(
    Stream<Uint8List> source,
    ByteConversionSink digest,
  ) async* {
    try {
      await for (final chunk in source) {
        digest.add(chunk);
        yield chunk;
      }
    } finally {
      digest.close();
    }
  }
}

final class InjectedStorageFailure implements Exception {
  const InjectedStorageFailure();
}

final class FailingByteSink implements ByteSink {
  FailingByteSink({required this.failAfterBytes});

  final int failAfterBytes;
  var _length = 0;
  var isClosed = false;

  @override
  int get length => _length;

  @override
  Future<void> add(Uint8List bytes) async {
    if (isClosed) throw StateError('sink is closed');
    if (_length + bytes.length > failAfterBytes) {
      throw const InjectedStorageFailure();
    }
    _length += bytes.length;
  }

  @override
  Future<void> close() async => isClosed = true;
}
