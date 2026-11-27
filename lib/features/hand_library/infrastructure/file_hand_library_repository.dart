import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:handdraw_studio/features/hand_library/domain/hand_library_repository.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';

class FileHandLibraryRepository implements HandLibraryRepository {
  static const _currentLibraryVersion = 5;

  FileHandLibraryRepository({Directory? supportDirectory})
    : _supportDirectory = supportDirectory ?? _defaultSupportDirectory();

  final Directory _supportDirectory;

  File get _libraryFile => File(_join(_supportDirectory.path, 'hands.json'));
  Directory get _managedHandsDirectory =>
      Directory(_join(_supportDirectory.path, 'hands'));

  @override
  Future<HandLibrarySnapshot> load() async {
    if (!await _libraryFile.exists()) return _defaultSnapshot();
    try {
      final raw = jsonDecode(await _libraryFile.readAsString());
      final json = raw as Map<String, dynamic>;
      final libraryVersion = (json['version'] as num?)?.toInt() ?? 1;
      final saved = (json['presets'] as List<dynamic>? ?? const [])
          .map((item) => HandPreset.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      final custom = saved
          .where((preset) => preset.isCustom)
          .where(
            (preset) =>
                preset.managedPath != null &&
                File(preset.managedPath!).existsSync(),
          );
      final overrides = {for (final preset in saved) preset.id: preset};
      final builtIns = BuiltInHands.all
          .map((preset) {
            final override = overrides[preset.id];
            if (override == null) return preset;
            return preset.copyWith(
              penTip: _restoredBuiltInPenTip(
                libraryVersion: libraryVersion,
                preset: preset,
                saved: override,
              ),
              defaultScale: _restoredBuiltInScale(
                libraryVersion: libraryVersion,
                preset: preset,
                saved: override,
              ),
              defaultRotationDegrees: override.defaultRotationDegrees,
            );
          })
          .toList(growable: false);
      final presets = [...builtIns, ...custom];
      final requested = json['selectedPresetId'] as String?;
      final selectedId = presets.any((preset) => preset.id == requested)
          ? requested!
          : BuiltInHands.defaultPresetId;
      final selectedPreset = presets.firstWhere(
        (preset) => preset.id == selectedId,
        orElse: () => presets.first,
      );
      final applicationDefaultsJson = json['applicationDefaults'];
      return HandLibrarySnapshot(
        presets: List.unmodifiable(presets),
        selectedPresetId: selectedId,
        applicationDefaults: applicationDefaultsJson is Map<String, dynamic>
            ? HandApplicationDefaults.fromJson(
                applicationDefaultsJson,
                fallback: selectedPreset,
              )
            : HandApplicationDefaults.fromPreset(selectedPreset),
      );
    } catch (_) {
      return _defaultSnapshot();
    }
  }

  @override
  Future<HandLibrarySnapshot> importCustom({
    required HandLibrarySnapshot current,
    required String sourcePath,
    required Uint8List bytes,
  }) async {
    await _managedHandsDirectory.create(recursive: true);
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final id = 'custom-$timestamp';
    final extension = _safeExtension(sourcePath);
    final managedPath = _join(_managedHandsDirectory.path, '$id.$extension');
    await File(managedPath).writeAsBytes(bytes, flush: true);
    final preset = HandPreset(
      id: id,
      name: _displayName(sourcePath),
      source: HandPresetSource.custom,
      managedPath: managedPath,
      originalPath: sourcePath,
      penTip: const Offset(0.18, 0.72),
      defaultScale: 0.24,
      defaultRotationDegrees: 0,
    );
    final next = current.copyWith(
      presets: [...current.presets, preset],
      selectedPresetId: id,
    );
    await save(next);
    return next;
  }

  @override
  Future<void> save(HandLibrarySnapshot snapshot) async {
    await _supportDirectory.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await _libraryFile.writeAsString(
      encoder.convert({
        'version': _currentLibraryVersion,
        'selectedPresetId': snapshot.selectedPresetId,
        'applicationDefaults': snapshot.resolvedApplicationDefaults.toJson(),
        'presets': snapshot.presets.map((preset) => preset.toJson()).toList(),
      }),
      flush: true,
    );
  }

  HandLibrarySnapshot _defaultSnapshot() => const HandLibrarySnapshot(
    presets: BuiltInHands.all,
    selectedPresetId: BuiltInHands.defaultPresetId,
  );

  static Directory _defaultSupportDirectory() {
    final environment = Platform.environment;
    if (Platform.isMacOS) {
      final userHome = environment['HOME'];
      if (userHome != null && userHome.isNotEmpty) {
        return Directory(
          _join(userHome, 'Library/Application Support/HandDraw Studio'),
        );
      }
    }
    if (Platform.isWindows) {
      final appData = environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return Directory(_join(appData, 'HandDraw Studio'));
      }
    }
    final userHome = environment['HOME'];
    if (userHome != null && userHome.isNotEmpty) {
      return Directory(_join(userHome, '.handdraw_studio'));
    }
    return Directory(_join(Directory.systemTemp.path, 'handdraw_studio'));
  }

  static String _safeExtension(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return 'png';
    final extension = name.substring(dot + 1).toLowerCase();
    return const {'png', 'jpg', 'jpeg', 'webp'}.contains(extension)
        ? extension
        : 'png';
  }

  static String _displayName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  static String _join(String parent, String child) {
    final separator = Platform.pathSeparator;
    return parent.endsWith(separator)
        ? '$parent$child'
        : '$parent$separator$child';
  }
}

Offset _restoredBuiltInPenTip({
  required int libraryVersion,
  required HandPreset preset,
  required HandPreset saved,
}) {
  if (libraryVersion >= FileHandLibraryRepository._currentLibraryVersion) {
    return saved.penTip;
  }
  // Version 1 did not distinguish shipped anchors from user overrides.
  if (libraryVersion < 2) return preset.penTip;
  // Version 2 did preserve deliberate calibration. Only replace exact values
  // that were shipped by the app, leaving every other custom point untouched.
  final old = switch (preset.id) {
    'marker-right' ||
    'marker-left' ||
    'marker-compact' => const Offset(0.18, 0.72),
    'marker-dark-right' => const Offset(0.115, 0.642),
    'marker-fineliner-right' => const Offset(0.150, 0.563),
    'marker-blue-right' => const Offset(0.190, 0.563),
    'marker-front-black-right' => const Offset(0.376, 0.045),
    'marker-technical-wheat-right' => const Offset(0.115, 0.488),
    _ => null,
  };
  return saved.penTip == old ? preset.penTip : saved.penTip;
}

double _restoredBuiltInScale({
  required int libraryVersion,
  required HandPreset preset,
  required HandPreset saved,
}) {
  if (libraryVersion >= FileHandLibraryRepository._currentLibraryVersion) {
    return saved.defaultScale;
  }
  if (preset.id == BuiltInHands.defaultPresetId &&
      (saved.defaultScale == 0.22 || saved.defaultScale == 0.24)) {
    return preset.defaultScale;
  }
  return saved.defaultScale;
}
