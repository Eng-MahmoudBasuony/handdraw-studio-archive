import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';

/// Playback boundary used by the writing-sound picker.
///
/// Keeping the UI behind this contract makes the preview control reusable and
/// keeps native audio and temporary-file concerns out of presentation code.
abstract interface class WritingSoundPreviewPlayer {
  Future<void> play({
    required WritingSoundPreset preset,
    required double volume,
  });

  Future<void> stop();
}
