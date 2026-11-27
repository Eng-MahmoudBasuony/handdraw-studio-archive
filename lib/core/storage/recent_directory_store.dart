import 'dart:convert';
import 'dart:io';

class RecentDirectoryStore {
  RecentDirectoryStore({File? preferencesFile})
    : _preferencesFile = preferencesFile ?? _defaultPreferencesFile();

  static final RecentDirectoryStore instance = RecentDirectoryStore();

  final File _preferencesFile;

  Future<String?> directoryFor(String key) async {
    final values = await _read();
    final path = values[key];
    if (path is! String || path.isEmpty) return null;
    return Directory(path).existsSync() ? path : null;
  }

  Future<void> rememberFile(String key, String filePath) async {
    await rememberDirectory(key, File(filePath).parent.path);
  }

  Future<void> rememberDirectory(String key, String directoryPath) async {
    if (!Directory(directoryPath).existsSync()) return;
    final values = await _read();
    values[key] = directoryPath;
    await _preferencesFile.parent.create(recursive: true);
    await _preferencesFile.writeAsString(jsonEncode(values), flush: true);
  }

  Future<Map<String, dynamic>> _read() async {
    if (!_preferencesFile.existsSync()) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(await _preferencesFile.readAsString());
      if (decoded is Map<String, dynamic>) return Map.of(decoded);
    } catch (_) {
      // A damaged preference file should never block a file dialog.
    }
    return <String, dynamic>{};
  }

  static File _defaultPreferencesFile() {
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    return File(
      '$home/Library/Application Support/HandDraw Studio/recent-directories.json',
    );
  }
}

abstract final class RecentDirectoryKey {
  static const drawing = 'drawing';
  static const hand = 'hand';
  static const projectOpen = 'projectOpen';
  static const projectSave = 'projectSave';
  static const movieExport = 'movieExport';
  static const voiceGuide = 'voiceGuide';
}
