import 'dart:io';
import 'package:flutter/services.dart';
import 'atomic_file_replacer.dart';

/// Native saves stage on the destination volume in an OS-authorized directory.
/// The selected destination is replaced only after the archive is verified.
class MacosAtomicFileReplacer
    implements AtomicFileReplacer, ScopedAtomicFileReplacer {
  const MacosAtomicFileReplacer();
  static const _channel = MethodChannel('handdraw_studio/exporter');
  static final _nativePaths = <String>{};
  @override
  void ensureSupported() =>
      const QualifiedAtomicFileReplacer().ensureSupported();
  @override
  Future<File> prepare(File destination) async {
    if (Platform.isMacOS) {
      try {
        final path = await _channel.invokeMethod<String>('prepareProjectSave', {
          'destination': destination.path,
        });
        if (path != null) {
          _nativePaths.add(path);
          return File(path);
        }
      } on MissingPluginException {
        /* Pure Dart hosts use POSIX staging. */
      }
    }
    return File(
      '${destination.path}.tmp.$pid.${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  @override
  Future<void> replace({
    required File temporary,
    required File destination,
  }) async {
    if (_nativePaths.contains(temporary.path)) {
      await _channel.invokeMethod<void>('commitProjectSave', {
        'temporary': temporary.path,
      });
    } else {
      await const QualifiedAtomicFileReplacer().replace(
        temporary: temporary,
        destination: destination,
      );
    }
  }

  @override
  Future<void> finish(File temporary) async {
    if (_nativePaths.remove(temporary.path)) {
      await _channel.invokeMethod<void>('finishProjectSave', {
        'temporary': temporary.path,
      });
    }
  }
}
