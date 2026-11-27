import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/features/writing_sound/application/writing_sound_preview_controller.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound_preview_player.dart';

void main() {
  test('plays and stops the selected preset at the current volume', () async {
    final player = _FakePreviewPlayer();
    final controller = WritingSoundPreviewController(player: player);
    addTearDown(controller.dispose);

    await controller.toggle(
      preset: WritingSoundPreset.recordedNaturalPaper,
      volume: 0.65,
    );

    expect(controller.status, WritingSoundPreviewStatus.playing);
    expect(player.preset, WritingSoundPreset.recordedNaturalPaper);
    expect(player.volume, 0.65);

    await controller.toggle(
      preset: WritingSoundPreset.recordedNaturalPaper,
      volume: 0.65,
    );

    expect(controller.status, WritingSoundPreviewStatus.idle);
    expect(player.stopCount, greaterThanOrEqualTo(2));
  });

  test(
    'reports a failed sample without leaking an exception to the UI',
    () async {
      final controller = WritingSoundPreviewController(
        player: _FakePreviewPlayer(shouldFail: true),
      );
      addTearDown(controller.dispose);

      await controller.play(
        preset: WritingSoundPreset.technicalPen,
        volume: 0.5,
      );

      expect(controller.status, WritingSoundPreviewStatus.failed);
      expect(controller.progress, 0);
    },
  );
}

class _FakePreviewPlayer implements WritingSoundPreviewPlayer {
  _FakePreviewPlayer({this.shouldFail = false});

  final bool shouldFail;
  WritingSoundPreset? preset;
  double? volume;
  int stopCount = 0;

  @override
  Future<void> play({
    required WritingSoundPreset preset,
    required double volume,
  }) async {
    if (shouldFail) throw StateError('preview failed');
    this.preset = preset;
    this.volume = volume;
  }

  @override
  Future<void> stop() async => stopCount++;
}
