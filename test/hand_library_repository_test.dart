import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/hand_library/infrastructure/file_hand_library_repository.dart';

void main() {
  test('provides calibrated built-in hands on first launch', () async {
    final directory = await Directory.systemTemp.createTemp(
      'handdraw-hand-library-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileHandLibraryRepository(supportDirectory: directory);

    final library = await repository.load();

    expect(library.presets, hasLength(8));
    expect(library.selectedPresetId, BuiltInHands.defaultPresetId);
    expect(library.selectedPreset, BuiltInHands.wheatTechnicalPenRight);
    expect(library.selectedPreset.penTip, const Offset(0.114583, 0.485677));
    expect(library.selectedPreset.defaultScale, 0.22);
    expect(library.resolvedApplicationDefaults.scale, 0.22);
    expect(library.resolvedApplicationDefaults.rotationDegrees, 0);
    expect(library.resolvedApplicationDefaults.flipX, isFalse);
    expect(
      library.resolvedApplicationDefaults.keepHandVisibleAfterDrawing,
      isFalse,
    );
    expect(library.presets.where((preset) => preset.flipX), hasLength(1));
    expect(
      library.presets.map((preset) => preset.id),
      containsAll([
        BuiltInHands.darkMarkerRight.id,
        BuiltInHands.fineLinerRight.id,
        BuiltInHands.blueMarkerRight.id,
        BuiltInHands.frontBlackMarkerRight.id,
        BuiltInHands.wheatTechnicalPenRight.id,
      ]),
    );
  });

  test('copies custom hand and restores selection and calibration', () async {
    final directory = await Directory.systemTemp.createTemp(
      'handdraw-hand-library-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source-hand.png');
    await source.writeAsBytes(const [1, 2, 3, 4]);
    final repository = FileHandLibraryRepository(supportDirectory: directory);
    final defaults = await repository.load();

    final imported = await repository.importCustom(
      current: defaults,
      sourcePath: source.path,
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
    );
    final custom = imported.selectedPreset.copyWith(
      penTip: const Offset(0.42, 0.61),
    );
    final updated = imported.copyWith(
      presets: imported.presets
          .map((preset) => preset.id == custom.id ? custom : preset)
          .toList(),
    );
    await repository.save(updated);
    await source.delete();

    final restored = await repository.load();

    expect(restored.selectedPresetId, custom.id);
    expect(restored.selectedPreset.penTip, const Offset(0.42, 0.61));
    expect(restored.selectedPreset.managedPath, isNot(source.path));
    expect(File(restored.selectedPreset.managedPath!).existsSync(), isTrue);
  });

  test(
    'migrates stale version 1 built-in pen tip to shipped calibration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'handdraw-hand-library-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final stale = BuiltInHands.wheatTechnicalPenRight.copyWith(
        penTip: const Offset(0.11159904233870968, 0.4891696068548388),
      );
      await File('${directory.path}/hands.json').writeAsString(
        jsonEncode({
          'version': 1,
          'selectedPresetId': stale.id,
          'presets': [stale.toJson()],
        }),
      );
      final repository = FileHandLibraryRepository(supportDirectory: directory);

      final migrated = await repository.load();

      expect(migrated.selectedPreset.penTip, const Offset(0.114583, 0.485677));
    },
  );

  test(
    'version 2 shipped anchors migrate but deliberate calibration stays',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'handdraw-hand-library-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = FileHandLibraryRepository(supportDirectory: directory);
      final stale = BuiltInHands.all
          .map(
            (preset) => preset.id == BuiltInHands.darkMarkerRight.id
                ? preset.copyWith(penTip: const Offset(0.115, 0.642))
                : preset,
          )
          .toList();
      await File('${directory.path}/hands.json').writeAsString(
        jsonEncode({
          'version': 2,
          'selectedPresetId': BuiltInHands.darkMarkerRight.id,
          'presets': stale.map((preset) => preset.toJson()).toList(),
        }),
      );

      final migrated = await repository.load();
      expect(
        migrated.selectedPreset.penTip,
        BuiltInHands.darkMarkerRight.penTip,
      );

      final defaults = migrated;
      const calibratedTip = Offset(0.123, 0.456);
      final calibrated = defaults.copyWith(
        presets: defaults.presets
            .map(
              (preset) => preset.id == BuiltInHands.defaultPresetId
                  ? preset.copyWith(penTip: calibratedTip)
                  : preset,
            )
            .toList(),
        selectedPresetId: BuiltInHands.defaultPresetId,
      );
      await repository.save(calibrated);

      final restored = await repository.load();

      expect(restored.selectedPreset.penTip, calibratedTip);
      final json =
          jsonDecode(await File('${directory.path}/hands.json').readAsString())
              as Map<String, dynamic>;
      expect(json['version'], 5);
    },
  );

  test('restores application hand defaults across project sessions', () async {
    final directory = await Directory.systemTemp.createTemp(
      'handdraw-hand-library-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = FileHandLibraryRepository(supportDirectory: directory);
    final library = await repository.load();

    await repository.save(
      library.copyWith(
        selectedPresetId: BuiltInHands.markerRight.id,
        applicationDefaults: const HandApplicationDefaults(
          scale: 0.58,
          rotationDegrees: 17,
          flipX: true,
          keepHandVisibleAfterDrawing: true,
        ),
      ),
    );

    final restored = await repository.load();
    expect(restored.selectedPresetId, BuiltInHands.markerRight.id);
    expect(restored.resolvedApplicationDefaults.scale, 0.58);
    expect(restored.resolvedApplicationDefaults.rotationDegrees, 17);
    expect(restored.resolvedApplicationDefaults.flipX, isTrue);
    expect(
      restored.resolvedApplicationDefaults.keepHandVisibleAfterDrawing,
      isTrue,
    );
  });

  test('migrates the shipped small Technical Pen scale only', () async {
    final directory = await Directory.systemTemp.createTemp(
      'handdraw-hand-library-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stale = BuiltInHands.wheatTechnicalPenRight.copyWith(
      defaultScale: 0.22,
    );
    await File('${directory.path}/hands.json').writeAsString(
      jsonEncode({
        'version': 3,
        'selectedPresetId': stale.id,
        'presets': [stale.toJson()],
      }),
    );

    final migrated = await FileHandLibraryRepository(
      supportDirectory: directory,
    ).load();

    expect(migrated.selectedPreset.defaultScale, 0.22);
  });
}
