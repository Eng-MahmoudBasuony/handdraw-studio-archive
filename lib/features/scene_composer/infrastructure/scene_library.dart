import 'dart:convert';
import 'dart:io';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';

class SceneLibraryDiagnostic {
  const SceneLibraryDiagnostic(this.path, this.message);
  final String path;
  final String message;
}

class SceneLibrary {
  SceneLibrary(this.directory);
  factory SceneLibrary.local() => SceneLibrary(
    Directory(
      '${Platform.environment['HOME']}/Library/Application Support/HandDraw Studio/scene-library',
    ),
  );
  final Directory directory;
  final _elementDiagnostics = <SceneLibraryDiagnostic>[];
  final _sceneDiagnostics = <SceneLibraryDiagnostic>[];
  List<SceneLibraryDiagnostic> get diagnostics =>
      List.unmodifiable([..._elementDiagnostics, ..._sceneDiagnostics]);

  Future<Map<String, dynamic>> _readObject(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object');
    }
    return decoded;
  }

  Future<List<SceneElement>> read() async {
    _elementDiagnostics.clear();
    final folder = Directory('${directory.path}/elements');
    if (!await folder.exists()) return [];
    final result = <SceneElement>[];
    await for (final file in folder.list()) {
      if (file is! File || !file.path.endsWith('.json')) continue;
      try {
        result.add(SceneElement.parse(await _readObject(file)));
      } on FormatException catch (error) {
        _elementDiagnostics.add(
          SceneLibraryDiagnostic(file.path, error.message),
        );
      }
    }
    return result;
  }

  Future<void> save(SceneDesign design) async {
    design = SceneDesign.parse(design.toJson());
    final folder = await Directory(
      '${directory.path}/elements',
    ).create(recursive: true);
    for (final element in design.elements) {
      final file = File('${folder.path}/${element.assetId}.json');
      await _atomic(file, element.toJson());
    }
    final templates = await Directory(
      '${directory.path}/scenes',
    ).create(recursive: true);
    await _atomic(
      File('${templates.path}/${DateTime.now().microsecondsSinceEpoch}.json'),
      design.toJson(),
    );
  }

  Future<List<SceneDesign>> scenes() async {
    _sceneDiagnostics.clear();
    final folder = Directory('${directory.path}/scenes');
    if (!await folder.exists()) return [];
    final files = await folder
        .list()
        .where((f) => f is File && f.path.endsWith('.json'))
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    final result = <SceneDesign>[];
    for (final file in files) {
      try {
        result.add(SceneDesign.parse(await _readObject(file as File)));
        if (result.length == 30) break;
      } on FormatException catch (error) {
        _sceneDiagnostics.add(SceneLibraryDiagnostic(file.path, error.message));
      }
    }
    return result;
  }

  Future<void> _atomic(File file, Object data) async {
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await temp.writeAsString(jsonEncode(data), flush: true);
    await temp.rename(file.path);
  }
}
