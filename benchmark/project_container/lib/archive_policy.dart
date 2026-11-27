enum BenchmarkAssetKind { artwork, audio, hand, other }

final class ArchiveEntryNamingPolicy {
  const ArchiveEntryNamingPolicy();

  static const _extensionByMediaType = <String, String>{
    'application/json': 'json',
    'image/svg+xml': 'svg',
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/webp': 'webp',
    'audio/mp4': 'm4a',
    'audio/mpeg': 'mp3',
    'audio/aac': 'aac',
    'audio/wav': 'wav',
    'video/quicktime': 'mov',
    'text/plain': 'txt',
  };

  String assetEntry({
    required String assetId,
    required BenchmarkAssetKind kind,
    required String validatedMediaType,
  }) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(assetId)) {
      throw ArgumentError.value(assetId, 'assetId', 'Unsafe persistent ID');
    }
    final extension = _extensionByMediaType[validatedMediaType];
    if (extension == null) {
      throw UnsupportedMediaTypeException(validatedMediaType);
    }
    final directory = switch (kind) {
      BenchmarkAssetKind.artwork => 'artwork',
      BenchmarkAssetKind.audio => 'audio',
      BenchmarkAssetKind.hand => 'hands',
      BenchmarkAssetKind.other => 'other',
    };
    return 'assets/$directory/$assetId.$extension';
  }
}

final class UnsupportedMediaTypeException implements Exception {
  const UnsupportedMediaTypeException(this.mediaType);

  final String mediaType;

  @override
  String toString() => 'Unsupported media type: $mediaType';
}

final class ArchiveSecurityLimits {
  const ArchiveSecurityLimits({
    this.maximumEntries = 10000,
    // Temporary qualification ceiling: the library has ZIP64 support, but
    // HandDraw has not yet completed a real >4 GiB cross-tool write/read gate.
    this.maximumEntryBytes = 0xffffffff,
    this.maximumTotalBytes = 0xffffffff,
    this.maximumCompressionRatio = 200,
  });

  final int maximumEntries;
  final int maximumEntryBytes;
  final int maximumTotalBytes;
  final double maximumCompressionRatio;
}

final class ArchiveEntryDescriptor {
  const ArchiveEntryDescriptor({
    required this.path,
    required this.compressedBytes,
    required this.uncompressedBytes,
    this.isSymbolicLink = false,
  });

  final String path;
  final int compressedBytes;
  final int uncompressedBytes;
  final bool isSymbolicLink;
}

enum ArchiveSecurityIssue {
  unsafePath,
  duplicateEntry,
  missingManifest,
  duplicateManifest,
  symbolicLink,
  invalidSize,
  entryLimit,
  totalSizeLimit,
  compressionRatioLimit,
  unmanifestedEntry,
  missingManifestEntry,
}

final class ArchiveSecurityException implements Exception {
  const ArchiveSecurityException(this.issue, this.detail);

  final ArchiveSecurityIssue issue;
  final String detail;

  @override
  String toString() => '${issue.name}: $detail';
}

final class ArchiveSecurityPolicy {
  const ArchiveSecurityPolicy({this.limits = const ArchiveSecurityLimits()});

  final ArchiveSecurityLimits limits;

  void validate(List<ArchiveEntryDescriptor> entries) {
    if (entries.length > limits.maximumEntries) {
      throw ArchiveSecurityException(
        ArchiveSecurityIssue.entryLimit,
        '${entries.length} entries exceeds ${limits.maximumEntries}',
      );
    }

    final seen = <String>{};
    var manifestCount = 0;
    var total = 0;
    for (final entry in entries) {
      _validatePath(entry.path);
      if (entry.path == 'manifest.json') {
        manifestCount++;
        if (manifestCount > 1) {
          throw const ArchiveSecurityException(
            ArchiveSecurityIssue.duplicateManifest,
            'manifest.json',
          );
        }
      }
      final collisionKey = entry.path.toLowerCase();
      if (!seen.add(collisionKey)) {
        throw ArchiveSecurityException(
          ArchiveSecurityIssue.duplicateEntry,
          entry.path,
        );
      }
      if (entry.isSymbolicLink) {
        throw ArchiveSecurityException(
          ArchiveSecurityIssue.symbolicLink,
          entry.path,
        );
      }
      if (entry.compressedBytes < 0 ||
          entry.uncompressedBytes < 0 ||
          entry.uncompressedBytes > limits.maximumEntryBytes) {
        throw ArchiveSecurityException(
          ArchiveSecurityIssue.invalidSize,
          entry.path,
        );
      }
      if (entry.uncompressedBytes > 0 && entry.compressedBytes == 0) {
        throw ArchiveSecurityException(
          ArchiveSecurityIssue.compressionRatioLimit,
          entry.path,
        );
      }
      if (entry.compressedBytes > 0 &&
          entry.uncompressedBytes / entry.compressedBytes >
              limits.maximumCompressionRatio) {
        throw ArchiveSecurityException(
          ArchiveSecurityIssue.compressionRatioLimit,
          entry.path,
        );
      }
      total += entry.uncompressedBytes;
      if (total > limits.maximumTotalBytes) {
        throw ArchiveSecurityException(
          ArchiveSecurityIssue.totalSizeLimit,
          '$total bytes',
        );
      }
    }
    if (manifestCount == 0) {
      throw const ArchiveSecurityException(
        ArchiveSecurityIssue.missingManifest,
        'manifest.json',
      );
    }
  }

  void _validatePath(String path) {
    final segments = path.split('/');
    if (path.isEmpty ||
        path != path.trim() ||
        path.startsWith('/') ||
        path.contains(r'\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
        RegExp(r'^[A-Za-z]:').hasMatch(path) ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw ArchiveSecurityException(ArchiveSecurityIssue.unsafePath, path);
    }
  }
}

/// Enforces the closed-world container contract after `manifest.json` has
/// itself been parsed and schema-validated. Archive discovery never invents
/// assets: every payload must be declared, and every declaration must exist.
final class ArchiveManifestMembershipPolicy {
  const ArchiveManifestMembershipPolicy();

  void validate({
    required Iterable<String> archivePaths,
    required Iterable<String> declaredAssetPaths,
  }) {
    final actual =
        archivePaths.where((path) => path != 'manifest.json').toSet();
    final declared = declaredAssetPaths.toSet();
    final unexpected = actual.difference(declared).toList()..sort();
    if (unexpected.isNotEmpty) {
      throw ArchiveSecurityException(
        ArchiveSecurityIssue.unmanifestedEntry,
        unexpected.join(', '),
      );
    }
    final missing = declared.difference(actual).toList()..sort();
    if (missing.isNotEmpty) {
      throw ArchiveSecurityException(
        ArchiveSecurityIssue.missingManifestEntry,
        missing.join(', '),
      );
    }
  }
}

final class ExternalAssetContentMismatch implements Exception {
  const ExternalAssetContentMismatch({
    required this.assetId,
    required this.expectedHash,
    required this.actualHash,
  });

  final String assetId;
  final String expectedHash;
  final String actualHash;

  @override
  String toString() =>
      'External asset $assetId has $actualHash; expected $expectedHash';
}
