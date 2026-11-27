import 'dart:typed_data';
import 'dart:ui';

import 'package:handdraw_studio/features/hand_library/domain/hand_library_repository.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';

/// Process-local hand library used by tests so they can never mutate the
/// user's Application Support preferences or managed custom-hand files.
final class MemoryHandLibraryRepository implements HandLibraryRepository {
  MemoryHandLibraryRepository({HandLibrarySnapshot? initial})
    : _snapshot =
          initial ??
          const HandLibrarySnapshot(
            presets: BuiltInHands.all,
            selectedPresetId: BuiltInHands.defaultPresetId,
          );

  HandLibrarySnapshot _snapshot;

  @override
  Future<HandLibrarySnapshot> load() async => _snapshot;

  @override
  Future<HandLibrarySnapshot> importCustom({
    required HandLibrarySnapshot current,
    required String sourcePath,
    required Uint8List bytes,
  }) async {
    final id = 'test-custom-${current.presets.length}';
    final preset = HandPreset(
      id: id,
      name: 'Test Custom Hand',
      source: HandPresetSource.custom,
      managedPath: sourcePath,
      originalPath: sourcePath,
      penTip: const Offset(0.18, 0.72),
      defaultScale: 0.24,
      defaultRotationDegrees: 0,
    );
    _snapshot = current.copyWith(
      presets: [...current.presets, preset],
      selectedPresetId: id,
    );
    return _snapshot;
  }

  @override
  Future<void> save(HandLibrarySnapshot snapshot) async {
    _snapshot = snapshot;
  }
}
