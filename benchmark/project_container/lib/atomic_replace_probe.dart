import 'dart:io';

typedef ArchiveValidator = Future<bool> Function(File candidate);

final class AtomicReplaceProbe {
  const AtomicReplaceProbe();

  Future<void> replace({
    required File destination,
    required Future<void> Function(File temporary) write,
    required ArchiveValidator validate,
  }) async {
    await destination.parent.create(recursive: true);
    final temporary = File(
      '${destination.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await write(temporary);
      if (!await validate(temporary)) {
        throw const FormatException('Temporary archive validation failed.');
      }
      await temporary.rename(destination.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<int> cleanupStaleTemps(
    Directory parent, {
    required String destinationName,
    required Duration olderThan,
  }) async {
    if (!await parent.exists()) return 0;
    final cutoff = DateTime.now().subtract(olderThan);
    var removed = 0;
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is! File ||
          !entity.uri.pathSegments.last.startsWith('$destinationName.tmp.')) {
        continue;
      }
      if ((await entity.lastModified()).isBefore(cutoff)) {
        await entity.delete();
        removed++;
      }
    }
    return removed;
  }
}
