import 'dart:io';

import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';

abstract interface class AtomicFileReplacer {
  void ensureSupported();

  Future<void> replace({required File temporary, required File destination});
}

/// POSIX same-directory rename is atomic. Windows is deliberately blocked
/// until the approved ReplaceFileW implementation and CI gate exist.
final class QualifiedAtomicFileReplacer implements AtomicFileReplacer {
  const QualifiedAtomicFileReplacer();

  @override
  void ensureSupported() {
    if (Platform.isWindows) {
      throw const UnsupportedAtomicReplacementPlatform(
        'Windows Project Store requires the qualified ReplaceFileW adapter.',
      );
    }
  }

  @override
  Future<void> replace({
    required File temporary,
    required File destination,
  }) async {
    ensureSupported();
    await temporary.rename(destination.path);
  }
}

/// Optional lifetime for platforms requiring a scoped temporary location.
abstract interface class ScopedAtomicFileReplacer {
  Future<File> prepare(File destination);
  Future<void> finish(File temporary);
}
