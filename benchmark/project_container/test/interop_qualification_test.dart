@TestOn('vm')
@Tags(['qualification'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' as reference;
import 'package:crypto/crypto.dart';
import 'package:koni_archive_core/io.dart';
import 'package:koni_zip/koni_zip.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory sandbox;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('handdraw-interop-');
  });
  tearDown(() async {
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test('Koni output is accepted by independent ZIP implementations', () async {
    final expected = await _writeRepresentativeKoniArchive(
      p.join(sandbox.path, 'koni.handdraw'),
    );
    final archivePath = p.join(sandbox.path, 'koni.handdraw');

    await _expectToolSuccess('unzip', ['-t', archivePath]);
    await _expectToolSuccess('bsdtar', ['-tf', archivePath]);
    if (Platform.isMacOS) {
      final destination = Directory(p.join(sandbox.path, 'ditto'));
      await destination.create();
      await _expectToolSuccess('ditto', [
        '-x',
        '-k',
        archivePath,
        destination.path,
      ]);
      await _expectExtractedContents(destination, expected);
    }

    final decoded = reference.ZipDecoder().decodeBytes(
      await File(archivePath).readAsBytes(),
      verify: true,
    );
    expect(decoded.length, expected.length);
    for (final entry in decoded.files) {
      expect(entry.readBytes(), expected[entry.name], reason: entry.name);
    }

    final bytes = await File(archivePath).readAsBytes();
    expect(
      _containsSignature(bytes, 0x08074b50),
      isTrue,
      reason: 'streaming output must contain standard data descriptors',
    );
  });

  test('Koni reads archives produced by independent tools', () async {
    final source = Directory(p.join(sandbox.path, 'source'));
    final expected = await _writeFixtureDirectory(source);

    if (await _toolAvailable('zip')) {
      final deflated = p.join(sandbox.path, 'infozip-deflated.handdraw');
      final stored = p.join(sandbox.path, 'infozip-stored.handdraw');
      await _runChecked('zip', ['-q', '-r', deflated, '.'], source.path);
      await _runChecked('zip', ['-q', '-0', '-r', stored, '.'], source.path);
      if (await _toolAvailable('zipinfo')) {
        final metadata = await Process.run(
          'zipinfo',
          ['-v', deflated],
          stdoutEncoding: latin1,
          stderrEncoding: latin1,
        );
        expect(metadata.exitCode, 0);
        expect('${metadata.stdout}'.toLowerCase(), contains('extra field'));
      }
      await _expectKoniContents(deflated, expected);
      await _expectKoniContents(stored, expected);
    } else {
      markTestSkipped('Info-ZIP zip is unavailable');
    }

    if (Platform.isMacOS && await _toolAvailable('ditto')) {
      final path = p.join(sandbox.path, 'apple-ditto.handdraw');
      await _runChecked('ditto', ['-c', '-k', '.', path], source.path);
      await _expectKoniContents(path, expected, allowToolMetadata: true);
    }

    final referencePath = p.join(sandbox.path, 'package-archive.handdraw');
    final output = reference.OutputFileStream(referencePath);
    final encoder = reference.ZipEncoder();
    encoder.startEncode(output);
    for (final item in expected.entries) {
      encoder.add(reference.ArchiveFile.bytes(item.key, item.value));
    }
    encoder.endEncode();
    await output.close();
    await _expectKoniContents(referencePath, expected);
  });

  test('CRC corruption and truncation fail closed', () async {
    final path = p.join(sandbox.path, 'corrupt.handdraw');
    await _writeRepresentativeKoniArchive(path, includeLargeAsset: false);
    final original = await File(path).readAsBytes();

    final marker = utf8.encode('HANDDRAW_UNIQUE_PAYLOAD_7dcb');
    final offset = _indexOf(original, marker);
    expect(offset, greaterThanOrEqualTo(0));
    final corrupted = Uint8List.fromList(original)..[offset] ^= 0xff;
    final corruptPath = p.join(sandbox.path, 'crc.handdraw');
    await File(corruptPath).writeAsBytes(corrupted);
    await expectLater(
      _drainKoni(corruptPath),
      throwsA(isA<ChecksumMismatchException>()),
    );

    final truncatedPath = p.join(sandbox.path, 'truncated.handdraw');
    await File(
      truncatedPath,
    ).writeAsBytes(original.sublist(0, original.length - 17));
    await expectLater(
      _drainKoni(truncatedPath),
      throwsA(isA<ArchiveException>()),
    );
  });
}

Future<Map<String, Uint8List>> _writeRepresentativeKoniArchive(
  String path, {
  bool includeLargeAsset = true,
}) async {
  final expected = <String, Uint8List>{
    'manifest.json': Uint8List.fromList(utf8.encode('{"version":1}')),
    'assets/artwork/asset_ascii.svg': Uint8List.fromList(
      utf8.encode('<svg>HANDDRAW_UNIQUE_PAYLOAD_7dcb</svg>' * 40),
    ),
    'assets/artwork/رسمة.svg': Uint8List.fromList(utf8.encode('<svg/>')),
    'assets/empty.bin': Uint8List(0),
    'assets/zero.txt': Uint8List(0),
    'assets/raw.bin': Uint8List.fromList(List.generate(8192, (i) => i & 0xff)),
    'assets/corrupt.bin': Uint8List.fromList(
      utf8.encode('HANDDRAW_UNIQUE_PAYLOAD_7dcb'),
    ),
  };
  if (includeLargeAsset) {
    expected['assets/large.bin'] = Uint8List.fromList(
      List.generate(8 * 1024 * 1024, (i) => (i * 31) & 0xff),
    );
  }
  final sink = await FileByteSink.create(path);
  final writer = const ZipWriteFormat().openWriter(
    sink,
    const ArchiveWriteOptions(),
  );
  for (final item in expected.entries) {
    await writer.addStream(
      ArchiveEntrySpec(
        path: item.key,
        compression:
            item.key.endsWith('.bin')
                ? ArchiveCompression.stored
                : ArchiveCompression.deflate,
      ),
      Stream.value(item.value),
      size: item.value.length,
    );
  }
  await writer.close();
  await sink.close();
  return expected;
}

Future<Map<String, Uint8List>> _writeFixtureDirectory(Directory root) async {
  final expected = <String, Uint8List>{
    'manifest.json': Uint8List.fromList(utf8.encode('{"version":1}')),
    'assets/artwork/a.svg': Uint8List.fromList(
      utf8.encode('<svg>abc</svg>' * 100),
    ),
    'assets/raw.bin': Uint8List.fromList(List.generate(4096, (i) => i & 0xff)),
    'assets/empty.txt': Uint8List(0),
    'assets/日本語.txt': Uint8List.fromList(utf8.encode('unicode')),
  };
  for (final item in expected.entries) {
    final file = File(p.join(root.path, item.key));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(item.value);
  }
  return expected;
}

Future<void> _expectKoniContents(
  String path,
  Map<String, Uint8List> expected, {
  bool allowToolMetadata = false,
}) async {
  final source = await FileByteSource.open(path);
  final reader = await const ZipFormat().openReader(
    source,
    const ArchiveReadOptions(),
  );
  try {
    final files =
        reader.entries
            .where((entry) => entry.type == ArchiveEntryType.file)
            .toList();
    if (!allowToolMetadata) expect(files.length, expected.length);
    for (final item in expected.entries) {
      final entry = files.singleWhere(
        (entry) => entry.path == item.key || entry.path == './${item.key}',
      );
      final chunks = await reader.openRead(entry).toList();
      final actual = Uint8List.fromList(
        chunks.expand((chunk) => chunk).toList(),
      );
      expect(actual, item.value, reason: item.key);
      expect(
        sha256.convert(actual),
        sha256.convert(item.value),
        reason: 'SHA-256 ${item.key}',
      );
    }
  } finally {
    await reader.close();
    await source.close();
  }
}

Future<void> _drainKoni(String path) async {
  final source = await FileByteSource.open(path);
  try {
    final reader = await const ZipFormat().openReader(
      source,
      const ArchiveReadOptions(),
    );
    try {
      for (final entry in reader.entries) {
        await reader.openRead(entry).drain<void>();
      }
    } finally {
      await reader.close();
    }
  } finally {
    await source.close();
  }
}

Future<void> _expectExtractedContents(
  Directory root,
  Map<String, Uint8List> expected,
) async {
  for (final item in expected.entries) {
    expect(
      await File(p.join(root.path, item.key)).readAsBytes(),
      item.value,
      reason: item.key,
    );
  }
}

Future<void> _expectToolSuccess(
  String executable,
  List<String> arguments,
) async {
  if (!await _toolAvailable(executable)) {
    markTestSkipped('$executable is unavailable');
    return;
  }
  final result = await Process.run(
    executable,
    arguments,
    stdoutEncoding: latin1,
    stderrEncoding: latin1,
  );
  expect(result.exitCode, 0, reason: '$executable: ${result.stderr}');
}

Future<void> _runChecked(
  String executable,
  List<String> arguments,
  String workingDirectory,
) async {
  final result = await Process.run(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    stdoutEncoding: latin1,
    stderrEncoding: latin1,
  );
  expect(result.exitCode, 0, reason: '$executable: ${result.stderr}');
}

Future<bool> _toolAvailable(String executable) async {
  final result = await Process.run(
    '/usr/bin/env',
    ['which', executable],
    stdoutEncoding: latin1,
    stderrEncoding: latin1,
  );
  return result.exitCode == 0;
}

bool _containsSignature(Uint8List bytes, int signature) {
  for (var i = 0; i <= bytes.length - 4; i++) {
    if (bytes[i] == (signature & 0xff) &&
        bytes[i + 1] == ((signature >> 8) & 0xff) &&
        bytes[i + 2] == ((signature >> 16) & 0xff) &&
        bytes[i + 3] == ((signature >> 24) & 0xff)) {
      return true;
    }
  }
  return false;
}

int _indexOf(Uint8List bytes, List<int> pattern) {
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var matches = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return i;
  }
  return -1;
}
