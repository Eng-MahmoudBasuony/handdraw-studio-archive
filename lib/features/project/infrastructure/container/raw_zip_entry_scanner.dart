import 'dart:convert';
import 'dart:io';

import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_limits.dart';
import 'package:koni_archive_core/io.dart';

final class RawZipEntryRecord {
  const RawZipEntryRecord({
    required this.path,
    required this.compressedBytes,
    required this.uncompressedBytes,
    required this.compressionMethod,
    required this.encrypted,
  });

  final String path;
  final int compressedBytes;
  final int uncompressedBytes;
  final int compressionMethod;
  final bool encrypted;
}

/// Reads only the central-directory metadata. This preserves raw names before
/// Koni normalizes them, allowing HandDraw to reject backslashes, drive paths,
/// controls, Unicode normalization ambiguity, and duplicates itself.
final class RawZipEntryScanner {
  const RawZipEntryScanner({this.limits = const ProjectContainerLimits()});

  final ProjectContainerLimits limits;

  Future<List<RawZipEntryRecord>> scan(File file) async {
    final source = await FileByteSource.open(file.path);
    try {
      return await scanSource(source);
    } finally {
      await source.close();
    }
  }

  /// Scans the exact random-access source later handed to the ZIP reader. This
  /// avoids a path-based validation/open race where another process could swap
  /// the file between those two operations.
  Future<List<RawZipEntryRecord>> scanSource(ByteSource source) async {
    final length = source.length;
    if (length > limits.maxArchiveBytes) {
      throw _limit('Container exceeds the temporary <4 GiB limit.');
    }
    final tailLength = length.clamp(0, 65557);
    final tail = await source.read(length - tailLength, tailLength);
    final eocd = _lastSignature(tail, const [0x50, 0x4b, 0x05, 0x06]);
    if (eocd < 0 || eocd + 22 > tail.length) {
      throw _invalid('ZIP end-of-central-directory is missing.');
    }
    final eocdOffset = length - tailLength + eocd;
    final diskNumber = _u16(tail, eocd + 4);
    final centralDisk = _u16(tail, eocd + 6);
    final entriesOnDisk = _u16(tail, eocd + 8);
    final count = _u16(tail, eocd + 10);
    final centralSize = _u32(tail, eocd + 12);
    final centralOffset = _u32(tail, eocd + 16);
    final commentLength = _u16(tail, eocd + 20);
    if (diskNumber != 0 ||
        centralDisk != 0 ||
        entriesOnDisk != count ||
        eocdOffset + 22 + commentLength != length) {
      throw _invalid('Split ZIPs and trailing data are not supported.');
    }
    if (count == 0xffff ||
        centralSize == 0xffffffff ||
        centralOffset == 0xffffffff) {
      throw _limit(
        'ZIP64 byte-size containers are not yet production-qualified.',
      );
    }
    if (count > limits.maxEntryCount ||
        centralOffset + centralSize != eocdOffset) {
      throw _limit('ZIP entry count or central directory exceeds policy.');
    }

    final records = <RawZipEntryRecord>[];
    final seen = <String>{};
    var offset = centralOffset;
    var total = 0;
    for (var index = 0; index < count; index++) {
      final fixed = await source.read(offset, 46);
      if (fixed.length != 46 || _u32(fixed, 0) != 0x02014b50) {
        throw _invalid('Invalid ZIP central-directory entry $index.');
      }
      final flags = _u16(fixed, 8);
      final method = _u16(fixed, 10);
      final compressed = _u32(fixed, 20);
      final uncompressed = _u32(fixed, 24);
      final nameLength = _u16(fixed, 28);
      final extraLength = _u16(fixed, 30);
      final commentLength = _u16(fixed, 32);
      final startDisk = _u16(fixed, 34);
      final madeBySystem = fixed[5];
      final externalAttributes = _u32(fixed, 38);
      final unixMode = externalAttributes >> 16;
      final isUnixSymlink = madeBySystem == 3 && (unixMode & 0xf000) == 0xa000;
      if (startDisk != 0 || isUnixSymlink) {
        throw const ProjectContainerException(
          ProjectContainerFailureCode.unsupportedFeature,
          'Split archives and symbolic links are not supported.',
        );
      }
      if (compressed == 0xffffffff || uncompressed == 0xffffffff) {
        throw _limit('ZIP64 entry sizes are not yet production-qualified.');
      }
      final nameBytes = await source.read(offset + 46, nameLength);
      if (nameBytes.length != nameLength ||
          nameBytes.any((byte) => byte > 0x7f)) {
        throw _invalid('Project entry names must be ASCII.');
      }
      final path = ascii.decode(nameBytes);
      _validatePath(path);
      if (!seen.add(path.toLowerCase())) {
        throw _invalid('Duplicate project entry path: $path.');
      }
      if ((flags & 1) != 0 || !limits.allowsCompressionCode(method)) {
        throw const ProjectContainerException(
          ProjectContainerFailureCode.unsupportedFeature,
          'Only unencrypted ZIP Store/Deflate entries are supported.',
        );
      }
      if (uncompressed > limits.maxEntryBytes ||
          (uncompressed > 0 && compressed == 0) ||
          (compressed > 0 &&
              uncompressed / compressed > limits.maxCompressionRatio)) {
        throw _limit('Entry $path exceeds size/compression policy.');
      }
      total += uncompressed;
      if (total > limits.maxUncompressedBytes) {
        throw _limit('Total uncompressed project size exceeds policy.');
      }
      records.add(
        RawZipEntryRecord(
          path: path,
          compressedBytes: compressed,
          uncompressedBytes: uncompressed,
          compressionMethod: method,
          encrypted: (flags & 1) != 0,
        ),
      );
      offset += 46 + nameLength + extraLength + commentLength;
    }
    return records;
  }

  void _validatePath(String path) {
    final segments = path.split('/');
    if (path.isEmpty ||
        path != path.trim() ||
        path.startsWith('/') ||
        path.contains(r'\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
        RegExp(r'^[A-Za-z]:').hasMatch(path) ||
        segments.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw _invalid('Unsafe project entry path: $path.');
    }
  }

  int _lastSignature(List<int> bytes, List<int> signature) {
    for (var index = bytes.length - signature.length; index >= 0; index--) {
      var matches = true;
      for (var part = 0; part < signature.length; part++) {
        if (bytes[index + part] != signature[part]) {
          matches = false;
          break;
        }
      }
      if (matches) return index;
    }
    return -1;
  }

  int _u16(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);

  int _u32(List<int> bytes, int offset) =>
      _u16(bytes, offset) | (_u16(bytes, offset + 2) << 16);

  ProjectContainerException _invalid(String message) =>
      ProjectContainerException(
        ProjectContainerFailureCode.invalidContainer,
        message,
      );

  ProjectContainerException _limit(String message) => ProjectContainerException(
    ProjectContainerFailureCode.limitExceeded,
    message,
  );
}
