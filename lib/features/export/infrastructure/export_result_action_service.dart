import 'dart:io';

import 'package:flutter/services.dart';

abstract interface class ExportResultActionService {
  Future<void> reveal(String path);
  Future<void> open(String path);
  Future<void> copyPath(String path);
}

class DesktopExportResultActionService implements ExportResultActionService {
  const DesktopExportResultActionService();

  @override
  Future<void> copyPath(String path) =>
      Clipboard.setData(ClipboardData(text: path));

  @override
  Future<void> open(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else {
      await Process.run('xdg-open', [path]);
    }
  }

  @override
  Future<void> reveal(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer.exe', [
        '/select,${File(path).absolute.path}',
      ]);
    } else {
      await Process.run('xdg-open', [File(path).parent.path]);
    }
  }
}
