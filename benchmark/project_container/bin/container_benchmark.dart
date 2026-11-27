import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:handdraw_project_container_benchmark/archive_policy.dart';
import 'package:koni_archive/io.dart';
import 'package:path/path.dart' as p;

const _mib = 1024 * 1024;
const _gib = 1024 * 1024 * 1024;

enum CompressionPolicy { storeAll, deflateAll, smart }

final class BenchmarkCancelled implements Exception {
  const BenchmarkCancelled();
}

final class FixtureEntry {
  const FixtureEntry({
    required this.archivePath,
    required this.filePath,
    required this.mediaType,
    required this.size,
  });

  factory FixtureEntry.fromJson(Map<String, Object?> json) => FixtureEntry(
    archivePath: json['archivePath']! as String,
    filePath: json['filePath']! as String,
    mediaType: json['mediaType']! as String,
    size: json['size']! as int,
  );

  final String archivePath;
  final String filePath;
  final String mediaType;
  final int size;

  Map<String, Object?> toJson() => {
    'archivePath': archivePath,
    'filePath': filePath,
    'mediaType': mediaType,
    'size': size,
  };
}

Future<void> main(List<String> arguments) async {
  final options = _arguments(arguments);
  if (options.containsKey('worker')) {
    await _worker(options);
    return;
  }
  await _coordinator(options);
}

Future<void> _coordinator(Map<String, String> options) async {
  final sizes = (options['sizes'] ?? '50,500,2048')
      .split(',')
      .map(int.parse)
      .toList(growable: false);
  final outputPath = p.absolute(
    options['output'] ?? 'build/project_container_benchmark_report.json',
  );
  final base =
      options['temp'] == null
          ? await Directory.systemTemp.createTemp('handdraw-container-3a-')
          : await Directory(options['temp']!).create(recursive: true);
  final keepTemp = options.containsKey('keep-temp');
  final initialAvailableDiskBytes = await _availableBytes(base);
  final results = <Map<String, Object?>>[];
  final skipped = <Map<String, Object?>>[];
  try {
    for (final sizeMiB in sizes) {
      final targetBytes = sizeMiB * _mib;
      final available = await _availableBytes(base);
      final required = targetBytes * 3 + 2 * _gib;
      if (available < required) {
        skipped.add({
          'sizeMiB': sizeMiB,
          'reason': 'insufficient safe disk space',
          'availableBytes': available,
          'requiredBytes': required,
        });
        continue;
      }
      final fixtureDir = Directory('${base.path}/fixture-$sizeMiB');
      final generationWatch = Stopwatch()..start();
      final entries = await _generateFixture(fixtureDir, targetBytes);
      generationWatch.stop();
      final fixtureManifest = File('${fixtureDir.path}/fixture-index.json');
      await fixtureManifest.writeAsString(
        jsonEncode([for (final entry in entries) entry.toJson()]),
        flush: true,
      );

      final policyResults = <Map<String, Object?>>[];
      for (final policy in CompressionPolicy.values) {
        final workerResult = await _runWorker([
          '--worker=archive',
          '--fixture=${fixtureManifest.path}',
          '--policy=${policy.name}',
          '--archive=${base.path}/$sizeMiB-${policy.name}.handdraw',
        ]);
        policyResults.add(workerResult);
      }
      final hashResult = await _runWorker([
        '--worker=hash',
        '--fixture=${fixtureManifest.path}',
      ]);
      final cancellationResult =
          sizeMiB == sizes.first
              ? await _runWorker([
                '--worker=cancel',
                '--fixture=${fixtureManifest.path}',
                '--archive=${base.path}/cancelled.handdraw',
              ])
              : null;
      results.add({
        'sizeMiB': sizeMiB,
        'fixtureBytes': entries.fold<int>(0, (sum, entry) => sum + entry.size),
        'entryCount': entries.length,
        'generationMilliseconds': generationWatch.elapsedMilliseconds,
        'policies': policyResults,
        'standaloneSha256': hashResult,
        if (cancellationResult != null) 'cancellation': cancellationResult,
      });

      for (final file in base.listSync().whereType<File>()) {
        if (file.path.endsWith('.handdraw')) await file.delete();
      }
      await fixtureDir.delete(recursive: true);
    }

    final report = <String, Object?>{
      'schemaVersion': 1,
      'generatedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'environment': {
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'dartVersion': Platform.version,
        'processorCount': Platform.numberOfProcessors,
        'benchmarkMode':
            const bool.fromEnvironment('dart.vm.product')
                ? 'AOT release'
                : 'JIT development',
        'initialAvailableDiskBytes': initialAvailableDiskBytes,
        'finalAvailableDiskBytes': await _availableBytes(base),
      },
      'fixturePolicy': {
        'temporaryDirectory': base.path,
        'committedToGit': false,
        'composition': {
          'manifest': '64 KiB JSON',
          'compressibleSvg': '10%',
          'largeVoiceAudio': '55%',
          'pngLike': '15%',
          'jpegLike': '10%',
          'manySmallMixedAssets': 'remaining 10%, up to 512 entries',
        },
      },
      'results': results,
      'skipped': skipped,
    };
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );
    print('REPORT $outputPath');
  } finally {
    if (!keepTemp && await base.exists()) await base.delete(recursive: true);
  }
}

Future<void> _worker(Map<String, String> options) async {
  final entries = await _readFixtureIndex(options['fixture']!);
  final result = switch (options['worker']) {
    'archive' => await _archiveWorker(
      entries,
      CompressionPolicy.values.byName(options['policy']!),
      File(options['archive']!),
    ),
    'hash' => await _hashWorker(entries),
    'cancel' => await _cancellationWorker(entries, File(options['archive']!)),
    _ => throw ArgumentError.value(options['worker'], 'worker'),
  };
  print(jsonEncode(result));
}

Future<Map<String, Object?>> _archiveWorker(
  List<FixtureEntry> entries,
  CompressionPolicy policy,
  File output,
) async {
  final memory = _MemorySampler()..start();
  final hashes = <String, String>{};
  final writeWatch = Stopwatch()..start();
  final writer = await createArchiveFile(
    output.path,
    format: const ZipWriteFormat(),
  );
  try {
    for (final entry in entries) {
      final digestOutput = AccumulatorSink<Digest>();
      final digestInput = sha256.startChunkedConversion(digestOutput);
      await writer.addStream(
        ArchiveEntrySpec(
          path: entry.archivePath,
          compression: _compression(policy, entry.mediaType),
        ),
        _fileChunks(File(entry.filePath), onChunk: digestInput.add),
        size: entry.size,
      );
      digestInput.close();
      hashes[entry.archivePath] = 'sha256:${digestOutput.events.single}';
    }
    await writer.close();
  } catch (_) {
    try {
      await writer.close();
    } catch (_) {}
    rethrow;
  }
  writeWatch.stop();

  final openWatch = Stopwatch()..start();
  final archive = await openArchiveFile(
    output.path,
    options: const ArchiveReadOptions(
      maxEntryCount: 10000,
      maxEntrySize: 4 * _gib,
    ),
  );
  openWatch.stop();
  final descriptors = [
    for (final entry in archive.entries)
      ArchiveEntryDescriptor(
        path: entry.path,
        compressedBytes: entry.compressedSize ?? entry.uncompressedSize,
        uncompressedBytes: entry.uncompressedSize,
        isSymbolicLink: entry.type == ArchiveEntryType.symlink,
      ),
  ];
  const ArchiveSecurityPolicy().validate(descriptors);

  final readWatch = Stopwatch()..start();
  var readBytes = 0;
  for (final entry in archive.entries) {
    await for (final chunk in archive.openRead(entry)) {
      readBytes += chunk.length;
    }
  }
  readWatch.stop();
  await archive.close();
  await output.rename('${output.path}.closed');
  final closed = File('${output.path}.closed');
  final archiveBytes = await closed.length();
  await closed.delete();
  memory.stop();
  final hashFingerprint = _hashFingerprint(hashes.values);
  return {
    'policy': policy.name,
    'archiveBytes': archiveBytes,
    'saveMilliseconds': writeWatch.elapsedMilliseconds,
    'openScanMilliseconds': openWatch.elapsedMilliseconds,
    'extractReadMilliseconds': readWatch.elapsedMilliseconds,
    'readBytes': readBytes,
    'rssBaselineBytes': memory.baseline,
    'rssPeakBytes': memory.peak,
    'rssDeltaBytes': memory.peak - memory.baseline,
    'hashIntegratedWithCopy': true,
    'hashCount': hashes.length,
    'hashFingerprint': hashFingerprint,
    'handlesClosedBeforeRename': true,
  };
}

Future<Map<String, Object?>> _hashWorker(List<FixtureEntry> entries) async {
  final memory = _MemorySampler()..start();
  final watch = Stopwatch()..start();
  var count = 0;
  var formatValid = true;
  final hashes = <String>[];
  for (final entry in entries) {
    final digest = await sha256.bind(File(entry.filePath).openRead()).first;
    final formatted = 'sha256:$digest';
    formatValid &= RegExp(r'^sha256:[0-9a-f]{64}$').hasMatch(formatted);
    hashes.add(formatted);
    count++;
  }
  watch.stop();
  memory.stop();
  return {
    'algorithm': 'package:crypto 3.0.7 SHA-256',
    'hashCount': count,
    'hashFingerprint': _hashFingerprint(hashes),
    'milliseconds': watch.elapsedMilliseconds,
    'rssBaselineBytes': memory.baseline,
    'rssPeakBytes': memory.peak,
    'rssDeltaBytes': memory.peak - memory.baseline,
    'formatValid': formatValid,
    'streaming': true,
  };
}

String _hashFingerprint(Iterable<String> hashes) {
  final stable = hashes.toList(growable: false)..sort();
  return 'sha256:${sha256.convert(utf8.encode(stable.join('\n')))}';
}

Future<Map<String, Object?>> _cancellationWorker(
  List<FixtureEntry> entries,
  File output,
) async {
  final entry = entries.reduce((a, b) => a.size > b.size ? a : b);
  final writer = await createArchiveFile(
    output.path,
    format: const ZipWriteFormat(),
  );
  var cancelled = false;
  try {
    await writer.addStream(
      ArchiveEntrySpec(
        path: entry.archivePath,
        compression: ArchiveCompression.stored,
      ),
      _fileChunks(File(entry.filePath), cancelAfterBytes: 2 * _mib),
      size: entry.size,
    );
  } on BenchmarkCancelled {
    cancelled = true;
  } finally {
    try {
      await writer.close();
    } catch (_) {}
  }
  final partialBytes = await output.length();
  await output.delete();
  return {
    'cooperativeCancellationObserved': cancelled,
    'partialBytesBeforeCleanup': partialBytes,
    'partialArchiveRemoved': !await output.exists(),
    'firstClassLibraryCancellation': false,
  };
}

ArchiveCompression _compression(CompressionPolicy policy, String mediaType) {
  return switch (policy) {
    CompressionPolicy.storeAll => ArchiveCompression.stored,
    CompressionPolicy.deflateAll => ArchiveCompression.deflate,
    CompressionPolicy.smart =>
      _shouldDeflate(mediaType)
          ? ArchiveCompression.deflate
          : ArchiveCompression.stored,
  };
}

bool _shouldDeflate(String mediaType) =>
    mediaType == 'application/json' ||
    mediaType == 'image/svg+xml' ||
    mediaType.startsWith('text/');

Stream<Uint8List> _fileChunks(
  File file, {
  void Function(List<int>)? onChunk,
  int? cancelAfterBytes,
}) async* {
  var read = 0;
  await for (final chunk in file.openRead()) {
    read += chunk.length;
    if (cancelAfterBytes != null && read > cancelAfterBytes) {
      throw const BenchmarkCancelled();
    }
    onChunk?.call(chunk);
    yield chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
  }
}

Future<List<FixtureEntry>> _generateFixture(
  Directory directory,
  int targetBytes,
) async {
  await directory.create(recursive: true);
  final manifestBytes = min(64 * 1024, targetBytes ~/ 100);
  final svgBytes = targetBytes ~/ 10;
  final audioBytes = targetBytes * 55 ~/ 100;
  final pngBytes = targetBytes * 15 ~/ 100;
  final jpegBytes = targetBytes ~/ 10;
  final allocated =
      manifestBytes + svgBytes + audioBytes + pngBytes + jpegBytes;
  final smallBytes = max(0, targetBytes - allocated);
  final entries = <FixtureEntry>[];

  Future<void> add(
    String archivePath,
    String mediaType,
    int size, {
    required bool compressible,
  }) async {
    final file = File('${directory.path}/payload/$archivePath');
    await file.parent.create(recursive: true);
    await _writeSynthetic(file, size, compressible: compressible);
    entries.add(
      FixtureEntry(
        archivePath: archivePath,
        filePath: file.path,
        mediaType: mediaType,
        size: size,
      ),
    );
  }

  await add(
    'manifest.json',
    'application/json',
    manifestBytes,
    compressible: true,
  );
  await add(
    'assets/artwork/asset_svg.svg',
    'image/svg+xml',
    svgBytes,
    compressible: true,
  );
  await add(
    'assets/audio/asset_voice.m4a',
    'audio/mp4',
    audioBytes,
    compressible: false,
  );
  await add(
    'assets/artwork/asset_png.png',
    'image/png',
    pngBytes,
    compressible: false,
  );
  await add(
    'assets/artwork/asset_jpeg.jpg',
    'image/jpeg',
    jpegBytes,
    compressible: false,
  );

  final smallCount = min(512, max(32, targetBytes ~/ (4 * _mib)));
  var remaining = smallBytes;
  for (var index = 0; index < smallCount; index++) {
    final countLeft = smallCount - index;
    final size = remaining ~/ countLeft;
    remaining -= size;
    final text = index.isEven;
    await add(
      text
          ? 'assets/other/text_${index.toString().padLeft(4, '0')}.txt'
          : 'assets/other/image_${index.toString().padLeft(4, '0')}.webp',
      text ? 'text/plain' : 'image/webp',
      size,
      compressible: text,
    );
  }
  return entries;
}

Future<void> _writeSynthetic(
  File file,
  int size, {
  required bool compressible,
}) async {
  final handle = await file.open(mode: FileMode.write);
  try {
    final chunk = compressible ? _textChunk() : _binaryChunk();
    var remaining = size;
    while (remaining > 0) {
      final count = min(remaining, chunk.length);
      await handle.writeFrom(chunk, 0, count);
      remaining -= count;
    }
    await handle.flush();
  } finally {
    await handle.close();
  }
}

Uint8List _textChunk() {
  final pattern = utf8.encode(
    '<path d="M10 10 C 20 20, 40 20, 50 10" data-handdraw="vector"/>\n',
  );
  final result = Uint8List(256 * 1024);
  for (var offset = 0; offset < result.length; offset += pattern.length) {
    result.setRange(
      offset,
      min(offset + pattern.length, result.length),
      pattern,
    );
  }
  return result;
}

Uint8List _binaryChunk() {
  final result = Uint8List(_mib);
  var state = 0x6d2b79f5;
  for (var index = 0; index < result.length; index++) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    result[index] = state & 0xff;
  }
  return result;
}

Future<List<FixtureEntry>> _readFixtureIndex(String path) async {
  final raw = jsonDecode(await File(path).readAsString())! as List<Object?>;
  return [
    for (final item in raw)
      FixtureEntry.fromJson(item! as Map<String, Object?>),
  ];
}

Future<Map<String, Object?>> _runWorker(List<String> arguments) async {
  final product = const bool.fromEnvironment('dart.vm.product');
  final executable = Platform.resolvedExecutable;
  final processArguments =
      product ? arguments : [Platform.script.toFilePath(), ...arguments];
  final result = await Process.run(executable, processArguments);
  if (result.exitCode != 0) {
    throw StateError('Worker failed: ${result.stderr}\n${result.stdout}');
  }
  final lines = (result.stdout as String)
      .trim()
      .split('\n')
      .where((line) => line.trim().startsWith('{'));
  return jsonDecode(lines.last) as Map<String, Object?>;
}

Future<int> _availableBytes(Directory directory) async {
  if (!Platform.isMacOS && !Platform.isLinux) return 0x7fffffffffffffff;
  final result = await Process.run('df', ['-k', directory.path]);
  if (result.exitCode != 0) return 0;
  final lines = (result.stdout as String).trim().split('\n');
  final columns = lines.last.trim().split(RegExp(r'\s+'));
  return int.parse(columns[3]) * 1024;
}

Map<String, String> _arguments(List<String> arguments) {
  final result = <String, String>{};
  for (final argument in arguments) {
    if (!argument.startsWith('--')) continue;
    final body = argument.substring(2);
    final separator = body.indexOf('=');
    if (separator < 0) {
      result[body] = 'true';
    } else {
      result[body.substring(0, separator)] = body.substring(separator + 1);
    }
  }
  return result;
}

final class _MemorySampler {
  late final int baseline;
  late int peak;
  Timer? _timer;

  void start() {
    baseline = ProcessInfo.currentRss;
    peak = baseline;
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      peak = max(peak, ProcessInfo.currentRss);
    });
  }

  void stop() {
    peak = max(peak, ProcessInfo.currentRss);
    _timer?.cancel();
  }
}
